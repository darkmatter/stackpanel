package cmd

import (
	"fmt"
	"os"
	"sort"

	"github.com/darkmatter/stackpanel/cli/internal/services"
	"github.com/darkmatter/stackpanel/cli/internal/state"
	"github.com/darkmatter/stackpanel/cli/internal/tui"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show status of all services and resources",
	Long: `Show a comprehensive status of all development resources.

This includes:
  - Development services (PostgreSQL, Redis, Minio)
  - Reverse proxy (Caddy)
  - Certificates

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
	purple.Println(Banner)

	// Load state file if available
	st, stateErr := state.Load("")

	// Show project info from state
	if stateErr == nil && st != nil {
		fmt.Printf("\n%s Project: %s (base port: %d)\n", yellow.Sprint("■"), purple.Sprint(st.ProjectName), st.BasePort)
	}

	// Apps (from state file)
	if stateErr == nil && st != nil && len(st.Apps) > 0 {
		fmt.Printf("\n%s Apps\n", yellow.Sprint("■"))
		// Sort app names for consistent output
		appNames := st.AppNames()
		sort.Strings(appNames)
		for _, name := range appNames {
			app := st.Apps[name]
			if app.URL != nil && *app.URL != "" {
				fmt.Printf("  %s %s → %s\n", green.Sprint("●"), name, dim.Sprint(*app.URL))
			} else {
				fmt.Printf("  %s %s (port %d)\n", dim.Sprint("○"), name, app.Port)
			}
		}
	}

	// Services (from state file if available, fallback to hardcoded)
	fmt.Printf("\n%s Development Services\n", yellow.Sprint("■"))
	if stateErr == nil && st != nil && len(st.Services) > 0 {
		// Show services from state
		serviceNames := st.ServiceNames()
		sort.Strings(serviceNames)
		for _, name := range serviceNames {
			svc := st.Services[name]
			showServiceStatusWithPort(name, svc.Name, svc.Port)
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

	// Certificates
	fmt.Printf("\n%s Certificates\n", yellow.Sprint("■"))
	showCertStatusCompact()

	fmt.Println()
}

// showServiceStatusWithPort shows service status with port from state
func showServiceStatusWithPort(name, displayName string, port int) {
	svc := services.Get(name)
	if svc == nil {
		dim.Printf("  ○ %s (not registered)\n", displayName)
		return
	}

	status := svc.Status()
	if status.Running {
		green.Printf("  ● %s", displayName)
		dim.Printf(" (port %d, PID %d)\n", port, status.PID)
	} else {
		dim.Printf("  ○ %s (port %d, stopped)\n", displayName, port)
	}
}

func showCaddyStatusCompact() {
	pid := readCaddyPidFile(caddyPidFile)
	if pid > 0 && services.IsProcessRunning(pid) {
		green.Print("  ● Caddy")
		dim.Printf(" (PID: %d)\n", pid)
	} else {
		dim.Println("  ○ Caddy (stopped)")
	}
}

func showCertStatusCompact() {
	certFile, _ := getCertPaths()
	if _, err := os.Stat(certFile); err == nil {
		green.Println("  ● Device certificate present")
	} else {
		dim.Println("  ○ No device certificate")
	}
}
