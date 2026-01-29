package cmd

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/spf13/cobra"
)

// hookConfig is a minimal config structure for validation.
// This is intentionally simple - the full evaluated config from Nix
// contains many more fields, but we only validate the essentials.
type hookConfig struct {
	Version     int    `json:"version"`
	ProjectName string `json:"projectName"`
	ProjectRoot string `json:"projectRoot"`
}

var hookCmd = &cobra.Command{
	Use:   "hook",
	Short: "Shell hook called by Nix during devshell entry",
	Long: `Shell hook that runs during Nix devshell entry.

This command is called by Nix during shell entry to validate configuration
and register the project. It is not intended to be run manually.

File generation is handled by Nix's write-files script, so this
command primarily serves as a validation checkpoint.

Configuration can be passed via:
  - --config-file [path]   Read from a JSON file
  - --config [json]        Pass JSON directly as argument
  - stdin                  Pipe JSON to stdin

Example (from Nix):
  stackpanel hook --config '${builtins.toJSON config}'

Example (from file):
  stackpanel hook --config-file /tmp/stackpanel-config.json

Example (from stdin):
  echo '{"projectName": "myapp", ...}' | stackpanel hook`,
	RunE:   runHook,
	Hidden: true, // Hide from help since it's internal
}

func init() {
	hookCmd.Flags().String("config", "", "Configuration JSON string")
	hookCmd.Flags().String("config-file", "", "Path to configuration JSON file")
	hookCmd.Flags().Bool("quiet", false, "Suppress output")

	rootCmd.AddCommand(hookCmd)
}

func runHook(cmd *cobra.Command, args []string) error {
	quiet, _ := cmd.Flags().GetBool("quiet")

	// Load configuration from various sources
	cfg, err := loadHookConfig(cmd)
	if err != nil {
		return err
	}

	// Validate required fields
	if cfg.ProjectName == "" {
		return fmt.Errorf("projectName is required in configuration")
	}

	// Register this project in the user config
	// This allows the agent to know about this project even when started from elsewhere
	if cfg.ProjectRoot != "" {
		if err := registerHookProject(cfg.ProjectRoot, cfg.ProjectName); err != nil {
			// Don't fail hook, just warn
			if !quiet {
				output.Warning(fmt.Sprintf("Could not register project: %v", err))
			}
		}
	}

	// File generation is now handled by Nix's write-files script.
	// This command validates config and confirms initialization.

	if !quiet {
		fmt.Printf("Config validated for %s\n", cfg.ProjectName)
		output.Success("Stackpanel initialized")
	}

	return nil
}

// registerHookProject adds or updates a project in the user config.
// This is called during hook to ensure the project is tracked.
func registerHookProject(projectRoot, projectName string) error {
	ucm, err := userconfig.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create user config manager: %w", err)
	}

	// Add or update the project
	_, err = ucm.AddProject(projectRoot, projectName)
	if err != nil {
		return fmt.Errorf("failed to add project: %w", err)
	}

	return nil
}

// loadHookConfig loads configuration from the available sources.
func loadHookConfig(cmd *cobra.Command) (*hookConfig, error) {
	// Priority: --config-file > --config > stdin

	configFile, _ := cmd.Flags().GetString("config-file")
	if configFile != "" {
		return loadHookConfigFromFile(configFile)
	}

	configJSON, _ := cmd.Flags().GetString("config")
	if configJSON != "" {
		return loadHookConfigFromString(configJSON)
	}

	// Check if stdin has data
	stat, _ := os.Stdin.Stat()
	if (stat.Mode() & os.ModeCharDevice) == 0 {
		// Stdin has data
		data, err := io.ReadAll(os.Stdin)
		if err != nil {
			return nil, fmt.Errorf("failed to read stdin: %w", err)
		}
		if len(strings.TrimSpace(string(data))) > 0 {
			return loadHookConfigFromString(string(data))
		}
	}

	return nil, fmt.Errorf("no configuration provided - use --config, --config-file, or pipe to stdin")
}

// loadHookConfigFromFile reads config from a JSON file.
func loadHookConfigFromFile(path string) (*hookConfig, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open config file: %w", err)
	}
	defer f.Close()

	var cfg hookConfig
	decoder := json.NewDecoder(f)
	if err := decoder.Decode(&cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config JSON: %w", err)
	}
	return &cfg, nil
}

// loadHookConfigFromString reads config from a JSON string.
func loadHookConfigFromString(s string) (*hookConfig, error) {
	var cfg hookConfig
	if err := json.Unmarshal([]byte(s), &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config JSON: %w", err)
	}
	return &cfg, nil
}
