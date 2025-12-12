package config

import (
	"os"
	"path/filepath"

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
}

func DefaultConfig() *Config {
	home, _ := os.UserHomeDir()
	return &Config{
		ProjectRoot:     ".",
		Port:            9876,
		APIEndpoint:     "https://stackpanel.dev/api/agent",
		AllowedCommands: []string{},
		DataDir:         filepath.Join(home, ".stackpanel"),
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
	if v := os.Getenv("STACKPANEL_PROJECT_ROOT"); v != "" {
		cfg.ProjectRoot = v
	}
	if v := os.Getenv("STACKPANEL_AUTH_TOKEN"); v != "" {
		cfg.AuthToken = v
	}
	if v := os.Getenv("STACKPANEL_API_ENDPOINT"); v != "" {
		cfg.APIEndpoint = v
	}

	// Resolve project root to absolute path
	if !filepath.IsAbs(cfg.ProjectRoot) {
		abs, err := filepath.Abs(cfg.ProjectRoot)
		if err != nil {
			return nil, err
		}
		cfg.ProjectRoot = abs
	}

	return cfg, nil
}
