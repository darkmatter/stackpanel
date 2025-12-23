package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"

	"github.com/darkmatter/stackpanel/cli/internal/services"
	"github.com/darkmatter/stackpanel/cli/internal/tui"
	"github.com/spf13/cobra"
)

var servicesCmd = &cobra.Command{
	Use:     "services",
	Aliases: []string{"svc", "s"},
	Short:   "Manage development services",
	Long: `Manage project-local development services (PostgreSQL, Redis, Minio, etc.)

Services are project-local by default, with data stored in .stackpanel/state/services/
This allows different projects to use different versions and configurations.

Note: Caddy is a global service (shared across projects) to avoid port 443 conflicts.`,
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		// Initialize services for this project
		services.InitForProject("")
	},
}

var servicesStartCmd = &cobra.Command{
	Use:   "start [service...]",
	Short: "Start services (all if none specified)",
	Long: `Start development services.

If no services are specified, starts all configured services.
If a service is already running, it will be reattached.

Examples:
  stackpanel services start           # Start all services
  stackpanel services start postgres  # Start only PostgreSQL
  stackpanel services start pg redis  # Start PostgreSQL and Redis`,
	Run: func(cmd *cobra.Command, args []string) {
		noTui, _ := cmd.Flags().GetBool("no-tui")

		// Get service names to start
		var svcNames []string
		if len(args) == 0 {
			svcNames = services.Names()
		} else {
			for _, arg := range args {
				svcNames = append(svcNames, services.Normalize(arg))
			}
		}

		if noTui {
			// Non-interactive mode
			for _, name := range svcNames {
				startService(name)
			}
		} else {
			// Interactive TUI mode
			if err := tui.RunStartServices(svcNames); err != nil {
				printError(fmt.Sprintf("TUI error: %v", err))
				// Fallback to non-interactive
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
			svcNames = services.Names()
		} else {
			for _, arg := range args {
				svcNames = append(svcNames, services.Normalize(arg))
			}
		}

		// Stop in reverse order
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
			svcNames = services.Names()
		} else {
			for _, arg := range args {
				svcNames = append(svcNames, services.Normalize(arg))
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
			svcNames = services.Names()
		} else {
			for _, arg := range args {
				svcNames = append(svcNames, services.Normalize(arg))
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
	Use:   "logs <service>",
	Short: "Show service logs",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		follow, _ := cmd.Flags().GetBool("follow")
		lines, _ := cmd.Flags().GetInt("lines")
		showServiceLogs(services.Normalize(args[0]), follow, lines)
	},
}

var servicesListCmd = &cobra.Command{
	Use:   "list",
	Short: "List available services",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("Available services:")
		for _, svc := range services.All() {
			status := svc.Status()
			statusIcon := dim.Sprint("○")
			if status.Running {
				statusIcon = green.Sprint("●")
			}
			fmt.Printf("  %s %s (%s)\n", statusIcon, svc.Name(), svc.DisplayName())
		}
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
	svc := services.Get(name)
	if svc == nil {
		printError(fmt.Sprintf("Unknown service: %s", name))
		return
	}

	fmt.Printf("\n%s %s\n", purple.Sprint("==>"), svc.DisplayName())

	// Check if already running
	status := svc.Status()
	if status.Running {
		printSuccess(fmt.Sprintf("Already running (PID: %d)", status.PID))
		printDim(fmt.Sprintf("  Port: %d", svc.Port()))
		return
	}

	printInfo("Starting...")
	if err := svc.Start(); err != nil {
		printError(fmt.Sprintf("Failed to start: %v", err))
		return
	}

	printSuccess("Started")
	printDim(fmt.Sprintf("  Port: %d", svc.Port()))

	// Show additional info
	for key, value := range svc.StatusInfo() {
		printDim(fmt.Sprintf("  %s: %s", key, value))
	}
}

func stopService(name string) {
	svc := services.Get(name)
	if svc == nil {
		printError(fmt.Sprintf("Unknown service: %s", name))
		return
	}

	fmt.Printf("\n%s %s\n", purple.Sprint("==>"), svc.DisplayName())

	status := svc.Status()
	if !status.Running {
		printDim("Not running")
		return
	}

	if err := svc.Stop(); err != nil {
		printError(fmt.Sprintf("Failed to stop: %v", err))
	} else {
		printSuccess("Stopped")
	}
}

func showServiceStatus(name string) {
	svc := services.Get(name)
	if svc == nil {
		printError(fmt.Sprintf("Unknown service: %s", name))
		return
	}

	fmt.Printf("\n%s %s\n", purple.Sprint("==>"), svc.DisplayName())

	status := svc.Status()
	if status.Running {
		green.Printf("  ● Running")
		fmt.Printf(" (PID: %d)\n", status.PID)
		printDim(fmt.Sprintf("    Port: %d", svc.Port()))

		// Show additional info
		for key, value := range svc.StatusInfo() {
			printDim(fmt.Sprintf("    %s: %s", key, value))
		}
	} else {
		dim.Println("  ○ Stopped")
	}
}

func showServiceLogs(name string, follow bool, lines int) {
	svc := services.Get(name)
	if svc == nil {
		printError(fmt.Sprintf("Unknown service: %s", name))
		return
	}

	logFile := svc.LogFile()
	if _, err := os.Stat(logFile); os.IsNotExist(err) {
		printWarning("No log file found")
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

// GetServiceStatus returns the status of a service (used by TUI)
func GetServiceStatus(name string) (bool, int) {
	svc := services.Get(name)
	if svc == nil {
		return false, 0
	}
	status := svc.Status()
	return status.Running, status.PID
}

// StartServiceByName starts a service by name (used by TUI)
func StartServiceByName(name string) error {
	svc := services.Get(name)
	if svc == nil {
		return fmt.Errorf("unknown service: %s", name)
	}
	return svc.Start()
}

// GetServicesBaseDir returns the current services base directory
// This is project-local by default (.stackpanel/state/services/)
func GetServicesBaseDir() string {
	return services.BaseDir
}
