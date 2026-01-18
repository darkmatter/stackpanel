package cmd

import (
	"fmt"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/spf13/cobra"
)

var (
	motdMinimal bool
)

var motdCmd = &cobra.Command{
	Use:   "motd",
	Short: "Display the message of the day",
	Long:  `Display the stackpanel message of the day with available commands, features, and hints.`,
	RunE:  runMOTD,
}

func init() {
	motdCmd.Flags().BoolVar(&motdMinimal, "minimal", false, "Show minimal one-line MOTD")
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

	// Minimal mode - just print a one-liner
	if motdMinimal {
		fmt.Print(tui.RenderMinimalMOTD(cfg.ProjectName))
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

	// Detect services from config
	var services []tui.ServiceStatus
	if cfg.Services != nil {
		for name := range cfg.Services {
			services = append(services, tui.ServiceStatus{
				Name:    name,
				Running: false, // Will be detected by RenderMOTDWithServices
			})
		}
	}

	// Default services to check if none configured
	defaultServices := []string{"postgres", "redis"}

	// Render MOTD
	data := tui.MOTDData{
		ProjectName: cfg.ProjectName,
		Commands:    commands,
		Features:    cfg.MOTD.Features,
		Hints:       cfg.MOTD.Hints,
		Services:    services,
	}

	// Use RenderMOTDWithServices if we have default services to detect
	if len(services) == 0 {
		fmt.Print(tui.RenderMOTDWithServices(data, defaultServices))
	} else {
		fmt.Print(tui.RenderMOTD(data))
	}

	return nil
}
