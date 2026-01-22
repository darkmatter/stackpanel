package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

var debugCmd = &cobra.Command{
	Use:     "debug",
	Aliases: []string{"dev"},
	Short:   "Manage debug mode (run stackpanel from source)",
	Long: `Manage debug mode settings for the stackpanel CLI.

When debug mode is enabled, the CLI will forward all commands to 'go run'
in your local stackpanel repository. This allows you to test changes
without rebuilding or reinstalling the binary.

Examples:
  stackpanel debug status                    # Show current debug mode settings
  stackpanel debug enable ~/projects/stackpanel  # Enable debug mode
  stackpanel debug disable                   # Disable debug mode

Alias:
  stackpanel dev ... (legacy alias)`,
}

var debugEnableCmd = &cobra.Command{
	Use:   "enable <repo-path>",
	Short: "Enable debug mode with a local repository path",
	Long: `Enable debug mode to run stackpanel from source.

When enabled, all stackpanel commands will be forwarded to:
  go run <repo-path>/apps/stackpanel-go <args...>

This allows you to test local changes without rebuilding the binary.

Examples:
  stackpanel debug enable ~/projects/stackpanel
  stackpanel debug enable /absolute/path/to/stackpanel
  stackpanel debug enable .   # Use current directory`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		repoPath := args[0]

		// Resolve the path
		if repoPath == "." {
			cwd, err := os.Getwd()
			if err != nil {
				output.Error(fmt.Sprintf("Failed to get current directory: %v", err))
				os.Exit(1)
			}
			repoPath = cwd
		}

		// Expand ~ if present
		if len(repoPath) > 0 && repoPath[0] == '~' {
			home, err := os.UserHomeDir()
			if err != nil {
				output.Error(fmt.Sprintf("Failed to get home directory: %v", err))
				os.Exit(1)
			}
			repoPath = filepath.Join(home, repoPath[1:])
		}

		// Make absolute
		absPath, err := filepath.Abs(repoPath)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to resolve path: %v", err))
			os.Exit(1)
		}

		// Validate the path exists and looks like a stackpanel repo
		goAppPath := filepath.Join(absPath, "apps", "stackpanel-go")
		mainGoPath := filepath.Join(goAppPath, "main.go")
		if _, err := os.Stat(mainGoPath); os.IsNotExist(err) {
			output.Error(fmt.Sprintf("Invalid stackpanel repository: %s", absPath))
			output.Warning(fmt.Sprintf("Expected to find: %s", mainGoPath))
			os.Exit(1)
		}

		// Update config
		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		if err := ucm.SetDevMode(true, absPath); err != nil {
			output.Error(fmt.Sprintf("Failed to enable debug mode: %v", err))
			os.Exit(1)
		}

		output.Success("Debug mode enabled")
		fmt.Println()
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Repository:"), color.CyanString(absPath))
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Go app:"), color.CyanString(goAppPath))
		fmt.Println()
		output.Info("All stackpanel commands will now run from source via 'go run'")
		fmt.Println()
		fmt.Printf("  To disable: %s\n", color.YellowString("stackpanel debug disable"))
	},
}

var debugDisableCmd = &cobra.Command{
	Use:   "disable",
	Short: "Disable debug mode",
	Long:  `Disable debug mode and use the installed stackpanel binary.`,
	Run: func(cmd *cobra.Command, args []string) {
		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		devMode := ucm.GetDevMode()
		if !devMode.Enabled {
			output.Info("Debug mode is already disabled")
			return
		}

		if err := ucm.SetDevMode(false, ""); err != nil {
			output.Error(fmt.Sprintf("Failed to disable debug mode: %v", err))
			os.Exit(1)
		}

		output.Success("Debug mode disabled")
		output.Info("Stackpanel will now use the installed binary")
	},
}

var debugStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show current debug mode settings",
	Run: func(cmd *cobra.Command, args []string) {
		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		devMode := ucm.GetDevMode()
		configPath := ucm.ConfigPath()

		fmt.Println(color.New(color.Bold).Sprint("Debug Mode Status"))
		fmt.Println()

		if devMode.Enabled {
			fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Status:"), color.GreenString("enabled"))
			fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Repository:"), color.CyanString(devMode.RepoPath))

			// Check if the repo still exists
			goAppPath := filepath.Join(devMode.RepoPath, "apps", "stackpanel-go", "main.go")
			if _, err := os.Stat(goAppPath); os.IsNotExist(err) {
				fmt.Println()
				output.Warning("Repository path no longer exists or is invalid!")
			}
		} else {
			fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Status:"), color.YellowString("disabled"))
		}

		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Config:"), configPath)
		fmt.Println()

		if !devMode.Enabled {
			fmt.Printf("  To enable: %s\n", color.CyanString("stackpanel debug enable <repo-path>"))
			fmt.Printf("  Alias: %s\n", color.CyanString("stackpanel dev enable <repo-path>"))
		} else {
			fmt.Printf("  To disable: %s\n", color.YellowString("stackpanel debug disable"))
			fmt.Printf("  Alias: %s\n", color.YellowString("stackpanel dev disable"))
		}
	},
}

func init() {
	rootCmd.AddCommand(debugCmd)
	debugCmd.AddCommand(debugEnableCmd)
	debugCmd.AddCommand(debugDisableCmd)
	debugCmd.AddCommand(debugStatusCmd)
}
