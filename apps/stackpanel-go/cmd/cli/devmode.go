package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

var debugCmd = &cobra.Command{
	Use:     "debug [args...]",
	Aliases: []string{"dev"},
	Short:   "Run stackpanel from source via 'go run'",
	Long: `Run the stackpanel CLI from source using 'go run'.

Without subcommands (enable/disable/status), this is equivalent to:
  cd <repo-path>/apps/stackpanel-go && go run . [args...]

The repo path is resolved in order:
  1. STACKPANEL_DEV_REPO environment variable
  2. dev_mode.repo_path from ~/.config/stackpanel/stackpanel.yaml
  3. Auto-detected from the current working directory

Any arguments after 'debug' are forwarded to the 'go run' invocation.

Examples:
  stackpanel debug                           # Run 'go run .' (shows help)
  stackpanel debug nixify .gitignore         # Run 'go run . nixify .gitignore'
  stackpanel debug status                    # Show current debug mode settings
  stackpanel debug enable ~/projects/stackpanel  # Enable debug mode
  stackpanel debug disable                   # Disable debug mode`,
	// Disable flag parsing so all args after 'debug' are passed through
	DisableFlagParsing: true,
	RunE:               runDebug,
}

// runDebug handles `stackpanel debug [args...]`.
// If the first arg is a known subcommand (enable/disable/status), it delegates.
// Otherwise it resolves the repo path and execs `go run . <args...>`.
func runDebug(cmd *cobra.Command, args []string) error {
	// Check if the first arg is a known subcommand or help flag
	if len(args) > 0 {
		switch args[0] {
		case "enable":
			subArgs := args[1:]
			if len(subArgs) != 1 {
				return fmt.Errorf("'debug enable' requires exactly 1 argument: <repo-path>")
			}
			debugEnableCmd.Run(debugEnableCmd, subArgs)
			return nil
		case "disable":
			debugDisableCmd.Run(debugDisableCmd, args[1:])
			return nil
		case "status":
			debugStatusCmd.Run(debugStatusCmd, args[1:])
			return nil
		case "-h", "--help", "help":
			return cmd.Help()
		}
	}

	// Resolve the repo path
	repoPath := resolveDevRepoPath()
	if repoPath == "" {
		return fmt.Errorf("no stackpanel repo path configured\n\n" +
			"Set one of:\n" +
			"  stackpanel debug enable <repo-path>\n" +
			"  export STACKPANEL_DEV_REPO=<repo-path>")
	}

	goAppDir := filepath.Join(repoPath, "apps", "stackpanel-go")
	mainGo := filepath.Join(goAppDir, "main.go")
	if _, err := os.Stat(mainGo); os.IsNotExist(err) {
		return fmt.Errorf("invalid stackpanel repo: %s\n  expected %s to exist", repoPath, mainGo)
	}

	// Build the command: go run . <args...>
	goPath, err := exec.LookPath("go")
	if err != nil {
		return fmt.Errorf("'go' not found in PATH: %w", err)
	}

	// Use syscall.Exec to replace this process entirely, just like
	// `cd <repo>/apps/stackpanel-go && go run . <args...>`
	execArgs := []string{"go", "run", "."}
	execArgs = append(execArgs, args...)

	if os.Getenv("STACKPANEL_DEBUG") == "1" {
		fmt.Fprintf(os.Stderr, "[debug-mode] cd %s && go run . %v\n", goAppDir, args)
	}

	// Change to the go app directory
	if err := os.Chdir(goAppDir); err != nil {
		return fmt.Errorf("failed to chdir to %s: %w", goAppDir, err)
	}

	// Exec replaces the current process
	return syscall.Exec(goPath, execArgs, os.Environ())
}

// resolveDevRepoPath determines the stackpanel repo path from (in order):
//  1. STACKPANEL_DEV_REPO env var
//  2. user config dev_mode.repo_path (if enabled)
//  3. auto-detect from cwd by walking up to find apps/stackpanel-go
func resolveDevRepoPath() string {
	// 1. Environment variable
	if envPath := os.Getenv("STACKPANEL_DEV_REPO"); envPath != "" {
		if len(envPath) > 0 && envPath[0] == '~' {
			if home, err := os.UserHomeDir(); err == nil {
				envPath = filepath.Join(home, envPath[1:])
			}
		}
		if abs, err := filepath.Abs(envPath); err == nil {
			return abs
		}
		return envPath
	}

	// 2. User config
	if ucm, err := userconfig.NewManager(); err == nil {
		dm := ucm.GetDevMode()
		if dm.Enabled && dm.RepoPath != "" {
			return dm.RepoPath
		}
	}

	// 3. Auto-detect: walk up from cwd looking for apps/stackpanel-go/main.go
	if cwd, err := os.Getwd(); err == nil {
		dir := cwd
		for {
			candidate := filepath.Join(dir, "apps", "stackpanel-go", "main.go")
			if _, err := os.Stat(candidate); err == nil {
				return dir
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}

	return ""
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
