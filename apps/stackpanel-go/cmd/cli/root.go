// Package cmd implements the Cobra command tree for the stackpanel CLI.
//
// The root command launches an interactive TUI by default. All subcommands
// (services, caddy, agent, deploy, etc.) are registered via init() functions
// in their respective files.
package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	_ "github.com/darkmatter/stackpanel/stackpanel-go/internal/services" // register built-in dev services via init()
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui/navigation"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

var (
	// Version and BuildDate are set at build time via -ldflags.
	// The "dev" default lets you identify local/untagged builds.
	Version   = "dev"
	BuildDate = "unknown"
)

var rootCmd = &cobra.Command{
	Use:   "stackpanel",
	Short: "Stackpanel development CLI",
	Long: `Stackpanel CLI - unified development environment management.

Manage development services and infrastructure
from a single command-line interface.

Run without arguments to launch the interactive TUI.`,
	Version: Version,
	Run: func(cmd *cobra.Command, args []string) {
		// Get flags
		noTUI, _ := cmd.Flags().GetBool("no-tui")
		daemon, _ := cmd.Flags().GetBool("daemon")

		// Determine run mode
		runMode := tui.DetermineRunMode(daemon, noTUI)

		switch runMode {
		case tui.RunModeInteractive:
			// Launch the TUI navigator
			if err := navigation.RunNavigation(cmd); err != nil {
				output.Error(fmt.Sprintf("TUI error: %v", err))
				os.Exit(1)
			}
		case tui.RunModeDaemon:
			// Daemon mode - just print status and stay running (or exit)
			output.Info("Running in daemon mode (no TUI)")
			// For now, just show help in daemon mode without TUI
			cmd.Help()
		case tui.RunModeDirect:
			// No TUI mode - show help
			cmd.Help()
		}
	},
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	// Global flags
	rootCmd.PersistentFlags().BoolP("verbose", "v", false, "Enable verbose output")
	rootCmd.PersistentFlags().Bool("no-color", false, "Disable color output")
	rootCmd.PersistentFlags().Bool("no-tui", false, "Disable interactive TUI mode")
	rootCmd.PersistentFlags().BoolP("daemon", "d", false, "Run in daemon mode (no TUI, for background processes)")

	// Add subcommands
	rootCmd.AddCommand(servicesCmd)
	rootCmd.AddCommand(caddyCmd)
	rootCmd.AddCommand(statusCmd)
	rootCmd.AddCommand(agentCmd)
	rootCmd.AddCommand(usersCmd)
	rootCmd.AddCommand(deployCmd)
	rootCmd.AddCommand(provisionCmd)
	// rootCmd.AddCommand(secretsCmd)

	// Handle --no-color flag and optional auto-register
	rootCmd.PersistentPreRun = func(cmd *cobra.Command, args []string) {
		noColor, _ := cmd.Flags().GetBool("no-color")
		if noColor {
			output.SetNoColor(true)
		}

		// Auto-detect and register project if explicitly enabled via environment variable.
		// This is opt-in because automatic registration can be surprising.
		// Set STACKPANEL_AUTO_REGISTER=1 to enable.
		//
		// Projects are still registered automatically by:
		// - stackpanel agent (when started from a project directory)
		// - stackpanel hook (when Nix calls it during shell entry)
		// - stackpanel init (after creating project structure)
		// - stackpanel project add (with user confirmation)
		if os.Getenv("STACKPANEL_AUTO_REGISTER") == "1" {
			// Skip for commands that handle registration themselves
			skipCommands := map[string]bool{
				"help":    true,
				"version": true,
				"dev":     true,
				"project": true,
				"agent":   true,
				"hook":    true,
				"init":    true,
			}

			if !skipCommands[cmd.Name()] {
				autoRegisterCurrentProject()
			}
		}
	}
}

// autoRegisterCurrentProject detects if we're in a stackpanel project
// and registers it in the user config if not already known.
// This is only called when STACKPANEL_AUTO_REGISTER=1 is set.
// It runs silently and doesn't fail the command if registration fails.
func autoRegisterCurrentProject() {
	projectPath := detectStackpanelProject()
	if projectPath == "" {
		return
	}

	ucm, err := userconfig.NewManager()
	if err != nil {
		return // Silently skip if config manager fails
	}

	// Only add if not already known
	if !ucm.HasProject(projectPath) {
		name := filepath.Base(projectPath)
		_, _ = ucm.AddProject(projectPath, name)
	}
}

// detectStackpanelProject walks up from cwd looking for a project root.
// It checks two markers: .stack/config.nix (stackpanel-native) and
// flake.nix + .git (Nix flake project). Returns "" if no project is found.
func detectStackpanelProject() string {
	cwd, err := os.Getwd()
	if err != nil {
		return ""
	}

	dir := cwd
	for {
		// Check for .stack/config.nix
		configPath := filepath.Join(dir, ".stack", "config.nix")
		if _, err := os.Stat(configPath); err == nil {
			return dir
		}

		// Check for flake.nix with .git (likely a stackpanel project)
		flakePath := filepath.Join(dir, "flake.nix")
		gitPath := filepath.Join(dir, ".git")
		if _, err := os.Stat(flakePath); err == nil {
			if _, err := os.Stat(gitPath); err == nil {
				return dir
			}
		}

		// Move to parent directory
		parent := filepath.Dir(dir)
		if parent == dir {
			// Reached root, no project found
			break
		}
		dir = parent
	}

	return ""
}
