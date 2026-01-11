package cmd

import (
	"fmt"
	"sort"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
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
		if static {
			showFullStatus()
		} else {
			if err := tui.RunStatusDashboard(); err != nil {
				printError(fmt.Sprintf("TUI error: %v", err))
				// Fallback to static
				showFullStatus()
			}
		}
	},
}

func init() {
	statusCmd.Flags().Bool("static", false, "Show static status (non-interactive)")
}

const Banner = `
       |                 |                                |
  __|  __|   _' |   __|  |  /  __ \    _' |  __ \    _ \  |
\__ \  |    (   |  (       <   |   |  (   |  |   |   __/  |
____/ \__| \__,_| \___| _|\_\  .__/  \__,_| _|  _| \___| _|
                              _|
`

func showFullStatus() {
	fmt.Println()
	purple.Print(Banner)

	// Load config from Nix
	cfg, cfgErr := nixconfig.Load()

	// Show project info from config
	if cfgErr == nil && cfg != nil {
		fmt.Printf("\n%s Project: %s (base port: %d)\n", yellow.Sprint("■"), purple.Sprint(cfg.ProjectName), cfg.BasePort)
	}

	// Apps (from config)
	if cfgErr == nil && cfg != nil && len(cfg.Apps) > 0 {
		fmt.Printf("\n%s Apps\n", yellow.Sprint("■"))
		// Sort app names for consistent output
		appNames := cfg.AppNames()
		sort.Strings(appNames)
		for _, name := range appNames {
			app := cfg.Apps[name]
			if app.URL != nil && *app.URL != "" {
				fmt.Printf("  %s %s → %s\n", green.Sprint("●"), name, dim.Sprint(*app.URL))
			} else {
				fmt.Printf("  %s %s (port %d)\n", dim.Sprint("○"), name, app.Port)
			}
		}
	}

	// Services (from config if available, fallback to hardcoded)
	fmt.Printf("\n%s Development Services\n", yellow.Sprint("■"))
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
	fmt.Printf("\n%s Reverse Proxy\n", yellow.Sprint("■"))
	showCaddyStatusCompact()

	fmt.Println()
}

// showServiceStatusWithPort shows service status with port from config
func showServiceStatusWithPort(name, displayName string, port int) {
	s := svc.Get(name)
	if s == nil {
		dim.Printf("  ○ %s (not registered)\n", displayName)
		return
	}

	status := s.Status()
	if status.Running {
		green.Printf("  ● %s", displayName)
		dim.Printf(" (port %d, PID %d)\n", port, status.PID)
	} else {
		dim.Printf("  ○ %s (port %d, stopped)\n", displayName, port)
	}
}

func showCaddyStatusCompact() {
	pid := readCaddyPidFile(caddyPidFile)
	if pid > 0 && svc.IsProcessRunning(pid) {
		green.Print("  ● Caddy")
		dim.Printf(" (PID: %d)\n", pid)
	} else {
		dim.Println("  ○ Caddy (stopped)")
	}
}
