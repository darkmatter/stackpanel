package cmd

import (
	"fmt"

	"github.com/darkmatter/stackpanel/cli/internal/nixconfig"
	"github.com/darkmatter/stackpanel/cli/internal/tui"
	"github.com/spf13/cobra"
)

var motdCmd = &cobra.Command{
	Use:   "motd",
	Short: "Display the message of the day",
	Long:  `Display the stackpanel message of the day with available commands, features, and hints.`,
	RunE:  runMOTD,
}

func init() {
	rootCmd.AddCommand(motdCmd)
}

func runMOTD(cmd *cobra.Command, args []string) error {
	// Load config from Nix
	cfg, err := nixconfig.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	// Check if MOTD is enabled
	if !cfg.MOTD.Enable {
		return nil
	}

	// Convert config commands to TUI format
	commands := make([]tui.MOTDCommand, len(cfg.MOTD.Commands))
	for i, c := range cfg.MOTD.Commands {
		commands[i] = tui.MOTDCommand{
			Name:        c.Name,
			Description: c.Description,
		}
	}

	// Render MOTD
	data := tui.MOTDData{
		ProjectName: cfg.ProjectName,
		Commands:    commands,
		Features:    cfg.MOTD.Features,
		Hints:       cfg.MOTD.Hints,
	}

	fmt.Print(tui.RenderMOTD(data))
	return nil
}
