package config

import (
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/envvars"
)

// Config holds the agent configuration.
// Configuration is loaded from environment variables and auto-detection.
// No config file is needed - run the agent from within a project directory.
type Config struct {
	// Project root directory (contains .stack/config.nix)
	// Auto-detected from current directory or STACKPANEL_PROJECT_ROOT
	ProjectRoot string

	// Port to listen on for HTTP/WebSocket connections
	// Default: 9876
	Port int

	// BindAddress is the address to bind the HTTP server to.
	// Default: 127.0.0.1 (localhost only)
	// Set to 0.0.0.0 for remote access (e.g., via Tailscale)
	BindAddress string

	// API endpoint to connect to (for cloud mode)
	APIEndpoint string

	// Authentication token (from STACKPANEL_AUTH_TOKEN)
	AuthToken string

	// TestPairingToken enables deterministic pairing token mode for testing.
	// When set, the agent uses a fixed signing key and agent ID derived from this value,
	// making the generated pairing token predictable and valid across restarts.
	TestPairingToken string

	// Allowed commands (empty = all allowed)
	AllowedCommands []string

	// Data directory for agent state (~/.stack)
	DataDir string

	// Allowed web UI origins (CORS + WebSocket Origin)
	// Localhost origins are always allowed
	AllowedOrigins []string

	// RemoteAccess indicates the agent is running in remote access mode
	// When true, Tailscale origins (*.ts.net) are automatically allowed
	RemoteAccess bool
}

// DefaultConfig returns a Config with sensible defaults.
func DefaultConfig() *Config {
	home, _ := os.UserHomeDir()
	return &Config{
		ProjectRoot:     "",
		Port:            9876,
		BindAddress:     "127.0.0.1",
		APIEndpoint:     "https://stackpanel.dev/api/agent",
		AllowedCommands: []string{},
		DataDir:         filepath.Join(home, ".stack"),
		AllowedOrigins:  []string{},
	}
}

// ApplyDefaults applies default values to missing config fields.
func (c *Config) ApplyDefaults() error {
	if c.Port == 0 {
		c.Port = 9876
	}

	if c.BindAddress == "" {
		c.BindAddress = "127.0.0.1"
	}

	if c.APIEndpoint == "" {
		c.APIEndpoint = "https://stackpanel.dev/api/agent"
	}

	if c.DataDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		c.DataDir = filepath.Join(home, ".stack")
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

	if v := envvars.StackpanelTestPairingToken.Get(); v != "" {
		cfg.TestPairingToken = v
	}

	if v := envvars.StackpanelAPIEndpoint.Get(); v != "" {
		cfg.APIEndpoint = v
	}

	if v := envvars.StackpanelDataDir.Get(); v != "" {
		cfg.DataDir = v
	}

	if v := envvars.StackpanelBindAddress.Get(); v != "" {
		cfg.BindAddress = v
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
