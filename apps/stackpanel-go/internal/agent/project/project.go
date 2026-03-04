// Package project manages Stackpanel project selection, validation, and persistence.
package project

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/rs/zerolog/log"
)

var (
	ErrNoProject          = errors.New("no project selected")
	ErrNotGitRepo         = errors.New("directory is not a git repository (no .git folder)")
	ErrNotStackpanel      = errors.New("directory is not a valid Stackpanel project")
	ErrProjectNotFound    = errors.New("project directory does not exist")
	ErrSuspiciousPath     = errors.New("path appears to be a system or temporary directory")
	ErrInvalidConfig      = errors.New("stackpanel config.nix is invalid or missing required fields")
	ErrFlakeNotStackpanel = errors.New("flake.nix exists but doesn't appear to be a Stackpanel project")
)

// ValidationLevel controls how strict project validation is
type ValidationLevel int

const (
	// ValidationStrict requires .stack/config.nix with valid content
	ValidationStrict ValidationLevel = iota
	// ValidationNormal accepts .stack/config.nix or flake.nix with stackpanel references
	ValidationNormal
	// ValidationLenient accepts any flake.nix (for potential stackpanel projects)
	ValidationLenient
)

// ValidationOptions configures validation behavior
type ValidationOptions struct {
	// Level controls how strict validation is
	Level ValidationLevel
	// SkipNixEval skips nix evaluation checks (faster but less accurate for flake-only projects)
	SkipNixEval bool
	// Timeout for nix commands (default 10s)
	NixTimeout time.Duration
}

// DefaultValidationOptions returns sensible defaults
func DefaultValidationOptions() ValidationOptions {
	return ValidationOptions{
		Level:       ValidationNormal,
		SkipNixEval: false,
		NixTimeout:  10 * time.Second,
	}
}

// QuickValidationOptions returns options for fast validation (no nix eval)
func QuickValidationOptions() ValidationOptions {
	return ValidationOptions{
		Level:       ValidationNormal,
		SkipNixEval: true,
		NixTimeout:  5 * time.Second,
	}
}

// ValidationResult contains detailed validation information
type ValidationResult struct {
	Valid       bool
	Level       ValidationLevel
	ProjectType string // "stackpanel-config", "stackpanel-flake", "flake-only"
	Warnings    []string
	Error       error
}

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

// UserConfigManager returns the underlying user config manager.
// This allows access to project resolution and default project features.
func (m *Manager) UserConfigManager() *userconfig.Manager {
	return m.userConfig
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
// This is the main validation function used for adding/opening projects.
func ValidateProject(projectPath string) error {
	result := ValidateProjectWithOptions(projectPath, DefaultValidationOptions())
	return result.Error
}

// ValidateProjectStrict performs strict validation requiring .stack/config.nix
func ValidateProjectStrict(projectPath string) error {
	opts := DefaultValidationOptions()
	opts.Level = ValidationStrict
	result := ValidateProjectWithOptions(projectPath, opts)
	return result.Error
}

// ValidateProjectFast performs validation without nix evaluation (faster)
func ValidateProjectFast(projectPath string) error {
	result := ValidateProjectWithOptions(projectPath, QuickValidationOptions())
	return result.Error
}

// ValidateProjectDetailed performs detailed validation and returns full results.
// Deprecated: Use ValidateProjectWithOptions instead
func ValidateProjectDetailed(projectPath string, level ValidationLevel) *ValidationResult {
	opts := DefaultValidationOptions()
	opts.Level = level
	return ValidateProjectWithOptions(projectPath, opts)
}

// ValidateProjectWithOptions performs detailed validation with configurable options.
func ValidateProjectWithOptions(projectPath string, opts ValidationOptions) *ValidationResult {
	level := opts.Level
	result := &ValidationResult{
		Valid:    false,
		Level:    level,
		Warnings: []string{},
	}

	// Check for suspicious paths
	if isSuspiciousPath(projectPath) {
		result.Error = ErrSuspiciousPath
		result.Warnings = append(result.Warnings, "Path appears to be a system or temporary directory")
		return result
	}

	// Check directory exists
	info, err := os.Stat(projectPath)
	if err != nil {
		if os.IsNotExist(err) {
			result.Error = ErrProjectNotFound
			return result
		}
		result.Error = fmt.Errorf("failed to stat directory: %w", err)
		return result
	}
	if !info.IsDir() {
		result.Error = fmt.Errorf("path is not a directory")
		return result
	}

	// Check for .git directory
	gitPath := filepath.Join(projectPath, ".git")
	if _, err := os.Stat(gitPath); os.IsNotExist(err) {
		result.Error = ErrNotGitRepo
		return result
	}

	// Check for .stack/config.nix (primary indicator)
	stackpanelConfig := filepath.Join(projectPath, ".stack", "config.nix")
	if _, err := os.Stat(stackpanelConfig); err == nil {
		// Validate the config.nix content
		if err := validateStackpanelConfig(stackpanelConfig); err != nil {
			result.Warnings = append(result.Warnings, fmt.Sprintf("config.nix validation: %v", err))
			if level == ValidationStrict {
				result.Error = ErrInvalidConfig
				return result
			}
		}
		result.Valid = true
		result.ProjectType = "stackpanel-config"
		return result
	}

	// Check for flake.nix
	flakePath := filepath.Join(projectPath, "flake.nix")
	if _, err := os.Stat(flakePath); err == nil {
		// Check if flake.nix contains stackpanel references
		hasStackpanel, flakeWarnings := checkFlakeForStackpanelWithOptions(flakePath, opts)
		result.Warnings = append(result.Warnings, flakeWarnings...)

		if hasStackpanel {
			result.Valid = true
			result.ProjectType = "stackpanel-flake"
			return result
		}

		// Flake exists but no stackpanel references
		if level == ValidationLenient {
			result.Valid = true
			result.ProjectType = "flake-only"
			result.Warnings = append(result.Warnings, "flake.nix exists but no stackpanel references found")
			return result
		}

		result.Error = ErrFlakeNotStackpanel
		result.Warnings = append(result.Warnings, "flake.nix exists but doesn't appear to be a Stackpanel project")
		return result
	}

	result.Error = ErrNotStackpanel
	return result
}

// isSuspiciousPath checks if a path looks like a system or temporary directory
func isSuspiciousPath(path string) bool {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return false
	}

	// Normalize path
	absPath = filepath.Clean(absPath)

	// List of suspicious path prefixes
	suspiciousPrefixes := []string{
		"/bin",
		"/sbin",
		"/usr/bin",
		"/usr/sbin",
		"/usr/lib",
		"/usr/local/bin",
		"/usr/local/sbin",
		"/etc",
		"/var",
		"/tmp",
		"/private/tmp",
		"/private/var",
		"/System",
		"/Library",
		"/Applications",
		"/opt/homebrew/Cellar",
		"/nix/store",
	}

	for _, prefix := range suspiciousPrefixes {
		if strings.HasPrefix(absPath, prefix) {
			return true
		}
	}

	// Check for root directory
	if absPath == "/" {
		return true
	}

	// Check for home directory itself (not subdirectories)
	home, err := os.UserHomeDir()
	if err == nil && absPath == home {
		return true
	}

	return false
}

// validateStackpanelConfig checks if a config.nix file has valid content
func validateStackpanelConfig(configPath string) error {
	file, err := os.Open(configPath)
	if err != nil {
		return fmt.Errorf("cannot open config: %w", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	hasContent := false
	lineCount := 0
	hasEnable := false
	hasName := false

	for scanner.Scan() {
		lineCount++
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		hasContent = true

		// Look for key indicators
		if strings.Contains(line, "enable") && strings.Contains(line, "=") {
			hasEnable = true
		}
		if strings.Contains(line, "name") && strings.Contains(line, "=") {
			hasName = true
		}

		// Stop after checking first 50 lines
		if lineCount > 50 {
			break
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("error reading config: %w", err)
	}

	if !hasContent {
		return fmt.Errorf("config.nix appears to be empty")
	}

	// For strict validation, require both enable and name
	// For now, we just warn if missing
	if !hasEnable {
		log.Debug().Str("path", configPath).Msg("config.nix missing 'enable' field")
	}
	if !hasName {
		log.Debug().Str("path", configPath).Msg("config.nix missing 'name' field")
	}

	return nil
}

// checkFlakeForStackpanel checks if a flake has stackpanel as an input or output
// It tries multiple detection methods in order of accuracy:
// 1. Check for .#stackpanelConfig output (most reliable)
// 2. Check flake metadata for stackpanel input
// 3. Fall back to text matching in flake.nix
func checkFlakeForStackpanel(flakePath string) (bool, []string) {
	return checkFlakeForStackpanelWithOptions(flakePath, DefaultValidationOptions())
}

// checkFlakeForStackpanelWithOptions checks if a flake has stackpanel with configurable options
func checkFlakeForStackpanelWithOptions(flakePath string, opts ValidationOptions) (bool, []string) {
	var warnings []string
	projectDir := filepath.Dir(flakePath)

	// If nix eval is not skipped, try the accurate nix-based checks first
	if !opts.SkipNixEval {
		// Try checking for stackpanelConfig output first (most reliable)
		hasOutput, outputWarnings := checkFlakeForStackpanelOutputWithTimeout(projectDir, opts.NixTimeout)
		warnings = append(warnings, outputWarnings...)
		if hasOutput {
			return true, warnings
		}

		// Try nix flake metadata to check inputs
		hasInput, metadataWarnings := checkFlakeMetadataForStackpanelWithTimeout(projectDir, opts.NixTimeout)
		warnings = append(warnings, metadataWarnings...)
		if hasInput {
			return true, warnings
		}
	} else {
		warnings = append(warnings, "Nix evaluation skipped (fast mode)")
	}

	// Fall back to string matching in flake.nix
	// This handles cases where nix isn't available or the flake hasn't been locked yet
	hasStackpanelText, textWarnings := checkFlakeTextForStackpanel(flakePath)
	warnings = append(warnings, textWarnings...)

	return hasStackpanelText, warnings
}

// checkFlakeForStackpanelOutput checks if the flake exposes a stackpanelConfig output
// This is the most reliable way to detect a stackpanel project
func checkFlakeForStackpanelOutput(projectDir string) (bool, []string) {
	return checkFlakeForStackpanelOutputWithTimeout(projectDir, 5*time.Second)
}

// checkFlakeForStackpanelOutputWithTimeout checks for stackpanelConfig output with custom timeout
// It tries multiple paths where stackpanelConfig might be exposed:
// 1. .#stackpanelConfig (stackpanel repo itself, or user projects that expose it at top level)
// 2. .#devShells.<system>.default.passthru.stackpanelConfig (user projects via devenv/devshell)
// 3. .#legacyPackages.<system>.stackpanelConfig (user projects via legacyPackages)
func checkFlakeForStackpanelOutputWithTimeout(projectDir string, timeout time.Duration) (bool, []string) {
	var warnings []string

	// Detect current system
	system := detectNixSystem()

	// Paths to check for stackpanelConfig (in order of likelihood)
	// We check .name attribute to verify it's a real config, not just an empty attrset
	pathsToCheck := []string{
		// Top-level stackpanelConfig (stackpanel repo or user projects that expose it)
		".#stackpanelConfig.name",
		// devShells passthru (most common for user projects)
		fmt.Sprintf(".#devShells.%s.default.passthru.stackpanelConfig.name", system),
		// legacyPackages (alternative exposure method)
		fmt.Sprintf(".#legacyPackages.%s.stackpanelConfig.name", system),
	}

	// Create a context with the specified timeout for all attempts
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	for _, path := range pathsToCheck {
		// Check if context is already cancelled
		if ctx.Err() != nil {
			warnings = append(warnings, "nix eval timed out checking for stackpanelConfig")
			return false, warnings
		}

		// Try to evaluate this path
		cmd := exec.CommandContext(ctx, "nix", "eval", "--json", path, "--no-eval-cache")
		cmd.Dir = projectDir

		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr

		if err := cmd.Run(); err != nil {
			// This path doesn't exist, try the next one
			log.Debug().
				Str("dir", projectDir).
				Str("path", path).
				Msg("stackpanelConfig path not found, trying next")
			continue
		}

		// If we got here, the flake has stackpanelConfig at this path
		log.Debug().
			Str("dir", projectDir).
			Str("path", path).
			Str("name", strings.TrimSpace(stdout.String())).
			Msg("Found stackpanelConfig output in flake")
		return true, warnings
	}

	// None of the paths worked
	log.Debug().
		Str("dir", projectDir).
		Msg("No stackpanelConfig output found at any known path")
	return false, warnings
}

// detectNixSystem returns the current nix system identifier (e.g., "x86_64-linux", "aarch64-darwin")
func detectNixSystem() string {
	// Try to get system from nix
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem")
	var stdout bytes.Buffer
	cmd.Stdout = &stdout

	if err := cmd.Run(); err == nil {
		system := strings.TrimSpace(stdout.String())
		if system != "" {
			return system
		}
	}

	// Fall back to runtime detection
	arch := "x86_64"
	os := "linux"

	// Detect architecture
	switch a := strings.ToLower(getArch()); a {
	case "arm64", "aarch64":
		arch = "aarch64"
	case "amd64", "x86_64":
		arch = "x86_64"
	}

	// Detect OS
	switch o := strings.ToLower(getOS()); o {
	case "darwin", "macos":
		os = "darwin"
	case "linux":
		os = "linux"
	}

	return fmt.Sprintf("%s-%s", arch, os)
}

// getArch returns the current architecture from Go runtime
func getArch() string {
	// Use build-time constant
	switch arch := runtime.GOARCH; arch {
	case "arm64":
		return "aarch64"
	case "amd64":
		return "x86_64"
	default:
		return arch
	}
}

// getOS returns the current OS from Go runtime
func getOS() string {
	return runtime.GOOS
}

// flakeMetadata represents the relevant parts of `nix flake metadata --json` output
type flakeMetadata struct {
	Locks struct {
		Nodes map[string]struct {
			Original struct {
				Owner string `json:"owner"`
				Repo  string `json:"repo"`
				Type  string `json:"type"`
			} `json:"original"`
		} `json:"nodes"`
		Root string `json:"root"`
	} `json:"locks"`
}

// checkFlakeMetadataForStackpanel uses `nix flake metadata` to check for stackpanel input
func checkFlakeMetadataForStackpanel(projectDir string) (bool, []string) {
	return checkFlakeMetadataForStackpanelWithTimeout(projectDir, 10*time.Second)
}

// checkFlakeMetadataForStackpanelWithTimeout uses `nix flake metadata` with custom timeout
func checkFlakeMetadataForStackpanelWithTimeout(projectDir string, timeout time.Duration) (bool, []string) {
	var warnings []string

	// Create a context with the specified timeout
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "nix", "flake", "metadata", "--json", ".")
	cmd.Dir = projectDir

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			warnings = append(warnings, "nix flake metadata timed out, falling back to text search")
		} else {
			// This is expected if nix isn't installed or flake isn't locked
			log.Debug().
				Str("dir", projectDir).
				Str("stderr", stderr.String()).
				Err(err).
				Msg("nix flake metadata failed, falling back to text search")
		}
		return false, warnings
	}

	var metadata flakeMetadata
	if err := json.Unmarshal(stdout.Bytes(), &metadata); err != nil {
		warnings = append(warnings, fmt.Sprintf("failed to parse flake metadata: %v", err))
		return false, warnings
	}

	// Check all nodes for stackpanel-related inputs
	stackpanelPatterns := []string{
		"stackpanel",
		"stack-panel",
		"sp-",
	}

	for nodeName, node := range metadata.Locks.Nodes {
		// Check node name
		nodeNameLower := strings.ToLower(nodeName)
		for _, pattern := range stackpanelPatterns {
			if strings.Contains(nodeNameLower, pattern) {
				log.Debug().
					Str("node", nodeName).
					Msg("Found stackpanel input in flake")
				return true, warnings
			}
		}

		// Check repo name if it's a GitHub/GitLab input
		if node.Original.Repo != "" {
			repoLower := strings.ToLower(node.Original.Repo)
			for _, pattern := range stackpanelPatterns {
				if strings.Contains(repoLower, pattern) {
					log.Debug().
						Str("node", nodeName).
						Str("repo", node.Original.Repo).
						Msg("Found stackpanel repo in flake inputs")
					return true, warnings
				}
			}
		}
	}

	return false, warnings
}

// checkFlakeTextForStackpanel does a text-based search for stackpanel references
// This is a fallback when nix flake metadata isn't available
func checkFlakeTextForStackpanel(flakePath string) (bool, []string) {
	var warnings []string

	file, err := os.Open(flakePath)
	if err != nil {
		warnings = append(warnings, fmt.Sprintf("cannot open flake.nix: %v", err))
		return false, warnings
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	lineCount := 0

	// Patterns that indicate stackpanel usage
	stackpanelPatterns := []string{
		"stackpanel",
		"Stackpanel",
		"STACKPANEL",
		".stack",
		"stackpanelConfig",
		"stackpanelModules",
	}

	for scanner.Scan() {
		lineCount++
		line := scanner.Text()

		for _, pattern := range stackpanelPatterns {
			if strings.Contains(line, pattern) {
				return true, warnings
			}
		}

		// Don't scan entire huge files
		if lineCount > 500 {
			warnings = append(warnings, "flake.nix is large, only scanned first 500 lines")
			break
		}
	}

	if err := scanner.Err(); err != nil {
		warnings = append(warnings, fmt.Sprintf("error reading flake.nix: %v", err))
	}

	return false, warnings
}

// QuickValidate performs a minimal validation check.
// Used when restoring saved projects to avoid expensive validation.
func QuickValidate(projectPath string) error {
	// Check for suspicious paths even in quick validation
	if isSuspiciousPath(projectPath) {
		return ErrSuspiciousPath
	}

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

// GetValidationWarnings returns warnings for a project without failing validation.
// Useful for showing users potential issues with their project.
func GetValidationWarnings(projectPath string) []string {
	result := ValidateProjectDetailed(projectPath, ValidationLenient)
	return result.Warnings
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
		// Check for .stack/config.nix
		configPath := filepath.Join(dir, ".stack", "config.nix")
		if _, err := os.Stat(configPath); err == nil {
			log.Debug().Str("path", dir).Msg("Found Stackpanel project via .stack/config.nix")
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
