// Package config defines the agent's runtime configuration.
// All configuration comes from environment variables — there is no config file.
// The agent is designed to be started from within a project directory (or via
// STACKPANEL_PROJECT_ROOT) so it inherits the devshell's environment.
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

	// TestPairingToken enables deterministic pairing for integration tests.
	// Normally the agent generates a random signing key on startup, making
	// the JWT pairing token unpredictable. This field pins both the signing
	// key and agent ID so tests can pre-compute valid tokens.
	TestPairingToken string

	// AllowedCommands restricts which binaries the exec endpoint can run.
	// Empty means no restrictions. Intended for shared/remote agents where
	// arbitrary command execution should be limited.
	AllowedCommands []string

	// Data directory for agent state (~/.stack)
	DataDir string

	// AllowedOrigins controls CORS and WebSocket Origin validation.
	// Localhost origins (127.0.0.1, localhost) are always implicitly allowed.
	AllowedOrigins []string

	// RemoteAccess enables the agent for access over Tailscale.
	// When true, *.ts.net origins are automatically added to AllowedOrigins
	// and BindAddress should typically be set to 0.0.0.0.
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

// Load creates a Config from environment variables (via the envvars package).
// The configPath parameter is vestigial from when a YAML config was supported.
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
