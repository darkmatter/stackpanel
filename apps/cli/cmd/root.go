package cmd

import (
	"fmt"
	"os"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	_ "github.com/darkmatter/stackpanel/cli/internal/services" // register built-in dev services
	"github.com/darkmatter/stackpanel/cli/internal/tui"
	"github.com/darkmatter/stackpanel/cli/internal/tui/navigation"
)

var (
	// Version info (set at build time)
	Version   = "dev"
	BuildDate = "unknown"

	// Colors (kept for backward compatibility with non-TUI commands)
	purple = color.New(color.Attribute(38), color.Attribute(5), color.Attribute(99)) // 256-color purple (code 99)
	green  = color.New(color.FgGreen)
	yellow = color.New(color.FgYellow)
	dim    = color.New(color.Faint)
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
				printError(fmt.Sprintf("TUI error: %v", err))
				os.Exit(1)
			}
		case tui.RunModeDaemon:
			// Daemon mode - just print status and stay running (or exit)
			printInfo("Running in daemon mode (no TUI)")
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
			color.NoColor = true
		}
	}
}

// Helper functions for common output patterns
func printSuccess(msg string) {
	green.Print("✓ ")
	fmt.Println(msg)
}

func printInfo(msg string) {
	purple.Print("→ ")
	fmt.Println(msg)
}

func printWarning(msg string) {
	yellow.Print("⚠ ")
	fmt.Println(msg)
}

func printError(msg string) {
	color.New(color.FgRed).Print("✗ ")
	fmt.Fprintln(os.Stderr, msg)
}

func printDim(msg string) {
	dim.Println(msg)
}
