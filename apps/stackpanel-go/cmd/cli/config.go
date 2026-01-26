package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/configsync"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/spf13/cobra"
)

var configCmd = &cobra.Command{
	Use:     "config",
	Aliases: []string{"cfg"},
	Short:   "Manage project configuration",
	Long: `Manage the stackpanel configuration.

The config formatter ensures that serializable data defined in
.stackpanel/config.nix gets migrated to .stackpanel/data/*.nix files,
keeping config.nix small (only Nix expressions that can't be plain data)
and data files authoritative.`,
}

var configCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Check if config.nix has entries that should be in data files",
	Long: `Compare the merged user config (_internal.nix) against individual
data files to detect entries defined in config.nix that could be migrated
to .stackpanel/data/*.nix.

Reports:
  - Extra keys: present in merged config but missing from data file (from config.nix)
  - Overridden keys: present in both but with different values (config.nix wins)
  - Entities without data files: entirely defined in config.nix`,
	Run: runConfigCheck,
}

var configSyncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Migrate config.nix entries to data files",
	Long: `Sync serializable entries from config.nix into .stackpanel/data/*.nix files.

This writes the merged values (data + config.nix) back to the data files,
making the config.nix entries redundant. After syncing, you can remove
the migrated entries from config.nix.`,
	Run: runConfigSync,
}

var (
	configJSONOutput bool
)

func init() {
	configCmd.AddCommand(configCheckCmd)
	configCmd.AddCommand(configSyncCmd)
	rootCmd.AddCommand(configCmd)

	// JSON output flag for both subcommands
	configCheckCmd.Flags().BoolVar(&configJSONOutput, "json", false, "Output as JSON")
	configSyncCmd.Flags().BoolVar(&configJSONOutput, "json", false, "Output as JSON")
}

// findConfigProjectRoot finds the project root that contains .stackpanel/config.nix.
// This is more specific than findProjectRoot() which may stop at a subdirectory
// that only has a .stackpanel/state directory.
func findConfigProjectRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}

	for {
		// Check for .stackpanel/config.nix (the actual config file)
		configPath := filepath.Join(dir, ".stackpanel", "config.nix")
		if _, err := os.Stat(configPath); err == nil {
			return dir, nil
		}
		// Also check for flake.nix as a project root indicator
		if _, err := os.Stat(filepath.Join(dir, "flake.nix")); err == nil {
			return dir, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("no project root found (looking for .stackpanel/config.nix or flake.nix)")
		}
		dir = parent
	}
}

func runConfigCheck(cmd *cobra.Command, args []string) {
	projectRoot, err := findConfigProjectRoot()
	if err != nil {
		output.Error(fmt.Sprintf("Failed to find project root: %v", err))
		os.Exit(1)
	}

	verbose, _ := cmd.Flags().GetBool("verbose")
	if verbose {
		output.Info(fmt.Sprintf("Checking config in %s", projectRoot))
	}

	result, err := configsync.Check(projectRoot)
	if err != nil {
		output.Error(fmt.Sprintf("Config check failed: %v", err))
		os.Exit(1)
	}

	if configJSONOutput {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(result); err != nil {
			output.Error(fmt.Sprintf("Failed to encode JSON: %v", err))
			os.Exit(1)
		}
		return
	}

	// Human-readable output
	if result.InSync {
		output.Success("Config is in sync — nothing to migrate")
		return
	}

	if len(result.Diffs) > 0 {
		output.Warning("Found entries in config.nix that should be in data files:")
		fmt.Println()

		for _, diff := range result.Diffs {
			fmt.Printf("  Entity: %s\n", diff.Entity)

			if len(diff.ExtraKeys) > 0 {
				fmt.Printf("    Extra keys (only in config.nix):\n")
				for _, key := range diff.ExtraKeys {
					fmt.Printf("      + %s\n", key)
				}
			}

			if len(diff.OverriddenKeys) > 0 {
				fmt.Printf("    Overridden keys (config.nix differs from data file):\n")
				for _, key := range diff.OverriddenKeys {
					fmt.Printf("      ~ %s\n", key)
				}
			}

			if diff.ValueDiffers {
				fmt.Printf("    Entire value differs (no data file exists)\n")
			}

			fmt.Println()
		}
	}

	if len(result.Errors) > 0 {
		output.Error("Some entities failed to evaluate:")
		for _, e := range result.Errors {
			fmt.Printf("  %s: %s\n", e.Entity, e.Error)
		}
		fmt.Println()
	}

	output.Dimmed("Run 'stackpanel config sync' to migrate these entries to data files.")
}

func runConfigSync(cmd *cobra.Command, args []string) {
	projectRoot, err := findConfigProjectRoot()
	if err != nil {
		output.Error(fmt.Sprintf("Failed to find project root: %v", err))
		os.Exit(1)
	}

	verbose, _ := cmd.Flags().GetBool("verbose")
	if verbose {
		output.Info(fmt.Sprintf("Syncing config in %s", projectRoot))
	}

	result, err := configsync.Sync(projectRoot)
	if err != nil {
		output.Error(fmt.Sprintf("Config sync failed: %v", err))
		os.Exit(1)
	}

	if configJSONOutput {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(result); err != nil {
			output.Error(fmt.Sprintf("Failed to encode JSON: %v", err))
			os.Exit(1)
		}
		return
	}

	// Human-readable output
	if len(result.Updated) == 0 && len(result.Errors) == 0 {
		output.Success("Already in sync — nothing to migrate")
		return
	}

	if len(result.Updated) > 0 {
		output.Success("Migrated entries to data files:")
		fmt.Println()

		for _, update := range result.Updated {
			if len(update.Keys) > 0 {
				fmt.Printf("  %s: %s\n", update.Entity, formatKeyList(update.Keys))
			} else {
				fmt.Printf("  %s: (entire value)\n", update.Entity)
			}
		}
		fmt.Println()
	}

	if len(result.Errors) > 0 {
		output.Error("Some entities failed to sync:")
		for _, e := range result.Errors {
			fmt.Printf("  %s: %s\n", e.Entity, e.Error)
		}
		fmt.Println()
	}

	if len(result.Updated) > 0 {
		output.Dimmed("You can now remove the migrated entries from .stackpanel/config.nix.")
	}
}

// formatKeyList formats a list of keys for display.
func formatKeyList(keys []string) string {
	if len(keys) == 0 {
		return "(none)"
	}
	if len(keys) <= 5 {
		return fmt.Sprintf("[%s]", joinKeys(keys))
	}
	return fmt.Sprintf("[%s, ... +%d more]", joinKeys(keys[:5]), len(keys)-5)
}

func joinKeys(keys []string) string {
	result := ""
	for i, k := range keys {
		if i > 0 {
			result += ", "
		}
		result += k
	}
	return result
}
