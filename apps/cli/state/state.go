// Package state provides access to the Stackpanel configuration.
//
// This package supports two methods of getting configuration:
// 1. Live Nix evaluation (preferred) - always up-to-date, no state drift
// 2. State file fallback - for when Nix is not available
//
// Use Load() for automatic selection of the best method.
package state

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// State represents the stackpanel configuration
// This is compatible with both nix eval output and state.json
type State struct {
	Version     int    `json:"version"`
	ProjectName string `json:"projectName"`
	ProjectRoot string `json:"projectRoot,omitempty"`
	BasePort    int    `json:"basePort"`

	Paths    Paths              `json:"paths"`
	Apps     map[string]App     `json:"apps"`
	Services map[string]Service `json:"services"`
	Network  Network            `json:"network"`
	MOTD     MOTD               `json:"motd"`
}

// Paths contains directory paths (relative to project root)
type Paths struct {
	State string `json:"state"`
	Gen   string `json:"gen"`
	Data  string `json:"data"`
}

// App represents an application with its port and domain configuration
type App struct {
	Port   int     `json:"port"`
	Domain *string `json:"domain"`
	URL    *string `json:"url"`
	TLS    bool    `json:"tls"`
}

// Service represents an infrastructure service
type Service struct {
	Key    string `json:"key"`
	Name   string `json:"name"`
	Port   int    `json:"port"`
	EnvVar string `json:"envVar"`
}

// Network contains network configuration
type Network struct {
	Step StepConfig `json:"step"`
}

// StepConfig contains Step CA configuration
type StepConfig struct {
	Enable bool    `json:"enable"`
	CAUrl  *string `json:"caUrl"`
}

// MOTD contains message of the day configuration
type MOTD struct {
	Enable   bool          `json:"enable"`
	Commands []MOTDCommand `json:"commands"`
	Features []string      `json:"features"`
	Hints    []string      `json:"hints"`
}

// MOTDCommand represents a command to show in the MOTD
type MOTDCommand struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

// DefaultStateFile is the default name of the state file
const DefaultStateFile = "stackpanel.json"

// LoadOption configures Load behavior
type LoadOption func(*loadOptions)

type loadOptions struct {
	preferNixEval bool
	projectRoot   string
	timeout       time.Duration
}

// WithNixEval enables live Nix evaluation (default: true)
func WithNixEval(enable bool) LoadOption {
	return func(o *loadOptions) {
		o.preferNixEval = enable
	}
}

// WithProjectRoot sets the project root for Nix evaluation
func WithProjectRoot(root string) LoadOption {
	return func(o *loadOptions) {
		o.projectRoot = root
	}
}

// WithTimeout sets timeout for Nix evaluation
func WithTimeout(d time.Duration) LoadOption {
	return func(o *loadOptions) {
		o.timeout = d
	}
}

// Load gets the stackpanel configuration using the best available method.
// It tries Nix evaluation first (for live config), falling back to state file.
func Load(path string, opts ...LoadOption) (*State, error) {
	options := &loadOptions{
		preferNixEval: true,
		timeout:       10 * time.Second,
	}
	for _, opt := range opts {
		opt(options)
	}

	// Try Nix evaluation first if enabled
	if options.preferNixEval {
		state, err := loadFromNix(options)
		if err == nil {
			return state, nil
		}
		// Fall through to state file
	}

	// Fall back to state file
	return loadFromStateFile(path)
}

// loadFromNix evaluates the config using nix eval
func loadFromNix(opts *loadOptions) (*State, error) {
	projectRoot := opts.projectRoot
	if projectRoot == "" {
		projectRoot = findProjectRoot()
	}
	if projectRoot == "" {
		return nil, fmt.Errorf("could not find project root")
	}

	nixFile := filepath.Join(projectRoot, "nix", "eval", "stackpanel-config.nix")
	if _, err := os.Stat(nixFile); os.IsNotExist(err) {
		return nil, fmt.Errorf("nix eval file not found")
	}

	ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
	defer cancel()

	// Import and use nixeval package
	// For now, shell out directly to avoid circular dependency
	return evalNixConfig(ctx, projectRoot, nixFile)
}

// loadFromStateFile reads from the state.json file
func loadFromStateFile(path string) (*State, error) {
	if path == "" {
		path = findStateFile()
		if path == "" {
			return nil, fmt.Errorf("state file not found - are you in a stackpanel devenv?")
		}
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read state file: %w", err)
	}

	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("failed to parse state file: %w", err)
	}

	return &state, nil
}

// findProjectRoot searches for the project root by looking for devenv.nix
func findProjectRoot() string {
	// 1. Check DEVENV_ROOT env var
	if root := os.Getenv("DEVENV_ROOT"); root != "" {
		return root
	}

	// 2. Search up from current directory
	cwd, err := os.Getwd()
	if err != nil {
		return ""
	}

	dir := cwd
	for {
		if _, err := os.Stat(filepath.Join(dir, "devenv.nix")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	return ""
}

// findStateFile searches for the state file in standard locations
func findStateFile() string {
	// 1. Check STACKPANEL_STATE_FILE env var
	if path := os.Getenv("STACKPANEL_STATE_FILE"); path != "" {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	// 2. Check STACKPANEL_STATE_DIR env var
	if dir := os.Getenv("STACKPANEL_STATE_DIR"); dir != "" {
		path := filepath.Join(dir, DefaultStateFile)
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	// 3. Look relative to current directory
	candidates := []string{
		".stackpanel/state/stackpanel.json",
		"../.stackpanel/state/stackpanel.json",
		"../../.stackpanel/state/stackpanel.json",
	}

	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			abs, _ := filepath.Abs(c)
			return abs
		}
	}

	return ""
}

// GetApp returns app info by name, or nil if not found
func (s *State) GetApp(name string) *App {
	if app, ok := s.Apps[name]; ok {
		return &app
	}
	return nil
}

// GetService returns service info by key (lowercase), or nil if not found
func (s *State) GetService(key string) *Service {
	if svc, ok := s.Services[key]; ok {
		return &svc
	}
	return nil
}

// AppNames returns all app names in order
func (s *State) AppNames() []string {
	names := make([]string, 0, len(s.Apps))
	for name := range s.Apps {
		names = append(names, name)
	}
	return names
}

// ServiceNames returns all service names in order
func (s *State) ServiceNames() []string {
	names := make([]string, 0, len(s.Services))
	for name := range s.Services {
		names = append(names, name)
	}
	return names
}
