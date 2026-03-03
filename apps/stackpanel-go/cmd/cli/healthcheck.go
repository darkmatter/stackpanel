package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/spf13/cobra"
)

var (
	healthcheckForce  bool
	healthcheckModule string
	healthcheckJSON   bool
)

var healthcheckCmd = &cobra.Command{
	Use:   "healthcheck",
	Short: "Run project healthchecks",
	Long: `Run healthchecks for the current project.

By default only checks that have failed, errored, or have never been run
are re-executed. Checks that already have a passing result are skipped.

Use --force to re-run all checks regardless of their cached status.

Examples:
  stackpanel healthcheck              # Run failed/unknown checks
  stackpanel healthcheck --force      # Re-run all checks
  stackpanel healthcheck --module go  # Only checks for the "go" module`,
	Aliases: []string{"hc", "health"},
	RunE:    runHealthcheck,
}

func init() {
	healthcheckCmd.Flags().BoolVar(&healthcheckForce, "force", false, "Re-run all checks, even passing ones")
	healthcheckCmd.Flags().StringVar(&healthcheckModule, "module", "", "Only run checks for a specific module")
	healthcheckCmd.Flags().BoolVar(&healthcheckJSON, "json", false, "Output results as JSON")
	rootCmd.AddCommand(healthcheckCmd)
}

func runHealthcheck(cmd *cobra.Command, args []string) error {
	// Load config from Nix
	cfg, err := nixconfig.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w (are you in a stackpanel devshell?)", err)
	}

	if len(cfg.Healthchecks) == 0 {
		output.Info("No healthchecks configured")
		return nil
	}

	// Resolve state directory
	stateDir := cfg.Paths.State
	if stateDir == "" {
		stateDir = ".stack/profile"
	}
	if cfg.ProjectRoot != "" && !filepath.IsAbs(stateDir) {
		stateDir = filepath.Join(cfg.ProjectRoot, stateDir)
	}

	// Filter checks by module if requested
	checks := cfg.Healthchecks
	if healthcheckModule != "" {
		var filtered []nixconfig.Healthcheck
		for _, c := range checks {
			if c.Module == healthcheckModule {
				filtered = append(filtered, c)
			}
		}
		if len(filtered) == 0 {
			return fmt.Errorf("no healthchecks found for module %q", healthcheckModule)
		}
		checks = filtered
	}

	// Count enabled checks
	enabledCount := 0
	for _, c := range checks {
		if c.Enabled {
			enabledCount++
		}
	}
	if enabledCount == 0 {
		output.Info("All healthchecks are disabled")
		return nil
	}

	// Run checks
	var results []tui.HealthcheckResult

	if healthcheckForce {
		fmt.Fprintf(os.Stderr, "Running all %d healthcheck(s)...\n", enabledCount)
		results = tui.RunHealthchecks(checks)
		_ = tui.SaveHealthcheckCache(stateDir, results)
	} else {
		// Only re-run failed/unknown checks; keep passing ones from cache
		cache := tui.LoadHealthcheckResults(stateDir)
		cachedPassCount := 0
		if cache != nil {
			for _, r := range cache.Results {
				if r.Status == "pass" {
					cachedPassCount++
				}
			}
		}

		toRunCount := enabledCount - cachedPassCount
		if toRunCount < 0 {
			toRunCount = 0
		}

		if toRunCount == 0 && cachedPassCount > 0 {
			age := time.Duration(0)
			if cache != nil {
				age = time.Since(cache.Timestamp)
			}
			fmt.Fprintf(os.Stderr, "All %d check(s) already passing", cachedPassCount)
			if age > 0 {
				fmt.Fprintf(os.Stderr, " (last run %s ago)", formatHealthcheckElapsed(age))
			}
			fmt.Fprintln(os.Stderr, ". Use --force to re-run.")
			results = cache.Results
		} else {
			if cachedPassCount > 0 {
				fmt.Fprintf(os.Stderr, "Re-running %d failed/unknown check(s), keeping %d cached pass(es)...\n", toRunCount, cachedPassCount)
			} else {
				fmt.Fprintf(os.Stderr, "Running %d healthcheck(s)...\n", enabledCount)
			}
			results = tui.RunFailedHealthchecks(stateDir, checks)
		}
	}

	// JSON output
	if healthcheckJSON {
		jsonData, err := json.MarshalIndent(results, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal results: %w", err)
		}
		fmt.Println(string(jsonData))
		return nil
	}

	// Pretty-print results
	printHealthcheckResults(results)

	// Exit with non-zero if any checks failed
	for _, r := range results {
		if r.Status == "fail" || r.Status == "error" {
			os.Exit(1)
		}
	}

	return nil
}

func printHealthcheckResults(results []tui.HealthcheckResult) {
	if len(results) == 0 {
		output.Info("No results")
		return
	}

	// Group by module
	modules := tui.AggregateByModule(results)

	fmt.Fprintln(os.Stderr)
	for _, m := range modules {
		// Module header
		var icon string
		if m.FailingCount == 0 {
			icon = output.Green.Sprint("●")
		} else if m.Severity == "HEALTHCHECK_SEVERITY_CRITICAL" {
			icon = output.Red.Sprint("●")
		} else {
			icon = output.Yellow.Sprint("●")
		}
		fmt.Fprintf(os.Stderr, "%s %s  %s\n", icon, output.Purple.Sprint(m.Module), output.DimC.Sprintf("%d/%d passing", m.PassingCount, m.TotalChecks))
	}

	// Individual check details (show failures)
	fmt.Fprintln(os.Stderr)
	hasFailed := false
	for _, r := range results {
		if r.Status == "fail" || r.Status == "error" {
			if !hasFailed {
				fmt.Fprintf(os.Stderr, "%s Failed checks:\n", output.Red.Sprint("✗"))
				hasFailed = true
			}
			fmt.Fprintf(os.Stderr, "  %s %s (%s) [%dms]\n",
				output.Red.Sprint("✗"),
				r.Name,
				output.DimC.Sprint(r.Module),
				r.DurationMs,
			)
			if r.Message != "" {
				msg := r.Message
				if len(msg) > 200 {
					msg = msg[:200] + "..."
				}
				for _, line := range strings.Split(msg, "\n") {
					fmt.Fprintf(os.Stderr, "    %s\n", output.DimC.Sprint(line))
				}
			}
		}
	}

	// Summary line
	fmt.Fprintln(os.Stderr)
	summary := tui.HealthSummaryFromResults(results)
	if summary.FailingCount == 0 {
		output.Success(fmt.Sprintf("All %d check(s) passing", summary.PassingCount))
	} else {
		output.Warning(fmt.Sprintf("%d/%d check(s) failing", summary.FailingCount, summary.TotalChecks))
	}
}

func formatHealthcheckElapsed(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds", int(d.Seconds()))
	}
	if d < time.Hour {
		return fmt.Sprintf("%dm", int(d.Minutes()))
	}
	if d < 24*time.Hour {
		hours := int(d.Hours())
		mins := int(d.Minutes()) % 60
		if mins > 0 {
			return fmt.Sprintf("%dh%dm", hours, mins)
		}
		return fmt.Sprintf("%dh", hours)
	}
	days := int(d.Hours() / 24)
	return fmt.Sprintf("%dd", days)
}
