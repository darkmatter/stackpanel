package cmd

import (
	"fmt"
	"io"
	"os"
	"strings"

	stackconfig "github.com/darkmatter/stackpanel/packages/stackpanel-go/config"
	"github.com/spf13/cobra"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize stackpanel from Nix configuration",
	Long: `Initialize stackpanel by generating files from Nix configuration.

This command is typically called by Nix during  shell entry.
It reads configuration JSON and generates:
  - IDE integration files (VS Code workspace, terminal integration)
  - JSON schemas for YAML intellisense
  - State file for runtime queries

Configuration can be passed via:
  - --config-file <path>   Read from a JSON file
  - --config <json>        Pass JSON directly as argument
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
	cfg, err := loadConfig(cmd)
	if err != nil {
		return err
	}

	// Validate required fields
	if cfg.ProjectName == "" {
		return fmt.Errorf("projectName is required in configuration")
	}
	if cfg.ProjectRoot == "" {
		// Default to current directory if not specified
		cwd, err := os.Getwd()
		if err != nil {
			return fmt.Errorf("failed to get current directory: %w", err)
		}
		cfg.ProjectRoot = cwd
	}

	// Set defaults
	if cfg.Paths.State == "" {
		cfg.Paths.State = ".stackpanel/state"
	}
	if cfg.Paths.Gen == "" {
		cfg.Paths.Gen = ".stackpanel/gen"
	}
	if cfg.Paths.Data == "" {
		cfg.Paths.Data = ".stackpanel"
	}
	if cfg.Version == 0 {
		cfg.Version = 1
	}

	// File generation is now handled by Nix's write-files script.
	// This command now just validates config.

	if !quiet {
		fmt.Printf("Config validated for %s\n", cfg.ProjectName)
		printSuccess("Stackpanel initialized")
	}

	return nil
}

// loadConfig loads configuration from the available sources
func loadConfig(cmd *cobra.Command) (*stackconfig.Config, error) {
	// Priority: --config-file > --config > stdin

	configFile, _ := cmd.Flags().GetString("config-file")
	if configFile != "" {
		return stackconfig.LoadFromFile(configFile)
	}

	configJSON, _ := cmd.Flags().GetString("config")
	if configJSON != "" {
		return stackconfig.LoadFromString(configJSON)
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
			return stackconfig.LoadFromString(string(data))
		}
	}

	return nil, fmt.Errorf("no configuration provided - use --config, --config-file, or pipe to stdin")
}
