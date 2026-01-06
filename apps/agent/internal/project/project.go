// Package project manages Stackpanel project selection, validation, and persistence.
package project

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/rs/zerolog/log"
)

var (
	ErrNoProject       = errors.New("no project selected")
	ErrNotGitRepo      = errors.New("directory is not a git repository (no .git folder)")
	ErrNotStackpanel   = errors.New("directory is not a valid Stackpanel project")
	ErrProjectNotFound = errors.New("project directory does not exist")
)

// Project represents a Stackpanel project.
type Project struct {
	// Absolute path to the project root (contains flake.nix and .git)
	Path string `json:"path"`

	// Display name (defaults to directory name)
	Name string `json:"name"`

	// Last time the project was opened
	LastOpened time.Time `json:"last_opened"`

	// Whether this is the currently active project
	Active bool `json:"active,omitempty"`
}

// State holds the agent's project state, persisted to disk.
type State struct {
	// Currently active project path (absolute)
	CurrentProject string `json:"current_project,omitempty"`

	// Known projects (recently opened)
	Projects []Project `json:"projects"`

	// Version for future migrations
	Version int `json:"version"`
}

// Manager handles project selection, validation, and persistence.
type Manager struct {
	stateFile string
	state     *State
	mu        sync.RWMutex
}

// NewManager creates a new project manager.
// stateFile is typically ~/.stackpanel/agent-state.json
func NewManager(dataDir string) (*Manager, error) {
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return nil, fmt.Errorf("failed to create data directory: %w", err)
	}

	m := &Manager{
		stateFile: filepath.Join(dataDir, "agent-state.json"),
		state:     &State{Version: 1},
	}

	if err := m.load(); err != nil && !os.IsNotExist(err) {
		log.Warn().Err(err).Msg("Failed to load agent state, starting fresh")
	}

	return m, nil
}

// load reads state from disk.
func (m *Manager) load() error {
	data, err := os.ReadFile(m.stateFile)
	if err != nil {
		return err
	}

	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return fmt.Errorf("failed to parse state file: %w", err)
	}

	m.state = &state
	return nil
}

// save persists state to disk.
func (m *Manager) save() error {
	data, err := json.MarshalIndent(m.state, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal state: %w", err)
	}

	if err := os.WriteFile(m.stateFile, data, 0o644); err != nil {
		return fmt.Errorf("failed to write state file: %w", err)
	}

	return nil
}

// CurrentProject returns the currently active project, or ErrNoProject if none.
func (m *Manager) CurrentProject() (*Project, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if m.state.CurrentProject == "" {
		return nil, ErrNoProject
	}

	for _, p := range m.state.Projects {
		if p.Path == m.state.CurrentProject {
			proj := p
			proj.Active = true
			return &proj, nil
		}
	}

	// Project in state but not in list (shouldn't happen, but handle gracefully)
	return &Project{
		Path:   m.state.CurrentProject,
		Name:   filepath.Base(m.state.CurrentProject),
		Active: true,
	}, nil
}

// CurrentProjectPath returns the current project path or empty string.
func (m *Manager) CurrentProjectPath() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.state.CurrentProject
}

// ListProjects returns all known projects.
func (m *Manager) ListProjects() []Project {
	m.mu.RLock()
	defer m.mu.RUnlock()

	projects := make([]Project, len(m.state.Projects))
	for i, p := range m.state.Projects {
		projects[i] = p
		projects[i].Active = p.Path == m.state.CurrentProject
	}
	return projects
}

// ValidateProject checks if a directory is a valid Stackpanel project.
// Returns nil if valid, or an error describing what's wrong.
func ValidateProject(projectPath string) error {
	// Check directory exists
	info, err := os.Stat(projectPath)
	if err != nil {
		if os.IsNotExist(err) {
			return ErrProjectNotFound
		}
		return fmt.Errorf("failed to access directory: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("path is not a directory: %s", projectPath)
	}

	// Check for .git directory
	gitPath := filepath.Join(projectPath, ".git")
	if _, err := os.Stat(gitPath); os.IsNotExist(err) {
		return ErrNotGitRepo
	}

	// Validate STACKPANEL_ROOT evaluates to config.stackpanel
	if err := validateStackpanelConfig(projectPath); err != nil {
		return err
	}

	return nil
}

// validateStackpanelConfig checks that the project has a valid Stackpanel configuration.
// It evaluates the flake and checks for config.stackpanel.
func validateStackpanelConfig(projectPath string) error {
	// Build a Nix expression that:
	// 1. Imports the flake
	// 2. Checks if config.stackpanel exists and is an attrset
	expr := `
let
  flake = builtins.getFlake (toString ./.);
  # Try to find stackpanel config in common locations
  hasStackpanel =
    (flake ? stackpanel) ||
    (flake ? config && flake.config ? stackpanel) ||
    (flake ? nixosConfigurations) ||
    (flake ? darwinConfigurations) ||
    (builtins.pathExists ./.stackpanel);
in
  if hasStackpanel then "valid" else throw "No stackpanel configuration found"
`

	cmd := exec.Command("nix", "eval", "--raw", "--impure", "--expr", expr)
	cmd.Dir = projectPath
	cmd.Env = append(os.Environ(),
		"NIX_CONFIG=experimental-features = nix-command flakes",
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		// Check for common error patterns
		outStr := string(output)
		if strings.Contains(outStr, "No stackpanel configuration found") {
			return ErrNotStackpanel
		}
		if strings.Contains(outStr, "does not provide attribute") {
			return ErrNotStackpanel
		}
		if strings.Contains(outStr, "error: getting status of") || strings.Contains(outStr, "flake.nix") {
			// No flake.nix - check for .stackpanel directory as fallback
			if _, statErr := os.Stat(filepath.Join(projectPath, ".stackpanel")); statErr == nil {
				return nil // Has .stackpanel directory, consider valid
			}
			return fmt.Errorf("%w: no flake.nix or .stackpanel directory", ErrNotStackpanel)
		}

		log.Debug().
			Str("output", outStr).
			Err(err).
			Msg("Nix eval failed during project validation")

		return fmt.Errorf("failed to evaluate project configuration: %w", err)
	}

	result := strings.TrimSpace(string(output))
	if result != "valid" {
		return ErrNotStackpanel
	}

	return nil
}

// OpenProject validates and sets a project as the current project.
func (m *Manager) OpenProject(projectPath string) (*Project, error) {
	// Resolve to absolute path
	absPath, err := filepath.Abs(projectPath)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve path: %w", err)
	}

	// Validate the project
	if err := ValidateProject(absPath); err != nil {
		return nil, err
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Update or add to projects list
	found := false
	for i, p := range m.state.Projects {
		if p.Path == absPath {
			m.state.Projects[i].LastOpened = time.Now()
			found = true
			break
		}
	}

	if !found {
		m.state.Projects = append(m.state.Projects, Project{
			Path:       absPath,
			Name:       filepath.Base(absPath),
			LastOpened: time.Now(),
		})
	}

	// Set as current
	m.state.CurrentProject = absPath

	// Persist state
	if err := m.save(); err != nil {
		log.Error().Err(err).Msg("Failed to save agent state")
		// Don't fail the operation, just log
	}

	log.Info().
		Str("path", absPath).
		Msg("Opened Stackpanel project")

	return &Project{
		Path:       absPath,
		Name:       filepath.Base(absPath),
		LastOpened: time.Now(),
		Active:     true,
	}, nil
}

// CloseProject clears the current project.
func (m *Manager) CloseProject() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.state.CurrentProject = ""

	if err := m.save(); err != nil {
		return fmt.Errorf("failed to save state: %w", err)
	}

	return nil
}

// RemoveProject removes a project from the known projects list.
func (m *Manager) RemoveProject(projectPath string) error {
	absPath, err := filepath.Abs(projectPath)
	if err != nil {
		return fmt.Errorf("failed to resolve path: %w", err)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Remove from list
	newProjects := make([]Project, 0, len(m.state.Projects))
	for _, p := range m.state.Projects {
		if p.Path != absPath {
			newProjects = append(newProjects, p)
		}
	}
	m.state.Projects = newProjects

	// Clear current if it was this project
	if m.state.CurrentProject == absPath {
		m.state.CurrentProject = ""
	}

	return m.save()
}

// SetProjectName sets a custom display name for a project.
func (m *Manager) SetProjectName(projectPath, name string) error {
	absPath, err := filepath.Abs(projectPath)
	if err != nil {
		return fmt.Errorf("failed to resolve path: %w", err)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	for i, p := range m.state.Projects {
		if p.Path == absPath {
			m.state.Projects[i].Name = name
			return m.save()
		}
	}

	return fmt.Errorf("project not found: %s", absPath)
}

// QuickValidate performs a fast validation (just checks .git exists).
// Use ValidateProject for full validation including Nix eval.
func QuickValidate(projectPath string) error {
	info, err := os.Stat(projectPath)
	if err != nil {
		if os.IsNotExist(err) {
			return ErrProjectNotFound
		}
		return err
	}
	if !info.IsDir() {
		return fmt.Errorf("not a directory: %s", projectPath)
	}

	gitPath := filepath.Join(projectPath, ".git")
	if _, err := os.Stat(gitPath); os.IsNotExist(err) {
		return ErrNotGitRepo
	}

	return nil
}
