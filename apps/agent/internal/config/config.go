package config

import (
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/packages/stackpanel-go/envvars"
	"gopkg.in/yaml.v3"
)

type Config struct {
	// Project root directory (contains flake.nix)
	ProjectRoot string `yaml:"project_root"`

	// Port to listen on for WebSocket connections
	Port int `yaml:"port"`

	// API endpoint to connect to (for cloud mode)
	APIEndpoint string `yaml:"api_endpoint"`

	// Authentication token
	AuthToken string `yaml:"auth_token"`

	// Allowed commands (empty = all allowed)
	AllowedCommands []string `yaml:"allowed_commands"`

	// Data directory for agent state
	DataDir string `yaml:"data_dir"`

	// Allowed web UI origins (CORS + WebSocket Origin). Empty means defaults.
	// Localhost origins are always allowed.
	AllowedOrigins []string `yaml:"allowed_origins"`
}

func DefaultConfig() *Config {
	home, _ := os.UserHomeDir()
	return &Config{
		ProjectRoot:     "", // Empty by default - must be set via project manager or env var
		Port:            9876,
		APIEndpoint:     "https://stackpanel.dev/api/agent",
		AllowedCommands: []string{},
		DataDir:         filepath.Join(home, ".stackpanel"),
		AllowedOrigins:  []string{},
	}
}

func Load(path string) (*Config, error) {
	cfg := DefaultConfig()

	// Try to find config file
	if path == "" {
		// Look in standard locations
		candidates := []string{
			".stackpanel/agent.yaml",
			filepath.Join(os.Getenv("HOME"), ".config/stackpanel/agent.yaml"),
		}
		for _, c := range candidates {
			if _, err := os.Stat(c); err == nil {
				path = c
				break
			}
		}
	}

	if path != "" {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		if err := yaml.Unmarshal(data, cfg); err != nil {
			return nil, err
		}
	}

	// Override with environment variables
	// STACKPANEL_PROJECT_ROOT takes precedence if set
	if v := envvars.StackpanelProjectRoot.Get(); v != "" {
		cfg.ProjectRoot = v
	}
	if v := envvars.StackpanelAuthToken.Get(); v != "" {
		cfg.AuthToken = v
	}
	if v := envvars.StackpanelAPIEndpoint.Get(); v != "" {
		cfg.APIEndpoint = v
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
