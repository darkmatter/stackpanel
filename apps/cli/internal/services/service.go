// Package services provides a pluggable service management system.
// Each service implements the Service interface and registers itself.
package services

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

// BaseDir is the root directory for all service data.
// By default, this is project-local (.stackpanel/state/services).
// Call InitForProject() to set this based on project root.
var BaseDir string

// GlobalBaseDir is the directory for global services (like Caddy)
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
	BaseDir = filepath.Join(projectDir, ".stackpanel", "state", "services")
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

// detectProjectRoot walks up from cwd looking for .stackpanel or .git
func detectProjectRoot() string {
	cwd, err := os.Getwd()
	if err != nil {
		return cwd
	}

	dir := cwd
	for {
		// Check for .stackpanel directory
		if _, err := os.Stat(filepath.Join(dir, ".stackpanel")); err == nil {
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

// Service defines the interface all services must implement
type Service interface {
	// Identity
	Name() string        // Internal name (e.g., "postgres")
	DisplayName() string // Human-readable name (e.g., "PostgreSQL")
	Aliases() []string   // Alternative names (e.g., ["pg", "postgresql"])

	// Configuration
	Port() int
	DataDir() string
	PidFile() string
	LogFile() string

	// Lifecycle
	Start() error
	Stop() error
	Status() ServiceStatus

	// Optional extended info
	StatusInfo() map[string]string // Additional status details
}

// ServiceStatus represents the current state of a service
type ServiceStatus struct {
	Running bool
	PID     int
	Port    int
	Info    map[string]string // Service-specific info
}

// BaseService provides common functionality for all services
type BaseService struct {
	name        string
	displayName string
	aliases     []string
	port        int
	dataDir     string
	pidFile     string
	logFile     string
}

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
func (b BaseService) Port() int           { return b.port }
func (b BaseService) DataDir() string     { return b.dataDir }
func (b BaseService) PidFile() string     { return b.pidFile }
func (b BaseService) LogFile() string     { return b.logFile }
func (b BaseService) ServiceDir() string  { return filepath.Dir(b.dataDir) }

// EnsureDir creates the service data directory
func (b BaseService) EnsureDir() error {
	return os.MkdirAll(b.dataDir, 0755)
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

// IsProcessRunning checks if a process is running
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

// IsPortInUse checks if a port is in use
func IsPortInUse(port int) bool {
	cmd := exec.Command("lsof", "-ti", fmt.Sprintf(":%d", port))
	output, _ := cmd.Output()
	return len(strings.TrimSpace(string(output))) > 0
}

// GetPIDOnPort returns the PID of the process using a port
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
