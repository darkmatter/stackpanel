package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	_ "github.com/darkmatter/stackpanel/stackpanel-go/internal/services" // register built-in dev services
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui/navigation"
)

var (
	// Version info (set at build time)
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

	// Handle --no-color flag
	rootCmd.PersistentPreRun = func(cmd *cobra.Command, args []string) {
		noColor, _ := cmd.Flags().GetBool("no-color")
		if noColor {
			output.SetNoColor(true)
		}
	}
}
