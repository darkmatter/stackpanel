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

var devCmd = &cobra.Command{
	Use:   "dev",
	Short: "Manage development mode for running from source",
	Long: `Manage development mode settings for the stackpanel CLI.

When dev mode is enabled, the CLI will forward all commands to 'go run'
in your local stackpanel repository. This allows you to test changes
without rebuilding or reinstalling the binary.

Examples:
  stackpanel dev status                    # Show current dev mode settings
  stackpanel dev enable ~/projects/stackpanel  # Enable dev mode
  stackpanel dev disable                   # Disable dev mode`,
}

var devEnableCmd = &cobra.Command{
	Use:   "enable <repo-path>",
	Short: "Enable development mode with a local repository path",
	Long: `Enable development mode to run stackpanel from source.

When enabled, all stackpanel commands will be forwarded to:
  go run <repo-path>/apps/stackpanel-go <args...>

This allows you to test local changes without rebuilding the binary.

Examples:
  stackpanel dev enable ~/projects/stackpanel
  stackpanel dev enable /absolute/path/to/stackpanel
  stackpanel dev enable .   # Use current directory`,
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
			output.Error(fmt.Sprintf("Failed to enable dev mode: %v", err))
			os.Exit(1)
		}

		output.Success("Development mode enabled")
		fmt.Println()
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Repository:"), color.CyanString(absPath))
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Go app:"), color.CyanString(goAppPath))
		fmt.Println()
		output.Info("All stackpanel commands will now run from source via 'go run'")
		fmt.Println()
		fmt.Printf("  To disable: %s\n", color.YellowString("stackpanel dev disable"))
	},
}

var devDisableCmd = &cobra.Command{
	Use:   "disable",
	Short: "Disable development mode",
	Long:  `Disable development mode and use the installed stackpanel binary.`,
	Run: func(cmd *cobra.Command, args []string) {
		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		devMode := ucm.GetDevMode()
		if !devMode.Enabled {
			output.Info("Development mode is already disabled")
			return
		}

		if err := ucm.SetDevMode(false, ""); err != nil {
			output.Error(fmt.Sprintf("Failed to disable dev mode: %v", err))
			os.Exit(1)
		}

		output.Success("Development mode disabled")
		output.Info("Stackpanel will now use the installed binary")
	},
}

var devStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show current development mode settings",
	Run: func(cmd *cobra.Command, args []string) {
		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		devMode := ucm.GetDevMode()
		configPath := ucm.ConfigPath()

		fmt.Println(color.New(color.Bold).Sprint("Development Mode Status"))
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
			fmt.Printf("  To enable: %s\n", color.CyanString("stackpanel dev enable <repo-path>"))
		} else {
			fmt.Printf("  To disable: %s\n", color.YellowString("stackpanel dev disable"))
		}
	},
}

func init() {
	rootCmd.AddCommand(devCmd)
	devCmd.AddCommand(devEnableCmd)
	devCmd.AddCommand(devDisableCmd)
	devCmd.AddCommand(devStatusCmd)
}
