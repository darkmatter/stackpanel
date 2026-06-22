// caddy.go manages the global Caddy reverse proxy.
//
// Unlike other services which are project-local (data in .stack/state/services/),
// Caddy runs as a shared singleton because only one process can bind ports
// 80/443.
//
// Per-site Caddyfile snippets are generated *functionally* by Nix
// (stackpanel.files.entries) into each project's .stack/gen/caddy/ directory on
// devshell entry — this is deterministic. This CLI never writes or deletes
// those files. Instead, `stackpanel caddy add` links a project's generated
// snippets into the shared ~/.config/caddy/sites.d/, and
// `stackpanel caddy remove` unlinks them. The shared Caddyfile glob-imports
// sites.d/, so linking a project's snippet is all that's needed to serve it.

package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	svc "github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
	"github.com/spf13/cobra"
)

// Caddy config lives under ~/.config/caddy/ (not per-project) because Caddy
// is a global service — only one process can bind to ports 80/443.
//
// The shared sites.d/ directory holds symlinks into each project's generated
// .stack/gen/caddy/ snippets (created by `stackpanel caddy add`).
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

Per-site configs are generated functionally by Nix into your project at:
  .stack/gen/caddy/<domain>.caddy

This generation is deterministic — it happens on devshell entry from your
stackpanel.apps.<app>.domain (and caddy site) configuration. The CLI does not
write these files.

'stackpanel caddy add' links your project's generated snippets into the shared
~/.config/caddy/sites.d/ so the global Caddy instance serves them:
  ~/.config/caddy/sites.d/<project>__<domain>.caddy -> .stack/gen/caddy/<domain>.caddy

'stackpanel caddy remove' unlinks them again. Neither command generates or
deletes the .stack/gen/caddy/ files themselves.`,
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
	Use:   "add [domain]",
	Short: "Link this project's generated Caddy site(s) into the global proxy",
	Long: `Link this project's generated Caddy site config(s) into the global Caddy.

Per-site Caddyfile snippets are generated functionally by Nix into
.stack/gen/caddy/ on devshell entry (from your stackpanel.apps.<app>.domain and
caddy site configuration). This command does NOT generate config — it only
creates symlinks from the shared ~/.config/caddy/sites.d/ to the generated
files so the global Caddy instance serves them.

With no argument, links all of the project's generated sites and prunes any
stale links left behind by sites that have since been removed from config.
Pass a domain to link a single site.

Examples:
  stackpanel caddy add
  stackpanel caddy add web.myapp.localhost`,
	Args: cobra.MaximumNArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		domain := ""
		if len(args) == 1 {
			domain = args[0]
		}
		linkCaddySites(domain)
	},
}

var caddyRemoveSiteCmd = &cobra.Command{
	Use:   "remove [domain]",
	Short: "Unlink this project's Caddy site(s) from the global proxy",
	Long: `Unlink this project's Caddy site config(s) from the global Caddy.

Removes the symlinks in ~/.config/caddy/sites.d/ that point at this project's
generated .stack/gen/caddy/ files. The generated files themselves are left intact
(they are managed by Nix).

With no argument, unlinks all of this project's sites. Pass a domain to unlink
a single site.

Examples:
  stackpanel caddy remove
  stackpanel caddy remove web.myapp.localhost`,
	Args: cobra.MaximumNArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		domain := ""
		if len(args) == 1 {
			domain = args[0]
		}
		unlinkCaddySites(domain)
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
}

func ensureCaddyDirs() {
	os.MkdirAll(caddyConfigDir, 0o755)
	os.MkdirAll(caddySitesDir, 0o755)
}

// projectCaddyDir returns the directory holding this project's generated
// per-site Caddyfile snippets. These files are generated functionally by Nix
// (stackpanel.files.entries); this command only links them, never writes them.
// Returns "" when not inside a project.
func projectCaddyDir() string {
	root := svc.GetProjectRoot()
	if root == "" {
		return ""
	}
	return filepath.Join(root, ".stack", "gen", "caddy")
}

// sanitizeDomain mirrors the Nix caddy lib (sanitizeDomain) so the generated
// .stack/gen/caddy/<stem>.caddy filenames and the names this CLI resolves match.
func sanitizeDomain(domain string) string {
	r := strings.ReplaceAll(domain, ".", "_")
	r = strings.ReplaceAll(r, ":", "_")
	r = strings.ReplaceAll(r, "@", "")
	return r
}

// caddyLinkName derives the shared sites.d/ symlink name for a project-local
// site file. Prefixing with the project directory name keeps multiple
// projects' sites from colliding in the shared directory. Ownership during
// removal is determined by resolving the symlink target, not by this name, so
// the prefix only needs to be stable, not globally unique.
func caddyLinkName(siteFile string) string {
	prefix := sanitizeDomain(filepath.Base(svc.GetProjectRoot()))
	return prefix + "__" + filepath.Base(siteFile)
}

// linkCaddySites symlinks this project's generated .stack/gen/caddy/*.caddy
// snippets into the shared ~/.config/caddy/sites.d/. It never generates or
// edits the snippets. With an empty domain it links every generated site and
// prunes stale links; with a domain it links just that site.
func linkCaddySites(domain string) {
	projDir := projectCaddyDir()
	if projDir == "" {
		output.Error("Not inside a stackpanel project (no .stack/ or .git/ found)")
		return
	}

	ensureCaddyDirs()

	var siteFiles []string
	if domain != "" {
		f := filepath.Join(projDir, sanitizeDomain(domain)+".caddy")
		if _, err := os.Stat(f); err != nil {
			output.Error(fmt.Sprintf("No generated site for %s (looked for %s)", domain, f))
			output.Dimmed("  Sites are generated from your stackpanel config on devshell entry.")
			return
		}
		siteFiles = []string{f}
	} else {
		matches, _ := filepath.Glob(filepath.Join(projDir, "*.caddy"))
		siteFiles = matches
	}

	linked := 0
	for _, sf := range siteFiles {
		target, err := filepath.Abs(sf)
		if err != nil {
			target = sf
		}
		link := filepath.Join(caddySitesDir, caddyLinkName(sf))

		// Replace any existing entry (symlink or stray file) so re-linking is
		// idempotent and picks up moved project paths.
		os.Remove(link)
		if err := os.Symlink(target, link); err != nil {
			output.Error(fmt.Sprintf("Failed to link %s: %v", filepath.Base(sf), err))
			continue
		}
		linked++
		output.Dimmed(fmt.Sprintf("  %s -> %s", link, target))
	}

	// Clean up links for sites that were removed from config (their generated
	// .stack/gen/caddy/ file no longer exists, so the link now dangles).
	pruned := pruneProjectLinks(projDir, false)

	switch {
	case linked > 0:
		output.Success(fmt.Sprintf("Linked %d Caddy site(s)", linked))
		output.Dimmed("  Run 'stackpanel caddy start' to apply")
	case pruned > 0:
		output.Success(fmt.Sprintf("Pruned %d stale Caddy link(s)", pruned))
		output.Dimmed("  Run 'stackpanel caddy start' to apply")
	default:
		output.Dimmed("  No generated Caddy sites to link")
	}
}

// unlinkCaddySites removes the shared sites.d/ symlinks that point at this
// project's generated snippets. The generated files are left intact. With an
// empty domain it unlinks every site owned by this project; with a domain it
// unlinks just that one.
func unlinkCaddySites(domain string) {
	projDir := projectCaddyDir()
	if projDir == "" {
		output.Error("Not inside a stackpanel project (no .stack/ or .git/ found)")
		return
	}

	if domain != "" {
		sf := filepath.Join(projDir, sanitizeDomain(domain)+".caddy")
		link := filepath.Join(caddySitesDir, caddyLinkName(sf))
		if _, err := os.Lstat(link); err != nil {
			output.Warning(fmt.Sprintf("Site not linked: %s", domain))
			return
		}
		if err := os.Remove(link); err != nil {
			output.Error(fmt.Sprintf("Failed to unlink site: %v", err))
			return
		}
		output.Success(fmt.Sprintf("Unlinked site: %s", domain))
		output.Dimmed("  Run 'stackpanel caddy start' to apply")
		return
	}

	removed := pruneProjectLinks(projDir, true)
	if removed == 0 {
		output.Dimmed("  No linked sites for this project")
		return
	}
	output.Success(fmt.Sprintf("Unlinked %d site(s)", removed))
	output.Dimmed("  Run 'stackpanel caddy start' to apply")
}

// pruneProjectLinks removes symlinks in sites.d/ that this project owns
// (i.e. whose target resolves inside the project's .stack/gen/caddy/ directory).
//
// When all is true, every owned link is removed. When all is false, only links
// whose target no longer exists (stale) are removed. Returns the number of
// links removed.
func pruneProjectLinks(projDir string, all bool) int {
	projAbs, err := filepath.Abs(projDir)
	if err != nil {
		return 0
	}
	prefix := projAbs + string(os.PathSeparator)

	entries, err := os.ReadDir(caddySitesDir)
	if err != nil {
		return 0
	}

	removed := 0
	for _, e := range entries {
		p := filepath.Join(caddySitesDir, e.Name())
		fi, err := os.Lstat(p)
		if err != nil || fi.Mode()&os.ModeSymlink == 0 {
			continue
		}

		target, err := os.Readlink(p)
		if err != nil {
			continue
		}
		if !filepath.IsAbs(target) {
			target = filepath.Join(caddySitesDir, target)
		}
		target = filepath.Clean(target)

		// Only touch links this project owns.
		if !strings.HasPrefix(target, prefix) {
			continue
		}

		if !all {
			// Stale only: keep links whose target still exists.
			if _, err := os.Stat(target); err == nil {
				continue
			}
		}

		if err := os.Remove(p); err == nil {
			removed++
		}
	}
	return removed
}

// startCaddy is idempotent: if Caddy is already running it reloads the config
// instead of starting a second instance. This makes it safe to call from
// shell hooks on every devshell entry without accumulating zombie processes.
func startCaddy() {
	fmt.Printf("\n%s Caddy\n", output.Purple.Sprint("==>"))

	if err := generateCaddyfile(); err != nil {
		output.Error(fmt.Sprintf("Failed to generate Caddyfile: %v", err))
		return
	}

	caddyfile := filepath.Join(caddyConfigDir, "Caddyfile")

	// Check if already running
	if pid := readCaddyPidFile(caddyPidFile); pid > 0 && svc.IsProcessRunning(pid) {
		output.Info("Reloading configuration...")
		cmd := exec.Command("caddy", "reload", "--config", caddyfile, "--force")
		if cmdOutput, err := cmd.CombinedOutput(); err != nil {
			output.Error(fmt.Sprintf("Reload failed: %v\n%s", err, cmdOutput))
			return
		}
		output.Success("Reloaded")
		return
	}

	output.Info("Starting Caddy...")
	cmd := exec.Command(
		"caddy",
		"start",
		"--config",
		caddyfile,
		"--pidfile",
		caddyPidFile,
	)
	if cmdOutput, err := cmd.CombinedOutput(); err != nil {
		output.Error(fmt.Sprintf("Start failed: %v\n%s", err, cmdOutput))
		return
	}

	output.Success("Started")
}

func stopCaddy() {
	fmt.Printf("\n%s Caddy\n", output.Purple.Sprint("==>"))

	pid := readCaddyPidFile(caddyPidFile)
	if pid == 0 || !svc.IsProcessRunning(pid) {
		output.Dimmed("Not running")
		os.Remove(caddyPidFile)
		return
	}

	cmd := exec.Command("caddy", "stop")
	if err := cmd.Run(); err != nil {
		output.Error(fmt.Sprintf("Stop failed: %v", err))
		return
	}

	os.Remove(caddyPidFile)
	output.Success("Stopped")
}

func showCaddyStatus() {
	fmt.Printf("\n%s Caddy\n", output.Purple.Sprint("==>"))

	pid := readCaddyPidFile(caddyPidFile)
	if pid > 0 && svc.IsProcessRunning(pid) {
		output.Green.Printf("  ● Running")
		fmt.Printf(" (PID: %d)\n", pid)
	} else {
		output.DimC.Println("  ○ Stopped")
		return
	}

	// List sites
	listCaddySites()
}

// generateCaddyfile writes a root Caddyfile that glob-imports all per-site
// configs from sites.d/. This pattern lets multiple projects register
// sites independently without coordination — linking/unlinking a snippet is
// enough. Caddy follows the symlinks placed in sites.d/.
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

	return os.WriteFile(caddyfile, []byte(content), 0o644)
}

func listCaddySites() {
	entries, err := os.ReadDir(caddySitesDir)
	if err != nil || len(entries) == 0 {
		output.Dimmed("  No sites configured")
		return
	}

	fmt.Println()
	output.Dimmed("  Configured sites:")
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".caddy") {
			continue
		}

		full := filepath.Join(caddySitesDir, e.Name())

		// A dangling symlink (target removed) shows up but can't be read.
		if _, err := os.Stat(full); err != nil {
			output.Dimmed(fmt.Sprintf("    • (dangling) %s", e.Name()))
			continue
		}

		data, _ := os.ReadFile(full)
		domain := ""
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "# Site:") {
				domain = strings.TrimPrefix(line, "# Site: ")
				break
			}
		}
		if domain == "" {
			domain = e.Name()
		}
		output.Dimmed(fmt.Sprintf("    • %s (filename = %s)", domain, e.Name()))
	}
	fmt.Println()
}

// readCaddyPidFile reads a PID from the given file path. Returns 0 if the
// file doesn't exist or contains garbage — callers should treat 0 as "not running".
func readCaddyPidFile(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	pid, _ := strconv.Atoi(strings.TrimSpace(string(data)))
	return pid
}
