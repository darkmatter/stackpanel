// setup.go implements `stack setup`: the write half of the reconciler.
//
// Same report as `stack doctor`, then a two-phase flow:
//  1. addon selection from metadata alone (cheap), then ONE speculative
//     evaluation with every accepted config mutation overlaid, rendered as
//     the file plan adopting would produce;
//  2. confirm, write the config mutations, then reconcile files.
//
// On a directory that is not a stackpanel project yet, setup scaffolds it
// first (the former `stackpanel init`), so initializing and reconciling from
// empty are the same command.
package cmd

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/fileops"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	executor "github.com/darkmatter/stackpanel/stackpanel-go/pkg/exec"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/spf13/cobra"
)

// Default flake reference for stackpanel.
// Users can override with --flake flag or STACKPANEL_FLAKE env var.
const defaultStackpanelFlake = "github:darkmatter/stackpanel"

type setupFlags struct {
	yes            bool
	json           bool
	dryRun         bool
	only           []string
	skip           []string
	reconsider     bool
	force          bool
	flake          string
	template       string
	tmp            bool
	nonInteractive bool
	with           []string
	without        []string
	addonValues    []string
	build          bool
}

var setupOpts setupFlags

var setupCmd = &cobra.Command{
	Use:   "setup",
	Short: "Reconcile the project: report, confirm, apply",
	Long: `Show the same report as 'stack doctor', decide pending adoption offers,
preview what adopting them generates, then apply everything after confirming.

On a directory that is not a stackpanel project yet, setup first writes the
scaffolding (flake.nix, .envrc, .stack/) from the stackpanel flake's
lib.initTemplates.<template> - the same file set 'nix flake init -t' copies -
and registers the project with the agent. Existing files are left alone
unless --force.

Adoption offers ("you could turn X on") are answered once and recorded in
.stack/reconcile.json keyed on the author's revision. Declining means "not
now", never "never": a bumped revision re-offers, --reconsider re-offers
everything you declined.

Adoption is one-way: accepting writes a config mutation into .stack/config.nix,
and the module's files materialize through ordinary reconciliation. Undoing it
is a user edit of config.nix.

Examples:
  stack setup                                 # interactive
  stack setup --yes                           # take every default, no prompts
  stack setup --json                          # print the plan, apply nothing
  stack setup --only files                    # reconcile generated files only
  stack setup --with playwright               # accept an offer without prompting
  stack setup --without editorconfig          # decline an offer without prompting
  stack setup --addon deploy=fly              # answer a select offer explicitly
  stack setup --reconsider                    # re-offer declined addons
  stack setup --flake path:/path/to/sp        # scaffold from a local checkout
  stack setup --tmp                           # scaffold into a temporary git repo`,
	RunE: runSetup,
}

func init() {
	f := setupCmd.Flags()
	f.BoolVarP(
		&setupOpts.yes,
		"yes",
		"y",
		false,
		"Skip confirmation and take every default answer",
	)
	f.BoolVar(
		&setupOpts.json,
		"json",
		false,
		"Print the plan as JSON and exit without applying",
	)
	f.BoolVar(
		&setupOpts.dryRun,
		"dry-run",
		false,
		"Show the report and exit without applying",
	)
	f.StringSliceVar(
		&setupOpts.only,
		"only",
		nil,
		"Run only these reconcilers (repeatable)",
	)
	f.StringSliceVar(&setupOpts.skip, "skip", nil, "Skip these reconcilers (repeatable)")
	f.BoolVar(
		&setupOpts.reconsider,
		"reconsider",
		false,
		"Re-offer addons that were declined at their current revision",
	)
	f.BoolVar(
		&setupOpts.force,
		"force",
		false,
		"Overwrite existing scaffolding files and rewrite generated files",
	)
	f.StringVar(
		&setupOpts.flake,
		"flake",
		"",
		"Stackpanel flake reference used for scaffolding (default: github:darkmatter/stackpanel)",
	)
	f.StringVar(&setupOpts.template, "template", "default", "Scaffolding template name")
	f.BoolVar(
		&setupOpts.tmp,
		"tmp",
		false,
		"Create the project in a temporary git repository and print its path",
	)
	f.BoolVar(
		&setupOpts.nonInteractive,
		"non-interactive",
		false,
		"Never prompt (same as --yes)",
	)
	f.StringSliceVar(
		&setupOpts.with,
		"with",
		nil,
		"Accept an addon by id without prompting (repeatable)",
	)
	f.StringSliceVar(
		&setupOpts.without,
		"without",
		nil,
		"Decline an addon by id without prompting (repeatable)",
	)
	f.StringSliceVar(
		&setupOpts.addonValues,
		"addon",
		nil,
		"Answer an addon explicitly as id=value (true/false, a choice value, or comma-separated values)",
	)
	f.BoolVar(
		&setupOpts.build,
		"build",
		false,
		"Also realize build-scope doctor checks with nix build",
	)
	rootCmd.AddCommand(setupCmd)
}

func runSetup(cmd *cobra.Command, args []string) error {
	return runSetupWith(cmd, setupOpts)
}

// runSetupWith is the body of `stack setup`, parameterized by flags so tests
// can drive it.
func runSetupWith(cmd *cobra.Command, opts setupFlags) error {
	verbose, _ := cmd.Flags().GetBool("verbose")
	interactive := !opts.yes && !opts.nonInteractive && !opts.json && !opts.dryRun &&
		tui.IsInteractiveStdio()
	takeDefaults := opts.yes || opts.nonInteractive || !tui.IsInteractiveStdio()

	targetDir, err := setupTargetDir(cmd.Context(), opts.tmp, opts.dryRun || opts.json)
	if err != nil {
		return err
	}
	flakeRef := resolveFlakeRef(opts.flake)

	ctx, err := reconcile.NewContext(cmd.Context(), targetDir)
	if err != nil {
		return err
	}
	ctx.Verbose = verbose
	ctx.Build = opts.build
	if verbose {
		output.Info(fmt.Sprintf("Target directory: %s", targetDir))
		output.Info(fmt.Sprintf("Using stackpanel flake: %s", flakeRef))
		if !ctx.InDevshell() {
			output.Info(
				"Not inside the devshell: generated files will be reconciled on the next shell entry",
			)
		}
	}

	// ── Phase 1: diagnose ────────────────────────────────────────────────
	scaffold := &reconcile.ScaffoldReconciler{
		FlakeRef: flakeRef,
		Template: opts.template,
		Force:    opts.force,
	}
	addonsRC := &reconcile.AddonsReconciler{Reconsider: opts.reconsider}
	if !ctx.InDevshell() {
		// A fresh repo has no evaluable project config: offers come from the
		// stackpanel flake instead.
		if addons, err := nixeval.GetInitAddonsFromFlake(
			cmd.Context(),
			reconcile.NormalizeFlakeRef(flakeRef),
		); err == nil {
			addonsRC.Addons = addons
		} else if verbose {
			output.Dimmed(fmt.Sprintf("  no addons available: %v", err))
		}
	}

	registry := reconcile.NewRegistry(
		scaffold,
		&reconcile.CodegenReconciler{Force: opts.force},
		&reconcile.FilesReconciler{},
		&reconcile.FileopsReconciler{},
		&reconcile.ChecksReconciler{},
		addonsRC,
		&reconcile.RegisterReconciler{Skip: opts.tmp},
	)
	registry, err = registry.Select(opts.only, opts.skip)
	if err != nil {
		return err
	}

	report := registry.Diagnose(ctx)

	if opts.json {
		data, err := report.JSON()
		if err != nil {
			return err
		}
		_, err = cmd.OutOrStdout().Write(data)
		return err
	}

	report.Render(os.Stderr, reconcile.RenderOptions{
		Title:   fmt.Sprintf("stack setup · %s", targetDir),
		Verbose: verbose,
	})
	if opts.dryRun {
		output.Info("Dry run: nothing applied")
		return nil
	}

	// ── Phase 2: decide offers, then one speculative evaluation ──────────
	var mutations []reconcile.Mutation
	var decisions []offerDecision
	if len(report.Offers) > 0 {
		addons := addonsRC.Addons
		if addons == nil && ctx.Config != nil {
			addons = ctx.Config.Addons
		}
		inputs := reconcile.AnswerInputs{
			With:    opts.with,
			Without: opts.without,
			Values:  opts.addonValues,
		}
		if interactive {
			inputs.Prompt = promptAddon
		}
		decisions, mutations, err = decideOffers(
			report.Offers,
			addons,
			inputs,
			takeDefaults,
		)
		if err != nil {
			return err
		}
	}

	var speculation *reconcile.Speculation
	if len(mutations) > 0 {
		fmt.Fprintln(os.Stderr)
		output.Info("Config mutations to write into .stack/config.nix:")
		for _, line := range reconcile.DescribeMutations(mutations) {
			output.Dimmed("  " + line)
		}
		if hasFlake(targetDir) {
			output.Dimmed("  evaluating what adopting would generate...")
			spec, serr := reconcile.Speculate(
				cmd.Context(),
				targetDir,
				reconcile.Overlay(mutations),
				0,
			)
			if serr != nil {
				output.Warning(
					fmt.Sprintf("speculative preview unavailable: %v", firstLine(serr.Error())),
				)
			} else {
				speculation = spec
				plan := reconcile.DiffPlan(targetDir, ctx.StateDir, "adopt", spec.Files)
				preview := &reconcile.Report{
					Reconcilers: []string{"adopt"},
					Findings:    plan.Findings,
					Changes:     plan.Changes,
				}
				fmt.Fprintln(os.Stderr)
				preview.Render(
					os.Stderr,
					reconcile.RenderOptions{Title: "After adoption", Verbose: verbose},
				)
			}
		}
	}

	nothingToDo := !report.HasChanges() && len(mutations) == 0 && len(decisions) == 0
	if nothingToDo {
		output.Success("Nothing to do: project is up to date")
		return nil
	}

	// ── Confirm ──────────────────────────────────────────────────────────
	if interactive {
		ok, err := tui.Confirm("Apply these changes?", true)
		if err != nil {
			return err
		}
		if !ok {
			// The offers were shown; remember that without applying anything.
			if err := recordDecisions(
				targetDir,
				addonsFor(addonsRC, ctx),
				decisions,
			); err != nil {
				return err
			}
			output.Warning("Aborted: nothing applied (offers shown were recorded)")
			return nil
		}
	}

	// ── Apply ────────────────────────────────────────────────────────────
	summary, applyErr := registry.Apply(ctx)
	for _, c := range summary.Applied {
		output.Dimmed(fmt.Sprintf("  %s %s %s", c.Reconciler, c.Kind, c.Path))
	}
	if applyErr != nil {
		return applyErr
	}

	if len(mutations) > 0 {
		if err := writeMutations(targetDir, mutations); err != nil {
			return err
		}
		output.Success(
			fmt.Sprintf("Wrote %d config mutation(s) to .stack/config.nix", len(mutations)),
		)
		if speculation != nil {
			if err := reconcileAfterMutation(ctx, speculation); err != nil {
				output.Warning(
					fmt.Sprintf(
						"could not reconcile the new generation now: %v",
						firstLine(err.Error()),
					),
				)
				output.Dimmed(
					"  the files will materialize on the next shell entry (direnv reload)",
				)
			}
		} else {
			output.Dimmed(
				"  generated files will materialize on the next shell entry (direnv reload)",
			)
		}
	}

	if err := recordDecisions(
		targetDir,
		addonsFor(addonsRC, ctx),
		decisions,
	); err != nil {
		return err
	}

	fmt.Fprintln(os.Stderr)
	output.Success("stack setup complete")
	if !ctx.InDevshell() {
		output.Dimmed("  Next steps:")
		output.Dimmed("    1. Review the generated files in .stack/ and flake.nix")
		output.Dimmed("    2. Edit .stack/config.nix to configure your project")
		output.Dimmed("    3. Run 'direnv allow' (or 'nix develop') to enter the shell")
	}
	if opts.tmp {
		fmt.Fprintln(cmd.OutOrStdout(), targetDir)
	}
	return nil
}

// offerDecision pairs an offer with the answer that was resolved for it.
type offerDecision struct {
	addon  nixeval.AddonSpec
	answer reconcile.Answer
}

// decideOffers resolves an answer for every pending offer and flattens the
// accepted ones into config mutations. Nothing is written here.
func decideOffers(
	offers []reconcile.Offer,
	addons []nixeval.AddonSpec,
	inputs reconcile.AnswerInputs,
	takeDefaults bool,
) ([]offerDecision, []reconcile.Mutation, error) {
	byID := map[string]nixeval.AddonSpec{}
	for _, a := range addons {
		byID[a.ID] = a
	}
	var decisions []offerDecision
	var mutations []reconcile.Mutation
	for _, o := range offers {
		a, ok := byID[o.ID]
		if !ok {
			continue
		}
		if takeDefaults && inputs.Prompt != nil {
			inputs.Prompt = nil
		}
		ans, err := reconcile.ResolveAnswer(inputs, a)
		if err != nil {
			return nil, nil, fmt.Errorf("addon %q: %w", a.ID, err)
		}
		decisions = append(decisions, offerDecision{addon: a, answer: ans})
		if muts, active := reconcile.Materialize(a, ans); active {
			mutations = append(mutations, muts...)
		}
	}
	return decisions, mutations, nil
}

func addonsFor(
	rc *reconcile.AddonsReconciler,
	ctx *reconcile.Context,
) []nixeval.AddonSpec {
	if rc.Addons != nil {
		return rc.Addons
	}
	if ctx.Config != nil {
		return ctx.Config.Addons
	}
	return nil
}

// recordDecisions writes the shown offers into the ledger. It records what was
// shown, not what the user wants: declining writes no config at all.
func recordDecisions(
	projectRoot string,
	addons []nixeval.AddonSpec,
	decisions []offerDecision,
) error {
	if len(decisions) == 0 {
		return nil
	}
	ledger, err := reconcile.LoadLedger(projectRoot, reconcile.RevisionsOf(addons))
	if err != nil {
		return err
	}
	now := time.Now()
	for _, d := range decisions {
		ledger.Record(d.addon.ID, d.addon.Revision, d.answer.Record(d.addon.Question), now)
	}
	if err := ledger.Save(); err != nil {
		return fmt.Errorf("write %s: %w", ledger.Path(), err)
	}
	return nil
}

// writeMutations patches .stack/config.nix through the same tree-sitter editor
// the studio uses, so comments and formatting survive.
func writeMutations(projectRoot string, mutations []reconcile.Mutation) error {
	exec, err := executor.NewWithoutDevshell(projectRoot, nil)
	if err != nil {
		return fmt.Errorf("create executor: %w", err)
	}
	store := nixdata.NewStore(projectRoot, exec)
	for _, m := range mutations {
		if err := store.PatchConsolidatedData(m.Path, m.Value); err != nil {
			return fmt.Errorf("set %s in config.nix: %w", m.Path, err)
		}
	}
	return nil
}

// reconcileAfterMutation materializes the new generation without a shell
// re-entry: realize the speculative eval's write-files script and preflight
// manifest with nix build, then run them.
func reconcileAfterMutation(ctx *reconcile.Context, spec *reconcile.Speculation) error {
	output.Dimmed("  realizing the new generation with nix build...")
	outs, err := reconcile.RealizeOutputs(
		ctx.Ctx,
		ctx.ProjectRoot,
		spec.WriterDrvPath,
		spec.PreflightManifestDrvPath,
	)
	if err != nil {
		return err
	}
	writer := spec.WriterOutPath
	manifest := spec.PreflightManifestOutPath
	for _, o := range outs {
		switch {
		case strings.HasSuffix(o, "write-files"):
			writer = o
		case strings.HasSuffix(o, "stackpanel-files-preflight.json"):
			manifest = o
		}
	}
	filesRC := &reconcile.FilesReconciler{}
	if _, err := os.Stat(filepath.Join(writer, "bin", "write-files")); err == nil {
		res, err := runWriteFilesAt(ctx, filepath.Join(writer, "bin", "write-files"))
		if err != nil {
			return err
		}
		for _, c := range res.Applied {
			output.Dimmed(fmt.Sprintf("  %s %s %s", filesRC.ID(), c.Kind, c.Path))
		}
	}
	if _, err := os.Stat(manifest); err == nil {
		fileopsRC := &reconcile.FileopsReconciler{ManifestPath: manifest}
		res, err := fileopsRC.Apply(ctx)
		if err != nil {
			return err
		}
		for _, c := range res.Applied {
			output.Dimmed(fmt.Sprintf("  %s %s %s", fileopsRC.ID(), c.Kind, c.Path))
		}
	}
	return nil
}

func runWriteFilesAt(
	ctx *reconcile.Context,
	writer string,
) (*reconcile.ApplyResult, error) {
	cmd := exec.CommandContext(ctx.Ctx, writer)
	cmd.Dir = ctx.ProjectRoot
	cmd.Env = append(
		os.Environ(),
		"STACKPANEL_ROOT="+ctx.ProjectRoot,
		"STACKPANEL_STATE_DIR="+ctx.StateDir,
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("write-files: %w\n%s", err, strings.TrimSpace(string(out)))
	}
	res := &reconcile.ApplyResult{}
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "write ") {
			res.Applied = append(
				res.Applied,
				reconcile.Change{Kind: reconcile.ChangeUpdate, Path: strings.Fields(line)[1]},
			)
		}
	}
	return res, nil
}

// promptAddon asks one addon question interactively.
func promptAddon(a nixeval.AddonSpec) (reconcile.Answer, error) {
	q := a.Question
	label := q.Label
	if q.Description != "" {
		output.Dimmed("  " + q.Description)
	}
	switch q.Type {
	case "bool":
		def, _ := q.Default.(bool)
		ok, err := tui.Confirm(label, def)
		return reconcile.Answer{Bool: ok}, err
	case "select":
		labels, byLabel := reconcile.ChoiceLabels(q)
		got, err := tui.Select(
			label,
			labels,
			reconcile.LabelForValue(q, reconcile.DefaultSelect(q)),
		)
		if err != nil {
			return reconcile.Answer{}, err
		}
		return reconcile.Answer{Select: byLabel[got]}, nil
	case "multiselect":
		labels, byLabel := reconcile.ChoiceLabels(q)
		defLabels := make([]string, 0)
		for _, v := range reconcile.DefaultMulti(q) {
			if l := reconcile.LabelForValue(q, v); l != "" {
				defLabels = append(defLabels, l)
			}
		}
		got, err := tui.MultiSelect(label, labels, defLabels)
		if err != nil {
			return reconcile.Answer{}, err
		}
		vals := make([]string, 0, len(got))
		for _, g := range got {
			if v, ok := byLabel[g]; ok {
				vals = append(vals, v)
			}
		}
		return reconcile.Answer{Multi: vals}, nil
	default:
		return reconcile.Answer{}, fmt.Errorf("unknown question type %q", q.Type)
	}
}

func hasFlake(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, "flake.nix"))
	return err == nil
}

func firstLine(s string) string {
	if idx := strings.IndexByte(s, '\n'); idx >= 0 {
		return s[:idx]
	}
	return s
}

// resolveFlakeRef picks the flake ref from (in order): --flake, STACKPANEL_FLAKE,
// STACKPANEL_ROOT, default.
func resolveFlakeRef(flag string) string {
	if flag != "" {
		return flag
	}
	if v := os.Getenv("STACKPANEL_FLAKE"); v != "" {
		return v
	}
	if root := os.Getenv("STACKPANEL_ROOT"); root != "" {
		return "path:" + root
	}
	return defaultStackpanelFlake
}

func setupTargetDir(ctx context.Context, tmp bool, readOnly bool) (string, error) {
	if !tmp {
		targetDir, err := os.Getwd()
		if err != nil {
			return "", fmt.Errorf("failed to get current directory: %w", err)
		}
		return targetDir, nil
	}
	if readOnly {
		return "", errors.New("--tmp cannot be combined with --dry-run or --json")
	}
	return createTmpInitTarget(ctx)
}

func createTmpInitTarget(ctx context.Context) (string, error) {
	targetDir, err := os.MkdirTemp("", "stackpanel-init-*")
	if err != nil {
		return "", fmt.Errorf("failed to create temporary init directory: %w", err)
	}

	cmd := exec.CommandContext(ctx, "git", "init", targetDir)
	if out, err := cmd.CombinedOutput(); err != nil {
		_ = os.RemoveAll(targetDir)
		return "", fmt.Errorf(
			"failed to initialize git repository: %w\n%s",
			err,
			string(out),
		)
	}

	return targetDir, nil
}

// findProjectRoot walks up the directory tree to find a project root
// (directory containing flake.nix or .stackpanel).
func findProjectRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "flake.nix")); err == nil {
			return dir, nil
		}
		if _, err := os.Stat(filepath.Join(dir, ".stackpanel")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf(
				"no project root found (looking for flake.nix or .stackpanel)",
			)
		}
		dir = parent
	}
}

// sortedKeys returns the map keys in deterministic order.
func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// ensure fileops stays referenced for the manifest type used by the apply path.
var _ = fileops.Manifest{}
