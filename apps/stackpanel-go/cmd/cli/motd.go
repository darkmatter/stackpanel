package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/spf13/cobra"
)

var (
	motdMinimal bool
	motdJSON    bool
	motdLegacy  bool
	motdForce   bool
)

var motdCmd = &cobra.Command{
	Use:   "motd",
	Short: "Display the message of the day",
	Long: `Display the stackpanel message of the day with status, commands, and hints.

The MOTD shows:
  - Agent and service status
  - AWS credentials status
  - Generated files status
  - Health check summary
  - Available commands
  - Quick start instructions
  - Useful shortcuts (sp, spx)

Examples:
  stackpanel motd              # Show full MOTD
  stackpanel motd --minimal    # Show one-line status
  stackpanel motd --json       # Output status as JSON
  stackpanel motd --legacy     # Use the legacy MOTD format
  stackpanel motd --force      # Show MOTD even if disabled`,
	RunE: runMOTD,
}

func init() {
	motdCmd.Flags().BoolVar(&motdMinimal, "minimal", false, "Show minimal one-line MOTD")
	motdCmd.Flags().BoolVar(&motdJSON, "json", false, "Output MOTD data as JSON")
	motdCmd.Flags().BoolVar(&motdLegacy, "legacy", false, "Use legacy MOTD format")
	motdCmd.Flags().BoolVar(&motdForce, "force", false, "Show MOTD even if disabled in config")
	rootCmd.AddCommand(motdCmd)
}

func runMOTD(cmd *cobra.Command, args []string) error {
	// Load config from Nix
	cfg, err := nixconfig.Load()
	if err != nil {
		// Don't fail completely, just use defaults
		cfg = &nixconfig.Config{
			ProjectName: "",
			ProjectRoot: os.Getenv("STACKPANEL_PROJECT_ROOT"),
		}
	}

	// Check if MOTD is enabled (skip this check for JSON output, force, or minimal flags)
	if !motdJSON && !motdForce && !motdMinimal && !cfg.MOTD.Enable {
		// MOTD disabled and no override flags
		return nil
	}

	// Minimal mode - just print a one-liner
	if motdMinimal {
		fmt.Fprint(os.Stderr, tui.RenderMinimalMOTD(cfg.ProjectName))
		return nil
	}

	// Build options for local healthcheck execution
	var motdOpts *tui.CollectMOTDDataOpts
	if len(cfg.Healthchecks) > 0 {
		stateDir := cfg.Paths.State
		if stateDir == "" {
			stateDir = ".stack/profile"
		}
		// Make stateDir absolute relative to project root
		if cfg.ProjectRoot != "" && !filepath.IsAbs(stateDir) {
			stateDir = filepath.Join(cfg.ProjectRoot, stateDir)
		}
		motdOpts = &tui.CollectMOTDDataOpts{
			Healthchecks: cfg.Healthchecks,
			StateDir:     stateDir,
		}
	}

	// Collect all MOTD data
	data := tui.CollectMOTDData(
		cfg.ProjectName,
		cfg.ProjectRoot,
		Version,
		9876, // Default agent port
		motdOpts,
	)

	// Pass missing flake inputs from Nix config
	if len(cfg.MissingFlakeInputs) > 0 {
		for _, fi := range cfg.MissingFlakeInputs {
			data.MissingFlakeInputs = append(data.MissingFlakeInputs, tui.MissingFlakeInput{
				Name:           fi.Name,
				URL:            fi.URL,
				FollowsNixpkgs: fi.FollowsNixpkgs,
				RequiredBy:     fi.RequiredBy,
			})
		}
		// Re-collect issues now that we have missing flake inputs
		data.Issues = tui.CollectIssues(data)
	}

	// Detect services from config and check their status
	if cfg.Services != nil {
		for name := range cfg.Services {
			data.Services = append(data.Services, tui.ServiceStatus{
				Name:    name,
				Running: checkDockerServiceStatus(name),
			})
		}
	}

	// If no services from config, check default services
	if len(data.Services) == 0 {
		defaultServices := []string{"postgres", "redis"}
		for _, name := range defaultServices {
			data.Services = append(data.Services, tui.ServiceStatus{
				Name:    name,
				Running: checkDockerServiceStatus(name),
			})
		}
	}

	// JSON output mode
	if motdJSON {
		jsonData, err := json.MarshalIndent(data, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal MOTD data: %w", err)
		}
		fmt.Println(string(jsonData))
		return nil
	}

	// Legacy mode - use old MOTD format
	if motdLegacy {
		return renderLegacyMOTD(cfg)
	}

	// Render improved MOTD
	fmt.Fprint(os.Stderr, tui.RenderImprovedMOTD(data))
	return nil
}

// renderLegacyMOTD renders the old-style MOTD for backward compatibility
func renderLegacyMOTD(cfg *nixconfig.Config) error {
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
	defaultServices := []string{}

	// Render MOTD
	legacyData := tui.MOTDData{
		ProjectName: cfg.ProjectName,
		Commands:    commands,
		Features:    cfg.MOTD.Features,
		Hints:       cfg.MOTD.Hints,
		Services:    services,
	}

	// Use RenderMOTDWithServices if we have default services to detect
	if len(services) == 0 {
		fmt.Fprint(os.Stderr, tui.RenderMOTDWithServices(legacyData, defaultServices))
	} else {
		fmt.Fprint(os.Stderr, tui.RenderMOTD(legacyData))
	}

	return nil
}

// checkDockerServiceStatus checks if a docker compose service is running
func checkDockerServiceStatus(service string) bool {
	cmd := exec.Command("docker", "compose", "ps", "--format", "{{.State}}", "--filter", fmt.Sprintf("name=%s", service))
	output, err := cmd.Output()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(output)), "running")
}
