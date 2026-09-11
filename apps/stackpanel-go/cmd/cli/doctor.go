// doctor.go implements `stack doctor`: the read-only half of the reconciler.
//
// Diagnose everything, print the report, exit. It never prompts and never
// writes. Think `terraform plan`: the same report `stack setup` shows before
// asking to apply.
package cmd

import (
	"context"
	"fmt"
	"path/filepath"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/spf13/cobra"
)

var (
	doctorSetupSession string
	doctorJSON         bool
	doctorOnly         []string
	doctorSkip         []string
	doctorBuild        bool
	doctorStrict       bool
	doctorScope        []string
	doctorExpectations string
)

var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Report drift, failing checks and pending offers without changing anything",
	Long: `Diagnose the project and print a report. Nothing is written.

The report has one section per reconciler:
  codegen   host-side generated artifacts (env payloads, manifests)
  files     generated files that drifted from their declared content
  fileops   adopted files, managed blocks and path-owned JSON/YAML/TOML keys
  checks    stackpanel.doctor checks (runtime and repo scope; --build for build scope)
  addons    adoption offers you have not decided on yet

Run inside the devshell for the full report; outside it only the checks that
do not need the evaluated config can run.

Exit status is 1 when any error-severity finding is present (a critical check
failed, a file could not be adopted, a reconciler could not diagnose), and 0
otherwise, even with pending changes. Pending changes are applied by
'stack setup'. Strict mode also fails on pending changes, unavailable inputs,
and checks that did not pass. --expectations implies strict mode and verifies
a frozen onboarding contract against a fresh, locked, pure Nix evaluation.

Examples:
  stack doctor                  # full report
  stack doctor --json           # machine-readable report
  stack doctor --only files     # just generated-file drift
  stack doctor --skip checks    # everything but the checks
  stack doctor --build          # also realize build-scope checks with nix
  stack doctor --strict --scope repo,build --build --json`,
	RunE: runDoctor,
}

func init() {
	doctorCmd.Flags().StringVar(&doctorSetupSession, "setup-session", "", "Verify runtime readiness for this setup session (implies strict)")
	doctorCmd.Flags().BoolVar(&doctorJSON, "json", false, "Print the report as JSON")
	doctorCmd.Flags().
		StringSliceVar(&doctorOnly, "only", nil, "Run only these reconcilers (repeatable)")
	doctorCmd.Flags().
		StringSliceVar(&doctorSkip, "skip", nil, "Skip these reconcilers (repeatable)")
	doctorCmd.Flags().
		BoolVar(&doctorBuild, "build", false, "Realize build-scope doctor checks with nix build")
	doctorCmd.Flags().BoolVar(&doctorStrict, "strict", false, "Fail on drift, incomplete verification, or any selected check that did not pass")
	doctorCmd.Flags().StringSliceVar(&doctorScope, "scope", nil, "Run checks in these scopes: repo, runtime, build (default: all)")
	doctorCmd.Flags().StringVar(&doctorExpectations, "expectations", "", "Verify a frozen onboarding expectations JSON file (implies --strict)")
	rootCmd.AddCommand(doctorCmd)
}

type doctorOptions struct {
	SetupSession     string
	Only             []string
	Skip             []string
	Scopes           []string
	Build            bool
	Strict           bool
	Verbose          bool
	ExpectationsPath string
}

func doctorRegistry(opts doctorOptions) *reconcile.Registry {
	registry := reconcile.NewRegistry(
		&reconcile.CodegenReconciler{},
		&reconcile.FilesReconciler{},
		&reconcile.FileopsReconciler{},
		&reconcile.ChecksReconciler{Scopes: opts.Scopes},
		&reconcile.AddonsReconciler{},
	)
	if opts.SetupSession != "" {
		registry.Add(&reconcile.RuntimeReconciler{SessionID: opts.SetupSession})
	}
	return registry
}

func collectDoctorReport(ctx context.Context, root string, opts doctorOptions) (*reconcile.Report, error) {
	if opts.SetupSession != "" {
		opts.Strict = true
		if len(opts.Scopes) > 0 {
			found := false
			for _, scope := range opts.Scopes {
				if scope == "runtime" {
					found = true
				}
			}
			if !found {
				return nil, fmt.Errorf("--setup-session requires runtime scope")
			}
		}
	}
	for _, scope := range opts.Scopes {
		switch scope {
		case "repo", "runtime", "build":
		default:
			return nil, fmt.Errorf("unknown doctor scope %q (expected repo, runtime, or build)", scope)
		}
	}
	registry, err := doctorRegistry(opts).Select(opts.Only, opts.Skip)
	if err != nil {
		return nil, err
	}
	if opts.SetupSession != "" {
		if _, ok := registry.Lookup("runtime"); !ok {
			return nil, fmt.Errorf("--setup-session requires runtime reconciler")
		}
	}
	var expected reconcile.Expectations
	if opts.ExpectationsPath != "" {
		expected, err = reconcile.LoadExpectations(opts.ExpectationsPath)
		if err != nil {
			return nil, err
		}
		opts.Strict = true
		for _, id := range []string{"codegen", "files", "fileops", "checks"} {
			if _, selected := registry.Lookup(id); !selected {
				return nil, fmt.Errorf("--expectations requires the %s reconciler; remove the conflicting --only/--skip filter", id)
			}
		}
	}
	runCtx, err := reconcile.NewContext(ctx, root)
	if err != nil {
		return nil, err
	}
	runCtx.Verbose = opts.Verbose
	runCtx.Build = opts.Build
	runCtx.CheckScopes = opts.Scopes
	report := registry.Diagnose(runCtx)
	runCtx.CheckResults = report.CheckResults
	if opts.Strict {
		report.Reconcilers = append(report.Reconcilers, "verification")
		report.Coverage = append(report.Coverage, reconcile.Coverage{Reconciler: "verification", Status: "complete"})
		var configErr error
		switch {
		case runCtx.ConfigError != nil:
			configErr = runCtx.ConfigError
		case runCtx.Config == nil:
			configErr = fmt.Errorf("evaluated configuration is missing")
		case runCtx.Config.Version < 1 || runCtx.Config.ProjectName == "" || runCtx.Config.ProjectRoot == "":
			configErr = fmt.Errorf("evaluated configuration is missing its version, project name, or root")
		case filepath.Clean(runCtx.Config.ProjectRoot) != filepath.Clean(runCtx.ProjectRoot):
			configErr = fmt.Errorf("evaluated configuration belongs to %s, not %s", runCtx.Config.ProjectRoot, runCtx.ProjectRoot)
		}
		if configErr != nil {
			report.Findings = append(report.Findings, reconcile.Finding{Reconciler: "verification", ID: "config", Severity: reconcile.SeverityError, Title: "evaluated configuration unavailable or invalid", Detail: configErr.Error()})
		}
	}
	if opts.ExpectationsPath != "" {
		report.Findings = append(report.Findings, reconcile.CheckExpectations(runCtx, expected)...)
		report.CheckResults = append(report.CheckResults, reconcile.CheckAcceptance(runCtx, expected)...)
	}
	if opts.Strict {
		report.EnforceStrict()
	}
	return report, nil
}

func runDoctor(cmd *cobra.Command, args []string) error {
	projectRoot, err := resolvePreflightProjectRoot("")
	if err != nil {
		return fmt.Errorf("not inside a stackpanel project: %w (run 'stack setup' to create one)", err)
	}
	verbose, _ := cmd.Flags().GetBool("verbose")
	report, err := collectDoctorReport(cmd.Context(), projectRoot, doctorOptions{
		SetupSession: doctorSetupSession, Only: doctorOnly, Skip: doctorSkip, Scopes: doctorScope, Build: doctorBuild,
		Strict: doctorStrict, Verbose: verbose, ExpectationsPath: doctorExpectations,
	})
	if err != nil {
		return err
	}
	if doctorJSON {
		data, err := report.JSON()
		if err != nil {
			return err
		}
		if _, err := cmd.OutOrStdout().Write(data); err != nil {
			return err
		}
	} else {
		report.Render(cmd.ErrOrStderr(), reconcile.RenderOptions{
			Title:    fmt.Sprintf("stack doctor · %s", projectRoot),
			Verbose:  verbose,
			NextStep: "Run 'stack setup' to apply pending changes.",
		})
	}
	if report.HasErrors() {
		return fmt.Errorf("doctor found errors; see the report above")
	}
	return nil
}
