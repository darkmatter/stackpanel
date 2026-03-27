// Package services provides a pluggable service management system for local dev
// infrastructure (PostgreSQL, Redis, Minio, Caddy, etc.). Services self-register
// into a global Registry, get deterministic ports derived from the project's GitHub
// slug, and store runtime state (PIDs, logs, data) under .stack/state/services/.
//
// Port assignment mirrors the Nix-side algorithm in nix/stack/lib/ports.nix so that
// Go-managed and Nix-managed services agree on ports without coordination.
package services

import (
	"context"
	"crypto/md5"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	nixeval "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// Port range constants mirror the Nix port computation defaults.
// See nix/stack/lib/ports.nix for the canonical implementation.
const (
	PortMin = 3000
	PortMax = 10000
	PortMod = 100 // Ports are rounded to this modulus for clean, memorable numbers
)

// BaseDir is the root directory for all service data.
// By default, this is project-local (.stack/state/services).
// Call InitForProject() to set this based on project root.
var BaseDir string

// GlobalBaseDir is the directory for services shared across projects (like Caddy).
// Unlike BaseDir, this isn't scoped to a project since Caddy serves all projects.
var GlobalBaseDir = filepath.Join(os.Getenv("HOME"), ".local", "share", "devservices")

// projectRoot stores the detected project root directory
var projectRoot string

// initialized tracks whether InitForProject has been called
var initialized bool

func init() {
	// Set a sensible default - will be overridden by InitForProject
	BaseDir = filepath.Join(os.Getenv("HOME"), ".local", "share", "devservices")
}

// InitForProject initializes the services package for a specific project.
// This sets BaseDir to the project-local services directory.
// If projectDir is empty, it will attempt to detect the project root.
func InitForProject(projectDir string) {
	if projectDir == "" {
		projectDir = detectProjectRoot()
	}
	projectRoot = projectDir
	BaseDir = filepath.Join(projectDir, ".stack", "state", "services")
	initialized = true
}

// GetProjectRoot returns the detected or configured project root
func GetProjectRoot() string {
	if projectRoot == "" {
		projectRoot = detectProjectRoot()
	}
	return projectRoot
}

// IsInitialized returns true if InitForProject has been called
func IsInitialized() bool {
	return initialized
}

// detectProjectRoot walks up from cwd looking for .stack or .git
func detectProjectRoot() string {
	cwd, err := os.Getwd()
	if err != nil {
		return cwd
	}

	dir := cwd
	for {
		// Check for .stack directory
		if _, err := os.Stat(filepath.Join(dir, ".stack")); err == nil {
			return dir
		}
		// Check for .git directory (fallback)
		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	// Default to current directory
	return cwd
}

// Service defines the interface all managed dev services must implement.
// Implementations handle their own process lifecycle (start/stop) and health
// checking. See Registry for how services are discovered by name or alias.
type Service interface {
	// Identity
	Name() string        // Internal name used as registry key (e.g., "postgres")
	DisplayName() string // Human-readable name for CLI output (e.g., "PostgreSQL")
	Aliases() []string   // Alternative lookup names (e.g., ["pg", "postgresql"])

	// Configuration — all paths are under BaseDir/<name>/
	Port() int
	DataDir() string
	PidFile() string
	LogFile() string

	// Lifecycle — implementations must be idempotent (starting a running service is a no-op)
	Start() error
	Stop() error
	Status() ServiceStatus

	// StatusInfo returns service-specific details (e.g., connection string, version).
	// May return nil if no extra info is available.
	StatusInfo() map[string]string
}

// ServiceStatus represents the current state of a service
type ServiceStatus struct {
	Running bool
	PID     int
	Port    int
	Info    map[string]string // Service-specific info
}

// BaseService provides common functionality (PID management, directory layout,
// port computation) that concrete service implementations embed.
type BaseService struct {
	name        string
	displayName string
	aliases     []string
	port        int
	dataDir     string
	pidFile     string
	logFile     string
}

// NewBaseService creates a BaseService with conventional directory layout:
//
//	BaseDir/<name>/data/     — service data (e.g., postgres data directory)
//	BaseDir/<name>/<name>.pid — PID file for process tracking
//	BaseDir/<name>/<name>.log — log file for service output
//
// The port parameter is stored but typically overridden by StablePort() at runtime.
func NewBaseService(name, displayName string, port int, aliases ...string) BaseService {
	serviceDir := filepath.Join(BaseDir, name)
	return BaseService{
		name:        name,
		displayName: displayName,
		aliases:     aliases,
		port:        port,
		dataDir:     filepath.Join(serviceDir, "data"),
		pidFile:     filepath.Join(serviceDir, name+".pid"),
		logFile:     filepath.Join(serviceDir, name+".log"),
	}
}

func (b BaseService) Name() string        { return b.name }
func (b BaseService) DisplayName() string { return b.displayName }
func (b BaseService) Aliases() []string   { return b.aliases }
func (b BaseService) DataDir() string     { return b.dataDir }
func (b BaseService) PidFile() string     { return b.pidFile }
func (b BaseService) LogFile() string     { return b.logFile }
func (b BaseService) ServiceDir() string  { return filepath.Dir(b.dataDir) }

// EnsureDir creates the service data directory
func (b BaseService) EnsureDir() error {
	return os.MkdirAll(b.dataDir, 0755)
}

// StablePort computes a deterministic port by evaluating the project's Nix config
// to get the GitHub slug, then hashing it. This ensures all team members get the
// same port without any configuration. Returns an error if Nix eval fails.
func (b BaseService) StablePort() (int, error) {
	ctx := context.Background()
	result, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
		Expression:  nixeval.ActiveConfigPreset,
		ProjectRoot: GetProjectRoot(),
	})
	if err != nil {
		return 0, fmt.Errorf("failed to eval nix expression: %v", err)
	}
	type RepoInfo struct {
		Github string `json:"github"`
	}
	var data RepoInfo
	err = json.Unmarshal(result, &data)
	if err != nil {
		return 0, fmt.Errorf("failed to parse nix eval result: %v", err)
	}
	if data.Github == "" {
		return 0, fmt.Errorf("could not determine port: github repo info not found")
	}
	// Use github repo as key
	port := computeOverRange(
		data.Github,
		3000,
		10000,
		100,
	)
	return port, nil
}

// Port returns the stable port, silently falling back to 0 on error.
// Callers needing error handling should use StablePort() directly.
func (b BaseService) Port() int {
	p, _ := b.StablePort()
	return p
}

// ReadPID reads the PID from the pid file
func (b BaseService) ReadPID() int {
	data, err := os.ReadFile(b.pidFile)
	if err != nil {
		return 0
	}
	pid, _ := strconv.Atoi(strings.TrimSpace(string(data)))
	return pid
}

// WritePID writes the PID to the pid file
func (b BaseService) WritePID(pid int) error {
	return os.WriteFile(b.pidFile, []byte(strconv.Itoa(pid)), 0644)
}

// RemovePID removes the pid file
func (b BaseService) RemovePID() {
	os.Remove(b.pidFile)
}

// IsProcessRunning checks if a process with the given PID exists.
// Uses the Unix signal(0) trick: sending signal 0 checks permissions
// without actually delivering a signal, returning nil only if the process exists.
func IsProcessRunning(pid int) bool {
	if pid <= 0 {
		return false
	}
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	err = process.Signal(syscall.Signal(0))
	return err == nil
}

// IsPortInUse checks if a port is in use by shelling out to lsof.
// Note: requires lsof on PATH (available on macOS by default, may need
// installing on Linux). Returns false on any error, including missing lsof.
func IsPortInUse(port int) bool {
	cmd := exec.Command("lsof", "-ti", fmt.Sprintf(":%d", port))
	output, _ := cmd.Output()
	return len(strings.TrimSpace(string(output))) > 0
}

// GetPIDOnPort returns the PID of the process listening on a port.
// When multiple processes share a port, returns only the first one.
func GetPIDOnPort(port int) int {
	cmd := exec.Command("lsof", "-ti", fmt.Sprintf(":%d", port))
	output, err := cmd.Output()
	if err != nil {
		return 0
	}
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(lines) > 0 {
		pid, _ := strconv.Atoi(lines[0])
		return pid
	}
	return 0
}

// KillProcess kills a process by PID
func KillProcess(pid int, sig syscall.Signal) error {
	process, err := os.FindProcess(pid)
	if err != nil {
		return err
	}
	return process.Signal(sig)
}

// computeOverRange maps a string key to a deterministic integer in [min, max),
// rounded down to the nearest multiple of mod. Uses MD5 for distribution (not
// security). This is the Go equivalent of the Nix port computation algorithm.
func computeOverRange(
	key string,
	min int,
	max int,
	mod int,
) int {
	h := md5.Sum([]byte(key))
	hexStr := fmt.Sprintf("%x", h)[:4]
	n, _ := strconv.ParseInt(hexStr, 16, 64)
	rawOffset := n % int64(max-min)
	offsetInRange := rawOffset
	roundedOffset := offsetInRange - (offsetInRange % int64(mod))
	return min + int(roundedOffset)
}

// StablePort computes a deterministic port for a service within a project's
// port range. The two-level hashing gives each project a 100-port block, then
// assigns individual services within that block.
//
//	StablePort("darkmatter/stackpanel", "postgres") // e.g., 6410
func StablePort(
	reposlug string, // e.g., "darkmatter/stackpanel"
	service string, // e.g., "postgres"
) int {
	prange := computeOverRange(reposlug, PortMin, PortMax, PortMod)
	return computeOverRange(
		service,
		prange,
		prange+PortMod,
		1,
	)
}

// ComputePort computes a stable port for a service, auto-detecting the
// project's GitHub slug via Nix eval if reposlug is empty. Falls back to
// "default/project" if detection fails, which still gives deterministic ports
// but they won't match what the Nix side computes.
func ComputePort(serviceName string, reposlug string) int {
	if reposlug == "" {
		// Try to get from nix eval
		ctx := context.Background()
		result, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
			Expression:  nixeval.ActiveConfigPreset,
			ProjectRoot: GetProjectRoot(),
		})
		if err == nil {
			type RepoInfo struct {
				Github string `json:"github"`
			}
			var data RepoInfo
			if json.Unmarshal(result, &data) == nil && data.Github != "" {
				reposlug = data.Github
			}
		}
		// Fallback to a default if still empty
		if reposlug == "" {
			reposlug = "default/project"
		}
	}
	return StablePort(reposlug, serviceName)
}
