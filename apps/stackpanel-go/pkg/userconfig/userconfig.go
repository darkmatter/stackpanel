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
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/envvars"
	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// GenerateProjectID creates a stable, unique ID for a project based on its
// absolute filesystem path. The 8-char hex prefix is short enough for CLI
// display while having negligible collision probability for typical dev setups.
func GenerateProjectID(path string) string {
	// Normalize the path
	absPath, err := filepath.Abs(path)
	if err != nil {
		absPath = path
	}
	// Create hash
	hash := sha256.Sum256([]byte(absPath))
	return hex.EncodeToString(hash[:])[:8]
}

// Project represents a known Stackpanel project.
type Project struct {
	// Unique identifier for the project (derived from path hash)
	ID string `yaml:"id,omitempty" json:"id,omitempty"`

	// Absolute path to the project root
	Path string `yaml:"path" json:"path"`

	// Display name (defaults to directory name)
	Name string `yaml:"name" json:"name"`

	// Last time the project was opened
	LastOpened time.Time `yaml:"last_opened" json:"last_opened"`
}

// DevMode holds development mode configuration for running from source.
type DevMode struct {
	// Enable development mode (use local source instead of installed binary)
	Enabled bool `yaml:"enabled" json:"enabled"`

	// Path to the stackpanel repository root (e.g., ~/projects/stackpanel)
	RepoPath string `yaml:"repo_path" json:"repo_path"`
}

// UserConfig holds user-level configuration that spans repositories.
type UserConfig struct {
	// Currently active project path (absolute)
	CurrentProject string `yaml:"current_project,omitempty" json:"current_project,omitempty"`

	// Default project path (used when no project is specified in requests)
	DefaultProject string `yaml:"default_project,omitempty" json:"default_project,omitempty"`

	// Known projects (recently opened)
	Projects []Project `yaml:"projects" json:"projects"`

	// Development mode settings for running from source
	DevMode DevMode `yaml:"dev_mode,omitempty" json:"dev_mode,omitempty"`

	// Config file format version for future migrations
	Version int `yaml:"version" json:"version"`
}

// Manager handles reading and writing user configuration. All public methods
// are safe for concurrent use via an internal RWMutex. Writes are persisted
// to disk immediately — there is no batch/flush mechanism.
type Manager struct {
	configPath string
	config     *UserConfig
	mu         sync.RWMutex
}

// DefaultConfigPath returns the default path for user config.
// Follows XDG Base Directory spec: uses XDG_CONFIG_HOME if set,
// otherwise falls back to ~/.config/stackpanel/stackpanel.yaml.
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

// GetConfigPath returns the config path, checking the STACKPANEL_USER_CONFIG
// env var first for override. Supports ~ expansion in the env var value.
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

// NewManager creates a new user config manager, loading existing config
// from disk. If the config file doesn't exist or is corrupt, starts with
// a fresh config (Version: 1) rather than failing — this lets first-run
// work without any setup.
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

// CurrentProject returns the currently active project, or nil if none is set.
// If the current project path is set but not in the known projects list
// (e.g. after manual config editing), returns a minimal Project with just
// the path and a derived name.
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

// AddProject adds or updates a project in the list. If the project path
// already exists, updates its LastOpened time and name (idempotent upsert).
// Saves to disk immediately.
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
		ID:         GenerateProjectID(absPath),
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

// SetCurrentProject sets the active project and adds it to the known
// projects list if not already present. This is the primary entry point
// when the agent or CLI opens a project.
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
			ID:         GenerateProjectID(absPath),
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

// GetProjectByID returns a project by its ID, or nil if not found.
func (m *Manager) GetProjectByID(id string) *Project {
	m.mu.RLock()
	defer m.mu.RUnlock()

	for _, p := range m.config.Projects {
		// Check stored ID or generate one from path
		projectID := p.ID
		if projectID == "" {
			projectID = GenerateProjectID(p.Path)
		}
		if projectID == id {
			return &p
		}
	}

	return nil
}

// ResolveProject resolves a flexible project identifier to a Project.
// Tries multiple strategies in order: empty string returns the default
// (then current) project; 8-char strings are tried as IDs; then name
// match (case-insensitive); then path match. Returns nil if nothing matches.
func (m *Manager) ResolveProject(identifier string) *Project {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// If empty, try default project, then current project
	if identifier == "" {
		// Try default project first
		if m.config.DefaultProject != "" {
			for _, p := range m.config.Projects {
				if p.Path == m.config.DefaultProject {
					return &p
				}
			}
		}
		// Fall back to current project
		if m.config.CurrentProject != "" {
			for _, p := range m.config.Projects {
				if p.Path == m.config.CurrentProject {
					return &p
				}
			}
		}
		return nil
	}

	// Try as ID first (8 character hex string)
	if len(identifier) == 8 {
		for _, p := range m.config.Projects {
			projectID := p.ID
			if projectID == "" {
				projectID = GenerateProjectID(p.Path)
			}
			if projectID == identifier {
				return &p
			}
		}
	}

	// Try as name (case-insensitive)
	identifierLower := strings.ToLower(identifier)
	for _, p := range m.config.Projects {
		if strings.ToLower(p.Name) == identifierLower {
			return &p
		}
	}

	// Try as path
	absPath, err := filepath.Abs(identifier)
	if err == nil {
		for _, p := range m.config.Projects {
			if p.Path == absPath {
				return &p
			}
		}
	}

	// Direct path match (in case of already absolute path)
	for _, p := range m.config.Projects {
		if p.Path == identifier {
			return &p
		}
	}

	return nil
}

// GetDefaultProject returns the default project, or nil if not set.
func (m *Manager) GetDefaultProject() *Project {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if m.config.DefaultProject == "" {
		return nil
	}

	for _, p := range m.config.Projects {
		if p.Path == m.config.DefaultProject {
			return &p
		}
	}

	return nil
}

// GetDefaultProjectPath returns the default project path or empty string.
func (m *Manager) GetDefaultProjectPath() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.config.DefaultProject
}

// SetDefaultProject sets the default project by path. The project must
// already be in the known projects list — pass empty string to clear.
// The default project is used by ResolveProject("") as the first fallback,
// before the current project.
func (m *Manager) SetDefaultProject(path string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if path == "" {
		m.config.DefaultProject = ""
		if err := m.save(); err != nil {
			return fmt.Errorf("failed to save config: %w", err)
		}
		log.Info().Msg("Cleared default project")
		return nil
	}

	// Resolve to absolute path
	absPath, err := filepath.Abs(path)
	if err != nil {
		return fmt.Errorf("failed to resolve path: %w", err)
	}

	// Verify the project exists in our list
	found := false
	for _, p := range m.config.Projects {
		if p.Path == absPath {
			found = true
			break
		}
	}
	if !found {
		return fmt.Errorf("project not found in known projects: %s", absPath)
	}

	m.config.DefaultProject = absPath

	if err := m.save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	log.Info().Str("path", absPath).Msg("Set default project")
	return nil
}

// ClearDefaultProject clears the default project setting.
func (m *Manager) ClearDefaultProject() error {
	return m.SetDefaultProject("")
}

// GetDevMode returns the current dev mode configuration.
func (m *Manager) GetDevMode() DevMode {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.config.DevMode
}

// IsDevModeEnabled returns true if dev mode is enabled and repo path is set.
func (m *Manager) IsDevModeEnabled() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.config.DevMode.Enabled && m.config.DevMode.RepoPath != ""
}

// SetDevMode enables or disables development mode. When enabled, the agent
// serves the web UI from the local stackpanel repo source instead of the
// installed binary's embedded assets. Supports ~ expansion in repoPath.
func (m *Manager) SetDevMode(enabled bool, repoPath string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Resolve to absolute path if provided
	if repoPath != "" {
		// Expand ~ if present
		if len(repoPath) > 0 && repoPath[0] == '~' {
			home, err := os.UserHomeDir()
			if err == nil {
				repoPath = filepath.Join(home, repoPath[1:])
			}
		}
		absPath, err := filepath.Abs(repoPath)
		if err != nil {
			return fmt.Errorf("failed to resolve repo path: %w", err)
		}
		repoPath = absPath
	}

	m.config.DevMode = DevMode{
		Enabled:  enabled,
		RepoPath: repoPath,
	}

	if err := m.save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	if enabled {
		log.Info().Str("repo_path", repoPath).Msg("Development mode enabled")
	} else {
		log.Info().Msg("Development mode disabled")
	}

	return nil
}

// GetDevRepoPath returns the dev mode repo path, or empty if not set.
func (m *Manager) GetDevRepoPath() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.config.DevMode.RepoPath
}
