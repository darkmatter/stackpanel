// status.go implements `stackpanel status`, which shows a unified view of
// all development resources. Prefers an interactive Bubble Tea dashboard;
// falls back to static output when the terminal doesn't support TUI or
// --static/--no-tui is specified.

package cmd

import (
	"fmt"
	"sort"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	svc "github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show status of all services and resources",
	Long: `Show a comprehensive status of all development resources.

This includes:
  - Development services (PostgreSQL, Redis, Minio)
  - Reverse proxy (Caddy)

By default, opens an interactive dashboard. Use --static for non-interactive output.`,
	Run: func(cmd *cobra.Command, args []string) {
		static, _ := cmd.Flags().GetBool("static")
		noTui, _ := cmd.Flags().GetBool("no-tui")
		if !noTui {
			if inherited := cmd.InheritedFlags().Lookup("no-tui"); inherited != nil && inherited.Value.String() == "true" {
				noTui = true
			}
		}
		if static || noTui {
			showFullStatus()
		} else {
			if err := tui.RunStatusDashboard(); err != nil {
				output.Error(fmt.Sprintf("TUI error: %v", err))
				// Fallback to static
				showFullStatus()
			}
		}
	},
}

func init() {
	statusCmd.Flags().Bool("static", false, "Show static status (non-interactive)")
}

// Banner is the ASCII art header shown in static status output.
const Banner = `
       |                 |                                |
  __|  __|   _' |   __|  |  /  __ \    _' |  __ \    _ \  |
\__ \  |    (   |  (       <   |   |  (   |  |   |   __/  |
____/ \__| \__,_| \___| _|\_\  .__/  \__,_| _|  _| \___| _|
                              _|
`

// showFullStatus renders a non-interactive status view combining Nix config
// (apps, services, ports) with live process state (PIDs, Caddy).
// When Nix config is unavailable (e.g. outside a devshell), it falls back
// to the hardcoded service list so the command still works.
func showFullStatus() {
	fmt.Println()
	output.Purple.Print(Banner)

	// Load config from Nix
	cfg, cfgErr := nixconfig.Load()

	// Show project info from config
	if cfgErr == nil && cfg != nil {
		fmt.Printf("\n%s Project: %s (base port: %d)\n", output.Yellow.Sprint("■"), output.Purple.Sprint(cfg.ProjectName), cfg.BasePort)
	}

	// Apps (from config)
	if cfgErr == nil && cfg != nil && len(cfg.Apps) > 0 {
		fmt.Printf("\n%s Apps\n", output.Yellow.Sprint("■"))
		// Sort app names for consistent output
		appNames := cfg.AppNames()
		sort.Strings(appNames)
		for _, name := range appNames {
			app := cfg.Apps[name]
			if app.URL != nil && *app.URL != "" {
				fmt.Printf("  %s %s → %s\n", output.Green.Sprint("●"), name, output.DimC.Sprint(*app.URL))
			} else {
				fmt.Printf("  %s %s (port %d)\n", output.DimC.Sprint("○"), name, app.Port)
			}
		}
	}

	// Services (from config if available, fallback to hardcoded)
	// Config-driven path uses computed ports from Nix; hardcoded path uses
	// the default service registry which computes ports from the project name.
	fmt.Printf("\n%s Development Services\n", output.Yellow.Sprint("■"))
	if cfgErr == nil && cfg != nil && len(cfg.Services) > 0 {
		// Show services from config
		serviceNames := cfg.ServiceNames()
		sort.Strings(serviceNames)
		for _, name := range serviceNames {
			svcInfo := cfg.Services[name]
			showServiceStatusWithPort(name, svcInfo.Name, svcInfo.Port)
		}
	} else {
		// Fallback to hardcoded services
		showServiceStatus("postgres")
		showServiceStatus("redis")
		showServiceStatus("minio")
	}

	// Caddy
	fmt.Printf("\n%s Reverse Proxy\n", output.Yellow.Sprint("■"))
	showCaddyStatusCompact()

	fmt.Println()
}

// showServiceStatusWithPort shows service status with port from config
func showServiceStatusWithPort(name, displayName string, port int) {
	s := svc.Get(name)
	if s == nil {
		output.DimC.Printf("  ○ %s (not registered)\n", displayName)
		return
	}

	status := s.Status()
	if status.Running {
		output.Green.Printf("  ● %s", displayName)
		output.DimC.Printf(" (port %d, PID %d)\n", port, status.PID)
	} else {
		output.DimC.Printf("  ○ %s (port %d, stopped)\n", displayName, port)
	}
}

func showCaddyStatusCompact() {
	pid := readCaddyPidFile(caddyPidFile)
	if pid > 0 && svc.IsProcessRunning(pid) {
		output.Green.Print("  ● Caddy")
		output.DimC.Printf(" (PID: %d)\n", pid)
	} else {
		output.DimC.Println("  ○ Caddy (stopped)")
	}
}
