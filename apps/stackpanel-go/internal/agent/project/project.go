// Package project manages Stackpanel project selection, validation, and persistence.
package project

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
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

// Manager handles project selection, validation, and persistence.
// Projects list is stored in user config (~/.config/stackpanel/stackpanel.yaml).
type Manager struct {
	userConfig *userconfig.Manager
	mu         sync.RWMutex
}

// NewManager creates a new project manager.
// The dataDir parameter is kept for backward compatibility but is no longer used.
// Projects are now stored in ~/.config/stackpanel/stackpanel.yaml
func NewManager(dataDir string) (*Manager, error) {
	ucm, err := userconfig.NewManager()
	if err != nil {
		return nil, fmt.Errorf("failed to create user config manager: %w", err)
	}

	log.Debug().
		Str("config_path", ucm.ConfigPath()).
		Msg("Project manager initialized with user config")

	return &Manager{
		userConfig: ucm,
	}, nil
}

// CurrentProject returns the currently active project, or ErrNoProject if none.
func (m *Manager) CurrentProject() (*Project, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	proj := m.userConfig.CurrentProject()
	if proj == nil {
		return nil, ErrNoProject
	}

	return &Project{
		Path:       proj.Path,
		Name:       proj.Name,
		LastOpened: proj.LastOpened,
		Active:     true,
	}, nil
}

// CurrentProjectPath returns the current project path or empty string.
func (m *Manager) CurrentProjectPath() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.userConfig.CurrentProjectPath()
}

// ListProjects returns all known projects.
func (m *Manager) ListProjects() []Project {
	m.mu.RLock()
	defer m.mu.RUnlock()

	ucProjects := m.userConfig.ListProjects()
	currentPath := m.userConfig.CurrentProjectPath()

	projects := make([]Project, len(ucProjects))
	for i, p := range ucProjects {
		projects[i] = Project{
			Path:       p.Path,
			Name:       p.Name,
			LastOpened: p.LastOpened,
			Active:     p.Path == currentPath,
		}
	}

	return projects
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

	proj, err := m.userConfig.SetCurrentProject(absPath)
	if err != nil {
		return nil, fmt.Errorf("failed to set current project: %w", err)
	}

	log.Info().
		Str("path", absPath).
		Str("name", proj.Name).
		Msg("Opened Stackpanel project")

	return &Project{
		Path:       proj.Path,
		Name:       proj.Name,
		LastOpened: proj.LastOpened,
		Active:     true,
	}, nil
}

// CloseProject clears the current project.
func (m *Manager) CloseProject() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if err := m.userConfig.ClearCurrentProject(); err != nil {
		return fmt.Errorf("failed to clear current project: %w", err)
	}

	log.Info().Msg("Closed current project")
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

	if err := m.userConfig.RemoveProject(absPath); err != nil {
		return fmt.Errorf("failed to remove project: %w", err)
	}

	log.Info().Str("path", absPath).Msg("Removed project from list")
	return nil
}

// ValidateProject checks if a directory is a valid Stackpanel project.
func ValidateProject(projectPath string) error {
	// Check directory exists
	info, err := os.Stat(projectPath)
	if err != nil {
		if os.IsNotExist(err) {
			return ErrProjectNotFound
		}
		return fmt.Errorf("failed to stat directory: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("path is not a directory")
	}

	// Check for .git directory
	gitPath := filepath.Join(projectPath, ".git")
	if _, err := os.Stat(gitPath); os.IsNotExist(err) {
		return ErrNotGitRepo
	}

	// Check for Stackpanel markers
	// Option 1: .stackpanel/config.nix
	stackpanelConfig := filepath.Join(projectPath, ".stackpanel", "config.nix")
	if _, err := os.Stat(stackpanelConfig); err == nil {
		return nil
	}

	// Option 2: flake.nix with stackpanel (we just check for flake.nix)
	flakePath := filepath.Join(projectPath, "flake.nix")
	if _, err := os.Stat(flakePath); err == nil {
		return nil
	}

	return ErrNotStackpanel
}

// QuickValidate performs a minimal validation check.
// Used when restoring saved projects to avoid expensive validation.
func QuickValidate(projectPath string) error {
	// Just check the directory exists and has a .git folder
	info, err := os.Stat(projectPath)
	if err != nil {
		return ErrProjectNotFound
	}
	if !info.IsDir() {
		return fmt.Errorf("path is not a directory")
	}

	gitPath := filepath.Join(projectPath, ".git")
	if _, err := os.Stat(gitPath); os.IsNotExist(err) {
		return ErrNotGitRepo
	}

	return nil
}

// DetectProject looks for a Stackpanel project in the current directory
// or parent directories.
func DetectProject() (string, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("failed to get working directory: %w", err)
	}

	dir := cwd
	for {
		// Check for .stackpanel/config.nix
		configPath := filepath.Join(dir, ".stackpanel", "config.nix")
		if _, err := os.Stat(configPath); err == nil {
			log.Debug().Str("path", dir).Msg("Found Stackpanel project via .stackpanel/config.nix")
			return dir, nil
		}

		// Check for flake.nix (might be a Stackpanel project)
		flakePath := filepath.Join(dir, "flake.nix")
		if _, err := os.Stat(flakePath); err == nil {
			// Also needs .git to be considered a project root
			gitPath := filepath.Join(dir, ".git")
			if _, err := os.Stat(gitPath); err == nil {
				log.Debug().Str("path", dir).Msg("Found potential Stackpanel project via flake.nix")
				return dir, nil
			}
		}

		// Move to parent directory
		parent := filepath.Dir(dir)
		if parent == dir {
			// Reached root, no project found
			break
		}
		dir = parent
	}

	return "", nil
}

// AutoRegister detects the current project and registers it with the manager.
// Returns the project if found and registered, or nil if no project detected.
func (m *Manager) AutoRegister() (*Project, error) {
	projectPath, err := DetectProject()
	if err != nil {
		return nil, err
	}
	if projectPath == "" {
		log.Debug().Msg("No stackpanel project detected in current directory")
		return nil, nil
	}

	// Open/register the project
	return m.OpenProject(projectPath)
}

// ConfigPath returns the path to the user config file where projects are stored.
func (m *Manager) ConfigPath() string {
	return m.userConfig.ConfigPath()
}
