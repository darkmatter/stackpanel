package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	svc "github.com/darkmatter/stackpanel/apps/stackpanel-go/pkg/services"
	"github.com/spf13/cobra"
)

var (
	caddyConfigDir = filepath.Join(os.Getenv("HOME"), ".config", "caddy")
	caddySitesDir  = filepath.Join(caddyConfigDir, "sites.d")
	caddyPidFile   = filepath.Join(caddyConfigDir, "caddy.pid")
)

var caddyCmd = &cobra.Command{
	Use:   "caddy",
	Short: "Manage Caddy reverse proxy",
	Long: `Manage the global Caddy reverse proxy.

Caddy is a GLOBAL service (unlike other services which are project-local).
This avoids port 443 conflicts between projects.

Site configs are stored in ~/.config/caddy/sites.d/ and can be
contributed to by multiple projects.

When you add a site, a symlink is created in your project at:
  .stackpanel/caddy/\<domain\>.caddy -> ~/.config/caddy/sites.d/\<domain\>.caddy

This allows you to:
  - See which sites belong to your project
  - Customize the config and check it into version control
  - Easily find and edit your project's Caddy configuration`,
}

var caddyStartCmd = &cobra.Command{
	Use:   "start",
	Short: "Start or reload Caddy",
	Run: func(cmd *cobra.Command, args []string) {
		startCaddy()
	},
}

var caddyStopCmd = &cobra.Command{
	Use:   "stop",
	Short: "Stop Caddy",
	Run: func(cmd *cobra.Command, args []string) {
		stopCaddy()
	},
}

var caddyStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show Caddy status",
	Run: func(cmd *cobra.Command, args []string) {
		showCaddyStatus()
	},
}

var caddyAddSiteCmd = &cobra.Command{
	Use:   "add [domain] [upstream]",
	Short: "Add a site to Caddy",
	Long: `Add a reverse proxy site to Caddy.

Examples:
  stackpanel caddy add myapp.localhost localhost:3000
  stackpanel caddy add api.localhost localhost:8080 --tls`,
	Args: cobra.ExactArgs(2),
	Run: func(cmd *cobra.Command, args []string) {
		useTls, _ := cmd.Flags().GetBool("tls")
		addCaddySite(args[0], args[1], useTls)
	},
}

var caddyRemoveSiteCmd = &cobra.Command{
	Use:   "remove [domain]",
	Short: "Remove a site from Caddy",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		removeCaddySite(args[0])
	},
}

var caddyListSitesCmd = &cobra.Command{
	Use:   "list",
	Short: "List configured sites",
	Run: func(cmd *cobra.Command, args []string) {
		listCaddySites()
	},
}

func init() {
	caddyCmd.AddCommand(caddyStartCmd)
	caddyCmd.AddCommand(caddyStopCmd)
	caddyCmd.AddCommand(caddyStatusCmd)
	caddyCmd.AddCommand(caddyAddSiteCmd)
	caddyCmd.AddCommand(caddyRemoveSiteCmd)
	caddyCmd.AddCommand(caddyListSitesCmd)

	caddyAddSiteCmd.Flags().Bool("tls", false, "Enable internal TLS")
}

func ensureCaddyDirs() {
	os.MkdirAll(caddyConfigDir, 0755)
	os.MkdirAll(caddySitesDir, 0755)
}

func generateCaddyfile() error {
	ensureCaddyDirs()

	caddyfile := filepath.Join(caddyConfigDir, "Caddyfile")
	content := fmt.Sprintf(`# Generated Caddyfile - imports all sites from sites.d/
# Managed by stackpanel - do not edit directly

{
  # Global options
  admin off
}

# Import all site configurations
import %s/*.caddy
`, caddySitesDir)

	return os.WriteFile(caddyfile, []byte(content), 0644)
}

func startCaddy() {
	fmt.Printf("\n%s Caddy\n", purple.Sprint("==>"))

	if err := generateCaddyfile(); err != nil {
		printError(fmt.Sprintf("Failed to generate Caddyfile: %v", err))
		return
	}

	caddyfile := filepath.Join(caddyConfigDir, "Caddyfile")

	// Check if already running
	if pid := readCaddyPidFile(caddyPidFile); pid > 0 && svc.IsProcessRunning(pid) {
		printInfo("Reloading configuration...")
		cmd := exec.Command("caddy", "reload", "--config", caddyfile, "--force")
		if output, err := cmd.CombinedOutput(); err != nil {
			printError(fmt.Sprintf("Reload failed: %v\n%s", err, output))
			return
		}
		printSuccess("Reloaded")
		return
	}

	printInfo("Starting Caddy...")
	cmd := exec.Command("caddy", "start", "--config", caddyfile, "--pidfile", caddyPidFile)
	if output, err := cmd.CombinedOutput(); err != nil {
		printError(fmt.Sprintf("Start failed: %v\n%s", err, output))
		return
	}

	printSuccess("Started")
}

func stopCaddy() {
	fmt.Printf("\n%s Caddy\n", purple.Sprint("==>"))

	pid := readCaddyPidFile(caddyPidFile)
	if pid == 0 || !svc.IsProcessRunning(pid) {
		printDim("Not running")
		os.Remove(caddyPidFile)
		return
	}

	cmd := exec.Command("caddy", "stop")
	if err := cmd.Run(); err != nil {
		printError(fmt.Sprintf("Stop failed: %v", err))
		return
	}

	os.Remove(caddyPidFile)
	printSuccess("Stopped")
}

func showCaddyStatus() {
	fmt.Printf("\n%s Caddy\n", purple.Sprint("==>"))

	pid := readCaddyPidFile(caddyPidFile)
	if pid > 0 && svc.IsProcessRunning(pid) {
		green.Printf("  ● Running")
		fmt.Printf(" (PID: %d)\n", pid)
	} else {
		dim.Println("  ○ Stopped")
		return
	}

	// List sites
	listCaddySites()
}

func addCaddySite(domain, upstream string, useTls bool) {
	ensureCaddyDirs()

	// Sanitize domain for filename
	filename := strings.ReplaceAll(domain, ".", "_")
	filename = strings.ReplaceAll(filename, ":", "_")
	siteFile := filepath.Join(caddySitesDir, filename+".caddy")

	tlsConfig := ""
	if useTls {
		tlsConfig = "tls internal"
	}

	content := fmt.Sprintf(`# Site: %s -> %s
%s {
  %s
  reverse_proxy %s
}
`, domain, upstream, domain, tlsConfig, upstream)

	if err := os.WriteFile(siteFile, []byte(content), 0644); err != nil {
		printError(fmt.Sprintf("Failed to write site config: %v", err))
		return
	}

	printSuccess(fmt.Sprintf("Added site: %s -> %s", domain, upstream))
	printDim(fmt.Sprintf("  Config: %s", siteFile))

	// Create symlink from project to global config
	projectRoot := svc.GetProjectRoot()
	if projectRoot != "" {
		projectCaddyDir := filepath.Join(projectRoot, ".stackpanel", "caddy")
		if err := os.MkdirAll(projectCaddyDir, 0755); err == nil {
			symlinkPath := filepath.Join(projectCaddyDir, filename+".caddy")
			// Remove existing symlink if it exists
			os.Remove(symlinkPath)
			if err := os.Symlink(siteFile, symlinkPath); err == nil {
				printDim(fmt.Sprintf("  Symlink: %s", symlinkPath))
			}
		}
	}

	printDim("  Run 'stackpanel caddy start' to apply")
}

func removeCaddySite(domain string) {
	filename := strings.ReplaceAll(domain, ".", "_")
	filename = strings.ReplaceAll(filename, ":", "_")
	siteFile := filepath.Join(caddySitesDir, filename+".caddy")

	if _, err := os.Stat(siteFile); os.IsNotExist(err) {
		printWarning(fmt.Sprintf("Site not found: %s", domain))
		return
	}

	if err := os.Remove(siteFile); err != nil {
		printError(fmt.Sprintf("Failed to remove site: %v", err))
		return
	}

	// Also remove symlink from project if it exists
	projectRoot := svc.GetProjectRoot()
	if projectRoot != "" {
		symlinkPath := filepath.Join(projectRoot, ".stackpanel", "caddy", filename+".caddy")
		os.Remove(symlinkPath) // Ignore error - might not exist
	}

	printSuccess(fmt.Sprintf("Removed site: %s", domain))
	printDim("  Run 'stackpanel caddy start' to apply")
}

func listCaddySites() {
	entries, err := os.ReadDir(caddySitesDir)
	if err != nil || len(entries) == 0 {
		printDim("  No sites configured")
		return
	}

	fmt.Println()
	printDim("  Configured sites:")
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".caddy") {
			continue
		}

		data, _ := os.ReadFile(filepath.Join(caddySitesDir, e.Name()))
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "# Site:") {
				parts := strings.TrimPrefix(line, "# Site: ")
				printDim(fmt.Sprintf("    • %s", parts))
				break
			}
		}
	}
	fmt.Println()
}

// readCaddyPidFile reads the PID from a file
func readCaddyPidFile(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	pid, _ := strconv.Atoi(strings.TrimSpace(string(data)))
	return pid
}
