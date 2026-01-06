// Package userconfig manages user-level configuration that spans multiple repositories.
//
// This config is stored at ~/.config/stackpanel/stackpanel.yaml by default,
// and can be overridden with STACKPANEL_USER_CONFIG environment variable.
//
// User config includes:
//   - Projects list (known repositories the user has worked with)
//   - Current/active project path
//   - User preferences
package userconfig

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/darkmatter/stackpanel/apps/stackpanel-go/pkg/envvars"
	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// Project represents a known Stackpanel project.
type Project struct {
	// Absolute path to the project root
	Path string `yaml:"path" json:"path"`

	// Display name (defaults to directory name)
	Name string `yaml:"name" json:"name"`

	// Last time the project was opened
	LastOpened time.Time `yaml:"last_opened" json:"last_opened"`
}

// UserConfig holds user-level configuration that spans repositories.
type UserConfig struct {
	// Currently active project path (absolute)
	CurrentProject string `yaml:"current_project,omitempty" json:"current_project,omitempty"`

	// Known projects (recently opened)
	Projects []Project `yaml:"projects" json:"projects"`

	// Config file format version for future migrations
	Version int `yaml:"version" json:"version"`
}

// Manager handles reading and writing user configuration.
type Manager struct {
	configPath string
	config     *UserConfig
	mu         sync.RWMutex
}

// DefaultConfigPath returns the default path for user config.
// Uses XDG_CONFIG_HOME if set, otherwise ~/.config
func DefaultConfigPath() string {
	configDir := os.Getenv("XDG_CONFIG_HOME")
	if configDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			home = "~"
		}
		configDir = filepath.Join(home, ".config")
	}
	return filepath.Join(configDir, "stackpanel", "stackpanel.yaml")
}

// GetConfigPath returns the config path, checking env var first.
func GetConfigPath() string {
	if path := envvars.StackpanelUserConfig.Get(); path != "" {
		// Expand ~ if present
		if len(path) > 0 && path[0] == '~' {
			home, err := os.UserHomeDir()
			if err == nil {
				path = filepath.Join(home, path[1:])
			}
		}
		return path
	}
	return DefaultConfigPath()
}

// NewManager creates a new user config manager.
func NewManager() (*Manager, error) {
	configPath := GetConfigPath()

	// Ensure config directory exists
	configDir := filepath.Dir(configPath)
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		return nil, fmt.Errorf("failed to create config directory: %w", err)
	}

	m := &Manager{
		configPath: configPath,
		config:     &UserConfig{Version: 1},
	}

	if err := m.load(); err != nil && !os.IsNotExist(err) {
		log.Warn().Err(err).Str("path", configPath).Msg("Failed to load user config, starting fresh")
	}

	return m, nil
}

// load reads config from disk.
func (m *Manager) load() error {
	data, err := os.ReadFile(m.configPath)
	if err != nil {
		return err
	}

	var config UserConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return fmt.Errorf("failed to parse config file: %w", err)
	}

	m.config = &config
	return nil
}

// save persists config to disk.
func (m *Manager) save() error {
	data, err := yaml.Marshal(m.config)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	if err := os.WriteFile(m.configPath, data, 0o644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	return nil
}

// ConfigPath returns the path to the config file.
func (m *Manager) ConfigPath() string {
	return m.configPath
}

// CurrentProject returns the currently active project, or nil if none.
func (m *Manager) CurrentProject() *Project {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if m.config.CurrentProject == "" {
		return nil
	}

	for _, p := range m.config.Projects {
		if p.Path == m.config.CurrentProject {
			return &p
		}
	}

	// Current project set but not in list (return minimal info)
	return &Project{
		Path: m.config.CurrentProject,
		Name: filepath.Base(m.config.CurrentProject),
	}
}

// CurrentProjectPath returns the current project path or empty string.
func (m *Manager) CurrentProjectPath() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.config.CurrentProject
}

// ListProjects returns all known projects, sorted by last opened (most recent first).
func (m *Manager) ListProjects() []Project {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Make a copy to avoid external mutation
	projects := make([]Project, len(m.config.Projects))
	copy(projects, m.config.Projects)

	// Mark the active one
	for i := range projects {
		if projects[i].Path == m.config.CurrentProject {
			// Note: we don't have an Active field in the YAML struct,
			// but callers can check against CurrentProjectPath()
		}
	}

	return projects
}

// AddProject adds or updates a project in the list.
// If the project already exists, updates its LastOpened time.
func (m *Manager) AddProject(path, name string) (*Project, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Resolve to absolute path
	absPath, err := filepath.Abs(path)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve path: %w", err)
	}

	if name == "" {
		name = filepath.Base(absPath)
	}

	now := time.Now()

	// Check if project already exists
	for i, p := range m.config.Projects {
		if p.Path == absPath {
			m.config.Projects[i].LastOpened = now
			m.config.Projects[i].Name = name
			if err := m.save(); err != nil {
				log.Error().Err(err).Msg("Failed to save user config")
			}
			return &m.config.Projects[i], nil
		}
	}

	// Add new project
	proj := Project{
		Path:       absPath,
		Name:       name,
		LastOpened: now,
	}
	m.config.Projects = append(m.config.Projects, proj)

	if err := m.save(); err != nil {
		log.Error().Err(err).Msg("Failed to save user config")
	}

	log.Debug().Str("path", absPath).Str("name", name).Msg("Added project to user config")
	return &proj, nil
}

// SetCurrentProject sets the current project path.
// Also adds/updates the project in the list.
func (m *Manager) SetCurrentProject(path string) (*Project, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Resolve to absolute path
	absPath, err := filepath.Abs(path)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve path: %w", err)
	}

	now := time.Now()
	name := filepath.Base(absPath)

	// Update or add to projects list
	found := false
	var proj *Project
	for i, p := range m.config.Projects {
		if p.Path == absPath {
			m.config.Projects[i].LastOpened = now
			found = true
			proj = &m.config.Projects[i]
			break
		}
	}

	if !found {
		newProj := Project{
			Path:       absPath,
			Name:       name,
			LastOpened: now,
		}
		m.config.Projects = append(m.config.Projects, newProj)
		proj = &m.config.Projects[len(m.config.Projects)-1]
	}

	// Set as current
	m.config.CurrentProject = absPath

	if err := m.save(); err != nil {
		log.Error().Err(err).Msg("Failed to save user config")
	}

	log.Info().Str("path", absPath).Msg("Set current project")
	return proj, nil
}

// ClearCurrentProject clears the current project selection.
func (m *Manager) ClearCurrentProject() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.config.CurrentProject = ""

	if err := m.save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	return nil
}

// RemoveProject removes a project from the list.
// If it's the current project, also clears current.
func (m *Manager) RemoveProject(path string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	absPath, err := filepath.Abs(path)
	if err != nil {
		return fmt.Errorf("failed to resolve path: %w", err)
	}

	// Find and remove
	newProjects := make([]Project, 0, len(m.config.Projects))
	for _, p := range m.config.Projects {
		if p.Path != absPath {
			newProjects = append(newProjects, p)
		}
	}
	m.config.Projects = newProjects

	// Clear current if it was this project
	if m.config.CurrentProject == absPath {
		m.config.CurrentProject = ""
	}

	if err := m.save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	log.Debug().Str("path", absPath).Msg("Removed project from user config")
	return nil
}

// GetProject returns a project by path, or nil if not found.
func (m *Manager) GetProject(path string) *Project {
	m.mu.RLock()
	defer m.mu.RUnlock()

	absPath, err := filepath.Abs(path)
	if err != nil {
		return nil
	}

	for _, p := range m.config.Projects {
		if p.Path == absPath {
			return &p
		}
	}

	return nil
}

// HasProject checks if a project path is known.
func (m *Manager) HasProject(path string) bool {
	return m.GetProject(path) != nil
}
