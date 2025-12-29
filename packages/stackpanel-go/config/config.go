// Package config defines the configuration structures passed from Nix to the CLI.
//
// These structures represent the "desired state" computed by Nix and are used
// by the `stackpanel init` command to generate files and write state.
package config

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
)

// Config is the top-level configuration passed from Nix
type Config struct {
	Version     int    `json:"version"`
	ProjectName string `json:"projectName"`
	ProjectRoot string `json:"projectRoot"` // Absolute path to project root
	BasePort    int    `json:"basePort"`

	Paths    Paths              `json:"paths"`
	Apps     map[string]App     `json:"apps"`
	Services map[string]Service `json:"services"`
	Network  Network            `json:"network"`
	IDE      *IDEConfig         `json:"ide,omitempty"`
	Schemas  *SchemasConfig     `json:"schemas,omitempty"`
}

// Paths contains directory paths (relative to project root)
type Paths struct {
	State string `json:"state"` // e.g., ".stackpanel/state"
	Gen   string `json:"gen"`   // e.g., ".stackpanel/gen"
	Data  string `json:"data"`  // e.g., ".stackpanel"
}

// App represents an application with its port and domain configuration
type App struct {
	Port   int     `json:"port"`
	Domain *string `json:"domain,omitempty"`
	URL    *string `json:"url,omitempty"`
	TLS    bool    `json:"tls"`
}

// Service represents an infrastructure service
type Service struct {
	Key    string `json:"key"`
	Name   string `json:"name"`
	Port   int    `json:"port"`
	EnvVar string `json:"envVar"`
}

// Network contains network configuration
type Network struct {
	Step StepConfig `json:"step"`
}

// StepConfig contains Step CA configuration
type StepConfig struct {
	Enable bool    `json:"enable"`
	CAUrl  *string `json:"caUrl,omitempty"`
}

// IDEConfig contains IDE integration settings
type IDEConfig struct {
	VSCode *VSCodeConfig `json:"vscode,omitempty"`
}

// VSCodeConfig contains VS Code specific settings
type VSCodeConfig struct {
	Enable        bool                   `json:"enable"`
	WorkspaceName string                 `json:"workspaceName"`
	Settings      map[string]interface{} `json:"settings,omitempty"`
	Extensions    []string               `json:"extensions,omitempty"`
	ExtraFolders  []WorkspaceFolder      `json:"extraFolders,omitempty"`
}

// WorkspaceFolder represents a VS Code workspace folder
type WorkspaceFolder struct {
	Path string `json:"path"`
	Name string `json:"name,omitempty"`
}

// SchemasConfig contains JSON schema generation settings
type SchemasConfig struct {
	Secrets *SecretsSchemas `json:"secrets,omitempty"`
}

// SecretsSchemas contains the JSON schemas for secrets configuration
type SecretsSchemas struct {
	Config    json.RawMessage `json:"config,omitempty"`
	Users     json.RawMessage `json:"users,omitempty"`
	AppConfig json.RawMessage `json:"appConfig,omitempty"`
	Schema    json.RawMessage `json:"schema,omitempty"`
	Env       json.RawMessage `json:"env,omitempty"`
}

// LoadFromReader reads config from an io.Reader (e.g., stdin or file)
func LoadFromReader(r io.Reader) (*Config, error) {
	var cfg Config
	decoder := json.NewDecoder(r)
	if err := decoder.Decode(&cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config JSON: %w", err)
	}
	return &cfg, nil
}

// LoadFromFile reads config from a JSON file
func LoadFromFile(path string) (*Config, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open config file: %w", err)
	}
	defer f.Close()
	return LoadFromReader(f)
}

// LoadFromString reads config from a JSON string
func LoadFromString(s string) (*Config, error) {
	var cfg Config
	if err := json.Unmarshal([]byte(s), &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config JSON: %w", err)
	}
	return &cfg, nil
}

// ToJSON serializes the config to JSON
func (c *Config) ToJSON() ([]byte, error) {
	return json.MarshalIndent(c, "", "  ")
}

// StateFile returns the path to the state file
func (c *Config) StateFile() string {
	return fmt.Sprintf("%s/%s/stackpanel.json", c.ProjectRoot, c.Paths.State)
}

// GenDir returns the absolute path to the gen directory
func (c *Config) GenDir() string {
	return fmt.Sprintf("%s/%s", c.ProjectRoot, c.Paths.Gen)
}
