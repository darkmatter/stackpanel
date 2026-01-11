package config

import (
	"os"
	"path/filepath"
)

// Config holds the agent configuration.
type Config struct {
	// Project root directory (contains .stackpanel/config.nix)
	ProjectRoot string

	// Port to listen on for HTTP/WebSocket connections
	Port int

	// API endpoint to connect to (for cloud mode)
	APIEndpoint string

	// Authentication token
	AuthToken string

	// Allowed commands (empty = all allowed)
	AllowedCommands []string

	// Data directory for agent state (~/.stackpanel)
	DataDir string

	// Allowed web UI origins (CORS + WebSocket Origin)
	AllowedOrigins []string
}

// ApplyDefaults applies default values to missing config fields.
func (c *Config) ApplyDefaults() error {
	if c.Port == 0 {
		c.Port = 9876
	}

	if c.APIEndpoint == "" {
		c.APIEndpoint = "https://stackpanel.dev/api/agent"
	}

	if c.DataDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		c.DataDir = filepath.Join(home, ".stackpanel")
	}

	// Ensure data directory exists
	if err := os.MkdirAll(c.DataDir, 0755); err != nil {
		return err
	}

	// Resolve project root to absolute path (only if set)
	if c.ProjectRoot != "" && !filepath.IsAbs(c.ProjectRoot) {
		abs, err := filepath.Abs(c.ProjectRoot)
		if err != nil {
			return err
		}
		c.ProjectRoot = abs
	}

	return nil
}
