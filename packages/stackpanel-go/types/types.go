package types

// Config represents the stackpanel configuration produced by Nix evaluation
// or read from the state file. Both the CLI and agent should treat this as
// the canonical project description.
type Config struct {
	Version     int    `json:"version"`
	ProjectName string `json:"projectName"`
	ProjectRoot string `json:"projectRoot,omitempty"`
	BasePort    int    `json:"basePort"`

	Paths    Paths              `json:"paths"`
	Apps     map[string]App     `json:"apps"`
	Services map[string]Service `json:"services"`
	Network  Network            `json:"network"`
	MOTD     *MOTD              `json:"motd,omitempty"`

	// Optional error hint fields returned by some Nix evaluations
	Error string `json:"error,omitempty"`
	Hint  string `json:"hint,omitempty"`
}

// Paths describes important directories within the project.
type Paths struct {
	State string `json:"state"` // e.g., ".stackpanel/state"
	Gen   string `json:"gen"`   // e.g., ".stackpanel/gen"
	Data  string `json:"data"`  // e.g., ".stackpanel"
}

// App describes a user application with associated routing data.
type App struct {
	Port   int     `json:"port"`
	Domain *string `json:"domain,omitempty"`
	URL    *string `json:"url,omitempty"`
	TLS    bool    `json:"tls"`
}

// Service describes an infrastructure service (postgres, redis, etc.).
type Service struct {
	Key    string `json:"key"`
	Name   string `json:"name"`
	Port   int    `json:"port"`
	EnvVar string `json:"envVar"`
}

// Network contains network-related configuration (Step CA, ports, etc.).
type Network struct {
	Step StepConfig `json:"step"`
}

// StepConfig configures the Step CA integration.
type StepConfig struct {
	Enable bool    `json:"enable"`
	CAUrl  *string `json:"caUrl,omitempty"`
}

// MOTD contains optional message-of-the-day settings rendered by the CLI.
type MOTD struct {
	Enable   bool          `json:"enable"`
	Commands []MOTDCommand `json:"commands,omitempty"`
	Features []string      `json:"features,omitempty"`
	Hints    []string      `json:"hints,omitempty"`
}

// MOTDCommand lists a suggested command for the CLI MOTD panel.
type MOTDCommand struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

// GetApp returns app info by name, or nil if not found.
func (c *Config) GetApp(name string) *App {
	if c == nil {
		return nil
	}
	if app, ok := c.Apps[name]; ok {
		return &app
	}
	return nil
}

// GetService returns service info by key, or nil if not found.
func (c *Config) GetService(key string) *Service {
	if c == nil {
		return nil
	}
	if svc, ok := c.Services[key]; ok {
		return &svc
	}
	return nil
}

// GetAppPort returns the port for an app, or 0 if not found.
func (c *Config) GetAppPort(name string) int {
	if app := c.GetApp(name); app != nil {
		return app.Port
	}
	return 0
}

// GetServicePort returns the port for a service, or 0 if not found.
func (c *Config) GetServicePort(key string) int {
	if svc := c.GetService(key); svc != nil {
		return svc.Port
	}
	return 0
}

// AppNames returns all app names sorted arbitrarily.
func (c *Config) AppNames() []string {
	if c == nil {
		return nil
	}
	names := make([]string, 0, len(c.Apps))
	for name := range c.Apps {
		names = append(names, name)
	}
	return names
}

// ServiceNames returns all registered service keys.
func (c *Config) ServiceNames() []string {
	if c == nil {
		return nil
	}
	names := make([]string, 0, len(c.Services))
	for name := range c.Services {
		names = append(names, name)
	}
	return names
}
