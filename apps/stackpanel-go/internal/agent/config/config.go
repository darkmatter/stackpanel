package config

import (
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/apps/stackpanel-go/pkg/envvars"
)

// Config holds the agent configuration.
// Configuration is loaded from environment variables and auto-detection.
// No config file is needed - run the agent from within a project directory.
type Config struct {
	// Project root directory (contains .stackpanel/config.nix)
	// Auto-detected from current directory or STACKPANEL_PROJECT_ROOT
	ProjectRoot string

	// Port to listen on for HTTP/WebSocket connections
	// Default: 9876
	Port int

	// API endpoint to connect to (for cloud mode)
	APIEndpoint string

	// Authentication token (from STACKPANEL_AUTH_TOKEN)
	AuthToken string

	// Allowed commands (empty = all allowed)
	AllowedCommands []string

	// Data directory for agent state (~/.stackpanel)
	DataDir string

	// Allowed web UI origins (CORS + WebSocket Origin)
	// Localhost origins are always allowed
	AllowedOrigins []string
}

// DefaultConfig returns a Config with sensible defaults.
func DefaultConfig() *Config {
	home, _ := os.UserHomeDir()
	return &Config{
		ProjectRoot:     "",
		Port:            9876,
		APIEndpoint:     "https://stackpanel.dev/api/agent",
		AllowedCommands: []string{},
		DataDir:         filepath.Join(home, ".stackpanel"),
		AllowedOrigins:  []string{},
	}
}

// Load creates a Config from environment variables.
// The configPath parameter is ignored (kept for backwards compatibility).
func Load(_ string) (*Config, error) {
	cfg := DefaultConfig()

	// Load from environment variables
	if v := envvars.StackpanelProjectRoot.Get(); v != "" {
		cfg.ProjectRoot = v
	}

	if v := envvars.StackpanelAuthToken.Get(); v != "" {
		cfg.AuthToken = v
	}

	if v := envvars.StackpanelAPIEndpoint.Get(); v != "" {
		cfg.APIEndpoint = v
	}

	if v := envvars.StackpanelDataDir.Get(); v != "" {
		cfg.DataDir = v
	}

	// Resolve project root to absolute path (only if set)
	if cfg.ProjectRoot != "" && !filepath.IsAbs(cfg.ProjectRoot) {
		abs, err := filepath.Abs(cfg.ProjectRoot)
		if err != nil {
			return nil, err
		}
		cfg.ProjectRoot = abs
	}

	return cfg, nil
}
