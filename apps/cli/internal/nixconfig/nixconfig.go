// Package nixconfig provides access to the Stackpanel configuration from Nix.
//
// This package reads the configuration JSON that Nix generates and stores
// in the Nix store. The path to this file is provided via STACKPANEL_CONFIG_JSON.
//
// This replaces the legacy state file approach with direct access to the
// Nix-generated configuration.
package nixconfig

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/darkmatter/stackpanel/packages/stackpanel-go/envvars"
)

// Config represents the Nix-generated stackpanel configuration.
// This is a subset of what Nix generates - we only include fields
// that the CLI actually needs.
type Config struct {
	Version     int    `json:"version"`
	ProjectName string `json:"projectName"`
	ProjectRoot string `json:"projectRoot"`
	BasePort    int    `json:"basePort"`

	Paths    Paths              `json:"paths"`
	Apps     map[string]App     `json:"apps"`
	Services map[string]Service `json:"services"`
	Network  Network            `json:"network"`
	MOTD     MOTD               `json:"motd"`
}

// Paths contains directory paths
type Paths struct {
	State string `json:"state"`
	Gen   string `json:"gen"`
	Data  string `json:"data"`
}

// App represents an application with its port and domain configuration
type App struct {
	Port   int     `json:"port"`
	Domain *string `json:"domain"`
	URL    *string `json:"url"`
	TLS    bool    `json:"tls"`
}

// Service represents an infrastructure service
type Service struct {
	Key  string `json:"key"`
	Name string `json:"name"`
	Port int    `json:"port"`
}

// Network contains network configuration
type Network struct {
	Step StepConfig `json:"step"`
}

// StepConfig contains Step CA configuration
type StepConfig struct {
	Enable bool    `json:"enable"`
	CAUrl  *string `json:"caUrl"`
}

// MOTD contains message of the day configuration
type MOTD struct {
	Enable   bool          `json:"enable"`
	Commands []MOTDCommand `json:"commands"`
	Features []string      `json:"features"`
	Hints    []string      `json:"hints"`
}

// MOTDCommand represents a command to show in the MOTD
type MOTDCommand struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

// Load reads the configuration from STACKPANEL_CONFIG_JSON.
// The config file contains $STACKPANEL_ROOT which needs to be substituted
// with the actual value from the environment.
func Load() (*Config, error) {
	configPath := envvars.StackpanelConfigJson.Get()
	if configPath == "" {
		return nil, fmt.Errorf("STACKPANEL_CONFIG_JSON not set - are you in a stackpanel devshell?")
	}

	return LoadFromFile(configPath)
}

// LoadFromFile reads configuration from a specific file path.
func LoadFromFile(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	// The config file may contain $STACKPANEL_ROOT placeholder
	// Substitute it with the actual value
	content := string(data)
	if root := envvars.StackpanelRoot.Get(); root != "" {
		content = strings.ReplaceAll(content, "$STACKPANEL_ROOT", root)
	}

	var cfg Config
	if err := json.Unmarshal([]byte(content), &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config JSON: %w", err)
	}

	return &cfg, nil
}

// AppNames returns all app names
func (c *Config) AppNames() []string {
	names := make([]string, 0, len(c.Apps))
	for name := range c.Apps {
		names = append(names, name)
	}
	return names
}

// ServiceNames returns all service keys
func (c *Config) ServiceNames() []string {
	names := make([]string, 0, len(c.Services))
	for name := range c.Services {
		names = append(names, name)
	}
	return names
}

// GetApp returns app info by name, or nil if not found
func (c *Config) GetApp(name string) *App {
	if app, ok := c.Apps[name]; ok {
		return &app
	}
	return nil
}

// GetService returns service info by key, or nil if not found
func (c *Config) GetService(key string) *Service {
	if svc, ok := c.Services[key]; ok {
		return &svc
	}
	return nil
}

// DataDir returns the data directory path.
// Falls back to STACKPANEL_DATA_DIR env var, then default.
func (c *Config) DataDir() string {
	// Try config first
	if c.Paths.Data != "" {
		return c.Paths.Data
	}

	// Try env var
	if dir := envvars.StackpanelDataDir.Get(); dir != "" {
		return dir
	}

	// Default
	return ".stackpanel/data"
}
