// services.go implements project-local development service management
// (postgres, redis, minio, etc.). Services are registered via init() in
// internal/services and discovered through the svc.Registry pattern.
// Data is stored in .stack/state/services/ so different projects can
// use different versions and configs simultaneously.

package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	svc "github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
	"github.com/spf13/cobra"
)

var servicesCmd = &cobra.Command{
	Use:     "services",
	Aliases: []string{"svc", "s"},
	Short:   "Manage development services",
	Long: `Manage project-local development services (PostgreSQL, Redis, Minio, etc.)

Services are project-local by default, with data stored in .stack/state/services/
This allows different projects to use different versions and configurations.

Note: Caddy is a global service (shared across projects) to avoid port 443 conflicts.`,
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		// InitForProject discovers the project root and sets up per-project
		// data directories. Passing "" triggers auto-detection from cwd.
		svc.InitForProject("")
	},
}

var servicesStartCmd = &cobra.Command{
	Use:   "start [service...]",
	Short: "Start services (all if none specified)",
	Long: `Start development svc.

If no services are specified, starts all configured svc.
If a service is already running, it will be reattached.

Examples:
  stackpanel services start           # Start all services
  stackpanel services start postgres  # Start only PostgreSQL
  stackpanel services start pg redis  # Start PostgreSQL and Redis`,
	Run: func(cmd *cobra.Command, args []string) {
		noTui, _ := cmd.Flags().GetBool("no-tui")

		// Resolve aliases (e.g. "pg" -> "postgres") via svc.Normalize.
		var svcNames []string
		if len(args) == 0 {
			svcNames = svc.Names()
		} else {
			for _, arg := range args {
				svcNames = append(svcNames, svc.Normalize(arg))
			}
		}

		if noTui {
			for _, name := range svcNames {
				startService(name)
			}
		} else {
			// TUI mode with automatic fallback: if the terminal doesn't
			// support Bubble Tea (e.g. CI, piped output), fall through
			// to the plain-text path so scripts still work.
			if err := tui.RunStartServices(svcNames); err != nil {
				output.Error(fmt.Sprintf("TUI error: %v", err))
				for _, name := range svcNames {
					startService(name)
				}
			}
		}
	},
}

var servicesStopCmd = &cobra.Command{
	Use:   "stop [service...]",
	Short: "Stop services (all if none specified)",
	Run: func(cmd *cobra.Command, args []string) {
		var svcNames []string
		if len(args) == 0 {
			svcNames = svc.Names()
		} else {
			for _, arg := range args {
				svcNames = append(svcNames, svc.Normalize(arg))
			}
		}

		// Reverse order mirrors dependency topology: stop dependents (apps)
		// before their backends (databases) to avoid connection errors during
		// shutdown.
		for i := len(svcNames) - 1; i >= 0; i-- {
			stopService(svcNames[i])
		}
	},
}

var servicesStatusCmd = &cobra.Command{
	Use:   "status [service...]",
	Short: "Show service status",
	Run: func(cmd *cobra.Command, args []string) {
		var svcNames []string
		if len(args) == 0 {
			svcNames = svc.Names()
		} else {
			for _, arg := range args {
				svcNames = append(svcNames, svc.Normalize(arg))
			}
		}

		for _, name := range svcNames {
			showServiceStatus(name)
		}
	},
}

var servicesRestartCmd = &cobra.Command{
	Use:   "restart [service...]",
	Short: "Restart services",
	Run: func(cmd *cobra.Command, args []string) {
		var svcNames []string
		if len(args) == 0 {
			svcNames = svc.Names()
		} else {
			for _, arg := range args {
				svcNames = append(svcNames, svc.Normalize(arg))
			}
		}

		// Stop in reverse order
		for i := len(svcNames) - 1; i >= 0; i-- {
			stopService(svcNames[i])
		}
		// Start in order
		for _, name := range svcNames {
			startService(name)
		}
	},
}

var servicesLogsCmd = &cobra.Command{
	Use:   "logs [service]",
	Short: "Show service logs",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		follow, _ := cmd.Flags().GetBool("follow")
		lines, _ := cmd.Flags().GetInt("lines")
		showServiceLogs(svc.Normalize(args[0]), follow, lines)
	},
}

var servicesListCmd = &cobra.Command{
	Use:   "list",
	Short: "List available services",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("Available services:")
		for _, svc := range svc.All() {
			status := svc.Status()
			statusIcon := output.DimC.Sprint("○")
			if status.Running {
				statusIcon = output.Green.Sprint("●")
			}
			fmt.Printf("  %s %s (%s)\n", statusIcon, svc.Name(), svc.DisplayName())
		}
	},
}

// servicesComputePortCmd is an unlisted helper for scripting and debugging
// the deterministic port algorithm (project-name hash → stable port).
var servicesComputePortCmd = &cobra.Command{
	Use:   "port [service-name]",
	Short: "Compute stable port for a service based on project name",
	Run: func(cmd *cobra.Command, args []string) {
		serviceName := args[0]
		port := svc.ComputePort(serviceName, "")
		fmt.Printf("%d\n", port)
	},
}

func init() {
	servicesCmd.AddCommand(servicesStartCmd)
	servicesCmd.AddCommand(servicesStopCmd)
	servicesCmd.AddCommand(servicesStatusCmd)
	servicesCmd.AddCommand(servicesRestartCmd)
	servicesCmd.AddCommand(servicesLogsCmd)
	servicesCmd.AddCommand(servicesListCmd)

	servicesLogsCmd.Flags().BoolP("follow", "f", false, "Follow log output")
	servicesLogsCmd.Flags().IntP("lines", "n", 50, "Number of lines to show")
	servicesStartCmd.Flags().Bool("no-tui", false, "Disable interactive TUI")
}

func startService(name string) {
	svc := svc.Get(name)
	if svc == nil {
		output.Error(fmt.Sprintf("Unknown service: %s", name))
		return
	}

	fmt.Printf("\n%s %s\n", output.Purple.Sprint("==>"), svc.DisplayName())

	// Check if already running
	status := svc.Status()
	if status.Running {
		output.Success(fmt.Sprintf("Already running (PID: %d)", status.PID))
		output.Dimmed(fmt.Sprintf("  Port: %d", svc.Port()))
		return
	}

	output.Info("Starting...")
	if err := svc.Start(); err != nil {
		output.Error(fmt.Sprintf("Failed to start: %v", err))
		return
	}

	output.Success("Started")
	output.Dimmed(fmt.Sprintf("  Port: %d", svc.Port()))

	// Show additional info
	for key, value := range svc.StatusInfo() {
		output.Dimmed(fmt.Sprintf("  %s: %s", key, value))
	}
}

func stopService(name string) {
	svc := svc.Get(name)
	if svc == nil {
		output.Error(fmt.Sprintf("Unknown service: %s", name))
		return
	}

	fmt.Printf("\n%s %s\n", output.Purple.Sprint("==>"), svc.DisplayName())

	status := svc.Status()
	if !status.Running {
		output.Dimmed("Not running")
		return
	}

	if err := svc.Stop(); err != nil {
		output.Error(fmt.Sprintf("Failed to stop: %v", err))
	} else {
		output.Success("Stopped")
	}
}

func showServiceStatus(name string) {
	svc := svc.Get(name)
	if svc == nil {
		output.Error(fmt.Sprintf("Unknown service: %s", name))
		return
	}

	fmt.Printf("\n%s %s\n", output.Purple.Sprint("==>"), svc.DisplayName())

	status := svc.Status()
	if status.Running {
		output.Green.Printf("  ● Running")
		fmt.Printf(" (PID: %d)\n", status.PID)
		output.Dimmed(fmt.Sprintf("    Port: %d", svc.Port()))

		// Show additional info
		for key, value := range svc.StatusInfo() {
			output.Dimmed(fmt.Sprintf("    %s: %s", key, value))
		}
	} else {
		output.DimC.Println("  ○ Stopped")
	}
}

// showServiceLogs shells out to `tail` rather than reading the log file
// in-process. This is intentional: tail handles --follow (-f) with proper
// signal propagation and avoids buffering issues with long-lived streams.
func showServiceLogs(name string, follow bool, lines int) {
	svc := svc.Get(name)
	if svc == nil {
		output.Error(fmt.Sprintf("Unknown service: %s", name))
		return
	}

	logFile := svc.LogFile()
	if _, err := os.Stat(logFile); os.IsNotExist(err) {
		output.Warning("No log file found")
		return
	}

	args := []string{"-n", strconv.Itoa(lines)}
	if follow {
		args = append(args, "-f")
	}
	args = append(args, logFile)

	cmd := exec.Command("tail", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()
}

// GetServiceStatus returns the status of a service (exported for TUI layer).
func GetServiceStatus(name string) (bool, int) {
	svc := svc.Get(name)
	if svc == nil {
		return false, 0
	}
	status := svc.Status()
	return status.Running, status.PID
}

// StartServiceByName starts a service by name (exported for TUI layer).
func StartServiceByName(name string) error {
	svc := svc.Get(name)
	if svc == nil {
		return fmt.Errorf("unknown service: %s", name)
	}
	return svc.Start()
}

// GetServicesBaseDir returns the current services base directory
// This is project-local by default (.stack/state/services/)
func GetServicesBaseDir() string {
	return svc.BaseDir
}
