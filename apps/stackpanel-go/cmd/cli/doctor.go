// doctor.go implements `stack doctor`: the read-only half of the reconciler.
//
// Diagnose everything, print the report, exit. It never prompts and never
// writes. Think `terraform plan`: the same report `stack setup` shows before
// asking to apply.
package cmd

import (
	"fmt"
	"os"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/spf13/cobra"
)

var (
	doctorJSON  bool
	doctorOnly  []string
	doctorSkip  []string
	doctorBuild bool
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
'stack setup'.

Examples:
  stack doctor                  # full report
  stack doctor --json           # machine-readable report
  stack doctor --only files     # just generated-file drift
  stack doctor --skip checks    # everything but the checks
  stack doctor --build          # also realize build-scope checks with nix`,
	RunE: runDoctor,
}

func init() {
	doctorCmd.Flags().BoolVar(&doctorJSON, "json", false, "Print the report as JSON")
	doctorCmd.Flags().
		StringSliceVar(&doctorOnly, "only", nil, "Run only these reconcilers (repeatable)")
	doctorCmd.Flags().
		StringSliceVar(&doctorSkip, "skip", nil, "Skip these reconcilers (repeatable)")
	doctorCmd.Flags().
		BoolVar(&doctorBuild, "build", false, "Realize build-scope doctor checks with nix build")
	rootCmd.AddCommand(doctorCmd)
}

// doctorRegistry is the read-only registry both commands share.
func doctorRegistry() *reconcile.Registry {
	return reconcile.NewRegistry(
		&reconcile.CodegenReconciler{},
		&reconcile.FilesReconciler{},
		&reconcile.FileopsReconciler{},
		&reconcile.ChecksReconciler{},
		&reconcile.AddonsReconciler{},
	)
}

func runDoctor(cmd *cobra.Command, args []string) error {
	projectRoot, err := resolvePreflightProjectRoot("")
	if err != nil {
		return fmt.Errorf(
			"not inside a stackpanel project: %w (run 'stack setup' to create one)",
			err,
		)
	}
	verbose, _ := cmd.Flags().GetBool("verbose")

	ctx, err := reconcile.NewContext(cmd.Context(), projectRoot)
	if err != nil {
		return err
	}
	ctx.Verbose = verbose
	ctx.Build = doctorBuild

	registry, err := doctorRegistry().Select(doctorOnly, doctorSkip)
	if err != nil {
		return err
	}

	report := registry.Diagnose(ctx)

	if doctorJSON {
		data, err := report.JSON()
		if err != nil {
			return err
		}
		if _, err := cmd.OutOrStdout().Write(data); err != nil {
			return err
		}
	} else {
		report.Render(os.Stderr, reconcile.RenderOptions{
			Title:    fmt.Sprintf("stack doctor · %s", projectRoot),
			Verbose:  verbose,
			NextStep: "Run 'stack setup' to apply pending changes.",
		})
		if !ctx.InDevshell() {
			fmt.Fprintln(
				os.Stderr,
				"Not inside the devshell: codegen, files, fileops and checks were skipped. Run 'direnv allow' or 'nix develop' first.",
			)
		}
	}

	if report.HasErrors() {
		os.Exit(1)
	}
	return nil
}
