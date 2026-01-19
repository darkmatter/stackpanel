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

// initConfig is a minimal config structure for validation.
// This is intentionally simple - the full evaluated config from Nix
// contains many more fields, but we only validate the essentials.
type initConfig struct {
	Version     int    `json:"version"`
	ProjectName string `json:"projectName"`
	ProjectRoot string `json:"projectRoot"`
}

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize stackpanel from Nix configuration",
	Long: `Initialize stackpanel by validating configuration from Nix.

This command is typically called by Nix during shell entry.
It validates the configuration JSON and confirms stackpanel is ready.

File generation is handled by Nix's write-files script, so this
command now primarily serves as a validation checkpoint.

Configuration can be passed via:
  - --config-file [path]   Read from a JSON file
  - --config [json]        Pass JSON directly as argument
  - stdin                  Pipe JSON to stdin

Example (from Nix):
  stackpanel init --config '${builtins.toJSON config}'

Example (from file):
  stackpanel init --config-file /tmp/stackpanel-config.json

Example (from stdin):
  echo '{"projectName": "myapp", ...}' | stackpanel init`,
	RunE: runInit,
}

func init() {
	initCmd.Flags().String("config", "", "Configuration JSON string")
	initCmd.Flags().String("config-file", "", "Path to configuration JSON file")
	initCmd.Flags().Bool("quiet", false, "Suppress output")

	rootCmd.AddCommand(initCmd)
}

func runInit(cmd *cobra.Command, args []string) error {
	quiet, _ := cmd.Flags().GetBool("quiet")

	// Load configuration from various sources
	cfg, err := loadInitConfig(cmd)
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
		if err := registerProject(cfg.ProjectRoot, cfg.ProjectName); err != nil {
			// Don't fail init, just warn
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

// registerProject adds or updates a project in the user config.
// This is called during init to ensure the project is tracked.
func registerProject(projectRoot, projectName string) error {
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

// loadInitConfig loads configuration from the available sources.
func loadInitConfig(cmd *cobra.Command) (*initConfig, error) {
	// Priority: --config-file > --config > stdin

	configFile, _ := cmd.Flags().GetString("config-file")
	if configFile != "" {
		return loadInitConfigFromFile(configFile)
	}

	configJSON, _ := cmd.Flags().GetString("config")
	if configJSON != "" {
		return loadInitConfigFromString(configJSON)
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
			return loadInitConfigFromString(string(data))
		}
	}

	return nil, fmt.Errorf("no configuration provided - use --config, --config-file, or pipe to stdin")
}

// loadInitConfigFromFile reads config from a JSON file.
func loadInitConfigFromFile(path string) (*initConfig, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open config file: %w", err)
	}
	defer f.Close()

	var cfg initConfig
	decoder := json.NewDecoder(f)
	if err := decoder.Decode(&cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config JSON: %w", err)
	}
	return &cfg, nil
}

// loadInitConfigFromString reads config from a JSON string.
func loadInitConfigFromString(s string) (*initConfig, error) {
	var cfg initConfig
	if err := json.Unmarshal([]byte(s), &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config JSON: %w", err)
	}
	return &cfg, nil
}
