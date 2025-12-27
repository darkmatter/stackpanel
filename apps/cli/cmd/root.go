package cmd

import (
	"fmt"
	"os"

	"github.com/fatih/color"
	"github.com/spf13/cobra"
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

Manage development services, certificates, and infrastructure
from a single command-line interface.`,
	Version: Version,
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	// Global flags
	rootCmd.PersistentFlags().BoolP("verbose", "v", false, "Enable verbose output")
	rootCmd.PersistentFlags().Bool("no-color", false, "Disable color output")

	// Add subcommands
	rootCmd.AddCommand(servicesCmd)
	rootCmd.AddCommand(certsCmd)
	rootCmd.AddCommand(caddyCmd)
	rootCmd.AddCommand(statusCmd)
	rootCmd.AddCommand(agentCmd)

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
