package cmd

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	executor "github.com/darkmatter/stackpanel/stackpanel-go/pkg/exec"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/spf13/cobra"
)

// Default flake reference for stackpanel.
// Users can override with --flake flag or STACKPANEL_FLAKE env var.
const defaultStackpanelFlake = "github:darkmatter/stackpanel"

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize a new stackpanel project",
	Long: `Initialize scaffolds a new stackpanel project and registers it so the
agent can find it. The scaffolding (flake.nix, .envrc, .stack/, ...) is fetched
from the stackpanel flake's lib.initFiles, which is derived from the same
template directory used by 'nix flake init -t' — both produce identical files.

The command is idempotent: running it again will skip any step whose work has
already been done. New steps added in future releases will be run on re-run.

An interactive TUI (via gum) guides you through each step. Pass
--non-interactive (or run under a non-TTY) to execute all steps without prompts.

Example:
  stackpanel init                              # Interactive setup
  stackpanel init --non-interactive            # No prompts, apply everything
  stackpanel init --force                      # Overwrite existing files
  stackpanel init --dry-run                    # Show what would be done
  stackpanel init --template minimal          # Use a named template
  stackpanel init --tmp                       # Create a temporary git repo
  stackpanel init --flake path:/path/to/sp     # Use a local stackpanel checkout
  stackpanel init --with vscode                # Enable an addon without prompting
  stackpanel init --without editorconfig       # Decline an addon without prompting
  stackpanel init --addon deploy=fly           # Answer a select addon explicitly`,
	RunE: runInit,
}

var (
	initForce          bool
	initDryRun         bool
	initFlake          string
	initTemplate       string
	initTmp            bool
	initNonInteractive bool
	initWith           []string
	initWithout        []string
	initAddonValues    []string
)

func init() {
	initCmd.Flags().BoolVar(&initForce, "force", false, "Overwrite existing files")
	initCmd.Flags().
		BoolVar(&initDryRun, "dry-run", false, "Show what would be created without writing files")
	initCmd.Flags().
		StringVar(&initFlake, "flake", "", "Stackpanel flake reference (default: github:darkmatter/stackpanel)")
	initCmd.Flags().
		StringVar(&initTemplate, "template", "default", "Template name to initialize")
	initCmd.Flags().
		BoolVar(&initTmp, "tmp", false, "Create the project in a temporary git repository and print its path")
	initCmd.Flags().
		BoolVar(&initNonInteractive, "non-interactive", false, "Skip all prompts and apply every pending step")
	initCmd.Flags().
		StringSliceVar(&initWith, "with", nil, "Enable an addon by id without prompting (repeatable)")
	initCmd.Flags().
		StringSliceVar(&initWithout, "without", nil, "Decline an addon by id without prompting (repeatable)")
	initCmd.Flags().
		StringSliceVar(&initAddonValues, "addon", nil, "Answer an addon explicitly as id=value (value: true/false, a choice value, or comma-separated values)")

	rootCmd.AddCommand(initCmd)
}

// -----------------------------------------------------------------------------
// Step machinery
// -----------------------------------------------------------------------------

// stepContext carries shared state between steps so each step can consult the
// resolved target directory, flake ref, flag values, and any cached data from
// prior steps (e.g. fetched init files).
type stepContext struct {
	ctx         context.Context
	targetDir   string
	flakeRef    string
	force       bool
	dryRun      bool
	template    string
	tmp         bool
	verbose     bool
	interactive bool

	// addon selection inputs (flags). Empty unless the user passed them.
	withAddons    []string
	withoutAddons []string
	addonValues   []string

	// cache: populated by the fetch step, consumed by the write-files step.
	initFiles map[string]string

	// addon cache + per-process guard for the configure-addons step.
	addons         []nixeval.AddonSpec
	addonsResolved bool
}

// step is the core abstraction for idempotent init work. Adding a new stage
// to `stackpanel init` is a matter of appending a `step` to `buildSteps`.
type step struct {
	// ID is used for logging only; keep it short and kebab-cased.
	ID string
	// Title is a human-readable label shown in prompts.
	Title string
	// Description is an optional longer sentence shown before the prompt.
	Description string
	// IsDone returns true if there is nothing to do for this step.
	// When true the step is skipped entirely (no prompt, no apply call).
	IsDone func(*stepContext) (bool, string, error)
	// Apply runs the step. It should be safe to invoke even if partially done.
	// Returned summary (if non-empty) is printed on success.
	Apply func(*stepContext) (string, error)
	// Confirm, when true, asks the user before running Apply in interactive mode.
	// Set to false for steps the user is expected to accept (fetching templates
	// from a flake reference, writing missing scaffolding, etc.).
	Confirm bool
}

func runInit(cmd *cobra.Command, args []string) error {
	verbose, _ := cmd.Flags().GetBool("verbose")
	ctx := context.Background()

	targetDir, err := initTargetDir(ctx, initTmp, initDryRun)
	if err != nil {
		return err
	}

	flakeRef := resolveFlakeRef(initFlake)

	sctx := &stepContext{
		ctx:         ctx,
		targetDir:   targetDir,
		flakeRef:    flakeRef,
		force:       initForce,
		dryRun:      initDryRun,
		template:    initTemplate,
		tmp:         initTmp,
		verbose:     verbose,
		interactive: !initNonInteractive && tui.IsInteractiveStdio(),

		withAddons:    initWith,
		withoutAddons: initWithout,
		addonValues:   initAddonValues,
	}

	if verbose {
		output.Info(fmt.Sprintf("Target directory: %s", targetDir))
		output.Info(fmt.Sprintf("Using stackpanel flake: %s", flakeRef))
		output.Info(fmt.Sprintf("Using template: %s", initTemplate))
		if !sctx.interactive {
			output.Info("Non-interactive mode: prompts will be skipped")
		}
	}

	steps := buildSteps()

	if sctx.dryRun {
		output.Info("Dry run: no files will be written, no state will change")
	}

	for _, s := range steps {
		if err := runStep(sctx, s); err != nil {
			return err
		}
	}

	fmt.Fprintln(os.Stderr)
	output.Success("stackpanel init complete")
	output.Dimmed("  Next steps:")
	output.Dimmed("    1. Review the generated files in .stackpanel/ and flake.nix")
	output.Dimmed("    2. Edit .stackpanel/config.nix to configure your project")
	output.Dimmed(
		"    3. Run 'direnv allow' (or 'nix develop') to enter the shell",
	)
	if sctx.tmp {
		fmt.Fprintln(cmd.OutOrStdout(), targetDir)
	}

	return nil
}

// runStep handles the common flow: check isDone, optionally prompt, run apply.
// It keeps runInit short and testable.
func runStep(sctx *stepContext, s step) error {
	done, doneMsg, err := s.IsDone(sctx)
	if err != nil {
		return fmt.Errorf("step %q check failed: %w", s.ID, err)
	}
	if done {
		if doneMsg == "" {
			doneMsg = s.Title
		}
		output.Green.Fprintf(os.Stderr, "✓ %s", doneMsg)
		fmt.Fprintln(os.Stderr, " (already done)")
		return nil
	}

	// Announce the step (before the prompt) so the user knows why we're asking.
	output.Info(s.Title)
	if s.Description != "" {
		output.Dimmed("  " + s.Description)
	}

	if sctx.interactive && s.Confirm && !sctx.dryRun {
		ok, err := tui.Confirm(fmt.Sprintf("Run step: %s?", s.Title), true)
		if err != nil {
			return fmt.Errorf("step %q confirm failed: %w", s.ID, err)
		}
		if !ok {
			output.Warning(fmt.Sprintf("Skipped %s (user declined)", s.ID))
			return nil
		}
	}

	if sctx.dryRun {
		output.Dimmed(fmt.Sprintf("  [dry-run] would apply: %s", s.ID))
		return nil
	}

	summary, err := s.Apply(sctx)
	if err != nil {
		return fmt.Errorf("step %q failed: %w", s.ID, err)
	}
	if summary != "" {
		output.Success(summary)
	}
	return nil
}

// buildSteps returns the ordered list of init steps. Adding a new stage is a
// one-liner append here; the machinery above handles idempotency and prompts.
func buildSteps() []step {
	return []step{
		stepFetchInitFiles(),
		stepWriteInitFiles(),
		stepAddons(),
		stepRegisterProject(),
	}
}

// -----------------------------------------------------------------------------
// Steps
// -----------------------------------------------------------------------------

// stepFetchInitFiles evaluates the stackpanel flake's `lib.initFiles` attribute
// and caches the map on the context for downstream steps.
func stepFetchInitFiles() step {
	return step{
		ID:          "fetch-init-files",
		Title:       "Fetch boilerplate from stackpanel flake",
		Description: "Evaluates <flake>#lib.initTemplates.<template> for project scaffolding (same file set as `nix flake init -t`).",
		IsDone: func(s *stepContext) (bool, string, error) {
			// This step is always "not done" until we've fetched files once per
			// invocation — the cache is per-process, so re-running the command
			// will refetch (which is desired: users might upgrade the flake).
			return s.initFiles != nil, "Boilerplate fetched", nil
		},
		Apply: func(s *stepContext) (string, error) {
			files, err := getInitFilesFromFlake(s.ctx, s.flakeRef, s.template)
			if err != nil {
				return "", fmt.Errorf(
					"failed to get init files from flake: %w\nHint: check that the flake reference %q is valid",
					err,
					s.flakeRef,
				)
			}
			s.initFiles = files
			return fmt.Sprintf("Fetched %d file(s) from stackpanel flake", len(files)), nil
		},
	}
}

// stepWriteInitFiles writes every file from the fetched initFiles map that
// doesn't already exist on disk (or, with --force, overwrites them).
func stepWriteInitFiles() step {
	return step{
		ID:          "write-init-files",
		Title:       "Write project scaffolding files",
		Description: "Writes any missing scaffolding files. Existing files are left alone unless --force.",
		IsDone: func(s *stepContext) (bool, string, error) {
			if s.force {
				// With --force we always (re)write. Never consider this done.
				return false, "", nil
			}
			if s.initFiles == nil {
				return false, "", nil
			}
			for rel := range s.initFiles {
				if _, err := os.Stat(filepath.Join(s.targetDir, rel)); errors.Is(
					err,
					os.ErrNotExist,
				) {
					return false, "", nil
				} else if err != nil {
					return false, "", err
				}
			}
			return true, "All scaffolding files present", nil
		},
		Apply: func(s *stepContext) (string, error) {
			if s.initFiles == nil {
				return "", fmt.Errorf("initFiles not fetched; fetch step must run first")
			}
			created, skipped, err := writeInitFiles(
				s.targetDir,
				s.initFiles,
				s.force,
				s.verbose,
			)
			if err != nil {
				return "", err
			}
			return fmt.Sprintf("Wrote %d file(s), skipped %d", created, skipped), nil
		},
	}
}

// stepRegisterProject records this directory in ~/.config/stackpanel/stackpanel.yaml
// so the agent and studio can find it.
func stepRegisterProject() step {
	return step{
		ID:          "register-project",
		Title:       "Register project with stackpanel user config",
		Description: "Adds this directory to ~/.config/stackpanel/stackpanel.yaml so the agent sees it.",
		IsDone: func(s *stepContext) (bool, string, error) {
			if s.tmp {
				return true, "Temporary project not registered", nil
			}
			ucm, err := userconfig.NewManager()
			if err != nil {
				// If we can't even read the user config, treat as not done so
				// Apply gets to surface the real error.
				return false, "", nil
			}
			if ucm.HasProject(s.targetDir) {
				return true, "Project already registered", nil
			}
			return false, "", nil
		},
		Apply: func(s *stepContext) (string, error) {
			ucm, err := userconfig.NewManager()
			if err != nil {
				return "", fmt.Errorf("failed to create user config manager: %w", err)
			}
			name := filepath.Base(s.targetDir)
			if _, err := ucm.AddProject(s.targetDir, name); err != nil {
				return "", fmt.Errorf("failed to add project: %w", err)
			}
			return "Registered project in ~/.config/stackpanel/stackpanel.yaml", nil
		},
	}
}

// -----------------------------------------------------------------------------
// Addons
// -----------------------------------------------------------------------------

// stepAddons asks about optional addons declared by the flake (lib.initAddons),
// then for each accepted answer copies the addon's files into the project and
// patches its config into .stack/config.nix. Choices are recorded in
// .stack/addons.json so re-runs don't re-ask; new addons are offered on re-run,
// and --force re-asks everything.
func stepAddons() step {
	return step{
		ID:          "configure-addons",
		Title:       "Configure optional addons",
		Description: "Asks about optional integrations (e.g. VS Code) and applies the ones you pick.",
		// Per-process guard: the marker file handles cross-run idempotency.
		IsDone: func(s *stepContext) (bool, string, error) {
			return s.addonsResolved, "Addons configured", nil
		},
		Apply: applyAddonsStep,
	}
}

func applyAddonsStep(s *stepContext) (string, error) {
	addons := getAddons(s)
	s.addonsResolved = true
	if len(addons) == 0 {
		return "No addons offered by this flake", nil
	}

	marker, err := readAddonMarker(s.targetDir)
	if err != nil {
		return "", err
	}

	// Lazily construct the nixdata store only when an addon actually needs a
	// config patch (file-only addons don't touch it).
	var store *nixdata.Store
	ensureStore := func() (*nixdata.Store, error) {
		if store != nil {
			return store, nil
		}
		exec, err := executor.NewWithoutDevshell(s.targetDir, nil)
		if err != nil {
			return nil, fmt.Errorf("create executor: %w", err)
		}
		store = nixdata.NewStore(s.targetDir, exec)
		return store, nil
	}

	var appliedNow []string
	var warnings []string
	for _, a := range addons {
		if _, seen := marker.Addons[a.ID]; seen && !s.force {
			continue
		}

		ans, err := resolveAddonAnswer(s, a)
		if err != nil {
			return "", fmt.Errorf("addon %q: %w", a.ID, err)
		}

		plan := materializeAddon(a, ans)
		if !plan.active {
			// Record the decline so re-runs don't nag (until --force).
			marker.Addons[a.ID] = plan.record
			continue
		}

		if len(plan.files) > 0 {
			if _, _, err := writeInitFiles(s.targetDir, plan.files, s.force, s.verbose); err != nil {
				return "", fmt.Errorf("addon %q: write files: %w", a.ID, err)
			}
		}

		if len(plan.enables) > 0 || len(plan.jsonOps) > 0 {
			st, err := ensureStore()
			if err != nil {
				return "", err
			}
			if patchErr := applyAddonConfig(st, a.ID, plan, &warnings); patchErr {
				// Leave unmarked so a later run retries the patch.
				continue
			}
		}

		marker.Addons[a.ID] = plan.record
		appliedNow = append(appliedNow, a.ID)
	}

	if err := writeAddonMarker(s.targetDir, marker); err != nil {
		return "", err
	}
	for _, w := range warnings {
		output.Warning(w)
	}
	if len(appliedNow) == 0 {
		return "No new addons to apply", nil
	}
	sort.Strings(appliedNow)
	return fmt.Sprintf("Applied addon(s): %s", strings.Join(appliedNow, ", ")), nil
}

// applyAddonConfig patches an addon's config enables and json-ops entries into
// config.nix. It returns true if any patch failed (the caller then leaves the
// addon unmarked so a later run retries). Failures are collected as warnings
// rather than aborting the whole init.
func applyAddonConfig(
	st *nixdata.Store,
	id string,
	plan addonPlan,
	warnings *[]string,
) bool {
	for _, e := range plan.enables {
		if err := st.PatchConsolidatedData(e.path, e.value); err != nil {
			*warnings = append(
				*warnings,
				fmt.Sprintf("%s: could not set %s (%v)", id, e.path, err),
			)
			return true
		}
	}
	// Register each json-ops target as a stackpanel.files.entries entry so the
	// generator merges it into the (possibly pre-existing) JSON file on shell
	// entry. Sorted for deterministic patch ordering.
	for _, file := range sortedKeys(plan.jsonOps) {
		path := "files.entries." + escapeConfigKey(file)
		if err := st.PatchConsolidatedData(path, jsonOpsEntryValue(plan.jsonOps[file])); err != nil {
			*warnings = append(
				*warnings,
				fmt.Sprintf("%s: could not register json-ops for %s (%v)", id, file, err),
			)
			return true
		}
	}
	return false
}

// getAddons fetches and caches the flake's addon manifest. Failure is
// non-fatal: a flake without lib.initAddons (older release) simply offers no
// addons, so init still completes.
func getAddons(s *stepContext) []nixeval.AddonSpec {
	if s.addons != nil {
		return s.addons
	}
	addons, err := nixeval.GetInitAddonsFromFlake(s.ctx, normalizeFlakeRef(s.flakeRef))
	if err != nil {
		if s.verbose {
			output.Dimmed(fmt.Sprintf("  no addons available: %v", err))
		}
		addons = []nixeval.AddonSpec{}
	}
	s.addons = addons
	return addons
}

// -----------------------------------------------------------------------------
// Addon answer resolution
// -----------------------------------------------------------------------------

// addonAnswer is the resolved response to an addon question. Only the field
// matching the question type is meaningful.
type addonAnswer struct {
	boolVal   bool
	selectVal string
	multiVal  []string
}

// resolveAddonAnswer determines the answer for an addon, in priority order:
// explicit --addon id=value, then --with/--without, then an interactive prompt,
// then the question's declared default.
func resolveAddonAnswer(s *stepContext, a nixeval.AddonSpec) (addonAnswer, error) {
	q := a.Question

	if raw, ok := explicitAddonValue(s.addonValues, a.ID); ok {
		return parseAddonValue(q.Type, raw), nil
	}
	if containsFold(s.withoutAddons, a.ID) {
		return addonAnswer{}, nil // bool=false / select="" / multi=nil
	}
	if containsFold(s.withAddons, a.ID) {
		switch q.Type {
		case "bool":
			return addonAnswer{boolVal: true}, nil
		case "select":
			return addonAnswer{selectVal: defaultSelect(q)}, nil
		case "multiselect":
			return addonAnswer{multiVal: allChoiceValues(q)}, nil
		}
	}
	if s.interactive {
		return promptAddon(a)
	}
	return defaultAddonAnswer(q), nil
}

func promptAddon(a nixeval.AddonSpec) (addonAnswer, error) {
	q := a.Question
	switch q.Type {
	case "bool":
		def, _ := q.Default.(bool)
		ok, err := tui.Confirm(q.Label, def)
		return addonAnswer{boolVal: ok}, err
	case "select":
		labels, byLabel := choiceLabels(q)
		got, err := tui.Select(q.Label, labels, labelForValue(q, defaultSelect(q)))
		if err != nil {
			return addonAnswer{}, err
		}
		return addonAnswer{selectVal: byLabel[got]}, nil
	case "multiselect":
		labels, byLabel := choiceLabels(q)
		defLabels := make([]string, 0)
		for _, v := range defaultMulti(q) {
			if l := labelForValue(q, v); l != "" {
				defLabels = append(defLabels, l)
			}
		}
		got, err := tui.MultiSelect(q.Label, labels, defLabels)
		if err != nil {
			return addonAnswer{}, err
		}
		vals := make([]string, 0, len(got))
		for _, g := range got {
			if v, ok := byLabel[g]; ok {
				vals = append(vals, v)
			}
		}
		return addonAnswer{multiVal: vals}, nil
	default:
		return addonAnswer{}, fmt.Errorf("unknown question type %q", q.Type)
	}
}

func defaultAddonAnswer(q nixeval.AddonQuestion) addonAnswer {
	switch q.Type {
	case "bool":
		b, _ := q.Default.(bool)
		return addonAnswer{boolVal: b}
	case "select":
		return addonAnswer{selectVal: defaultSelect(q)}
	case "multiselect":
		return addonAnswer{multiVal: defaultMulti(q)}
	}
	return addonAnswer{}
}

// addonPlan is the resolved effect of an addon answer: files to write, config
// enables to patch, json-ops to register, the value to persist in the marker,
// and whether the addon is active (contributes anything).
type addonPlan struct {
	files   map[string]string
	enables []configEnable
	jsonOps map[string][]nixeval.AddonJSONOp
	record  any
	active  bool
}

// materializeAddon turns an answer into the work to perform. For json-ops we use
// addon-level ops (a.JSONOps) for every active answer; per-choice json-ops are
// not supported yet. record is the value persisted in the marker.
func materializeAddon(a nixeval.AddonSpec, ans addonAnswer) addonPlan {
	files := map[string]string{}
	q := a.Question
	switch q.Type {
	case "bool":
		if !ans.boolVal {
			return addonPlan{record: false}
		}
		mergeFiles(files, a.Files)
		enables := flattenConfig("", a.Config)
		return addonPlan{
			files:   files,
			enables: enables,
			jsonOps: a.JSONOps,
			record:  true,
			active:  hasWork(files, enables, a.JSONOps),
		}
	case "select":
		ch, ok := findChoice(q, ans.selectVal)
		if !ok || ans.selectVal == "" {
			return addonPlan{record: ans.selectVal}
		}
		mergeFiles(files, a.Files) // addon-level shared files
		mergeFiles(files, ch.Files)
		enables := append(flattenConfig("", a.Config), flattenConfig("", ch.Config)...)
		return addonPlan{
			files:   files,
			enables: enables,
			jsonOps: a.JSONOps,
			record:  ans.selectVal,
			active:  hasWork(files, enables, a.JSONOps),
		}
	case "multiselect":
		if len(ans.multiVal) == 0 {
			return addonPlan{record: ans.multiVal}
		}
		mergeFiles(files, a.Files)
		enables := flattenConfig("", a.Config)
		for _, v := range ans.multiVal {
			if ch, ok := findChoice(q, v); ok {
				mergeFiles(files, ch.Files)
				enables = append(enables, flattenConfig("", ch.Config)...)
			}
		}
		return addonPlan{
			files:   files,
			enables: enables,
			jsonOps: a.JSONOps,
			record:  ans.multiVal,
			active:  hasWork(files, enables, a.JSONOps),
		}
	}
	return addonPlan{}
}

// hasWork reports whether a materialised answer actually contributes anything
// (so that e.g. selecting a "none" choice is recorded but not reported as
// applied).
func hasWork(
	files map[string]string,
	enables []configEnable,
	jsonOps map[string][]nixeval.AddonJSONOp,
) bool {
	return len(files) > 0 || len(enables) > 0 || len(jsonOps) > 0
}

// jsonOpsEntryValue builds the stackpanel.files.entries value for a json-ops
// target: { type = "json-ops"; adopt = "backup"; ops = [ ... ]; }. Paths are
// emitted as lists so they serialise to Nix list literals.
func jsonOpsEntryValue(ops []nixeval.AddonJSONOp) map[string]any {
	opList := make([]any, 0, len(ops))
	for _, op := range ops {
		pathAny := make([]any, len(op.Path))
		for i, p := range op.Path {
			pathAny[i] = p
		}
		entry := map[string]any{
			"op":   op.Op,
			"path": pathAny,
		}
		if op.Value != nil {
			entry["value"] = op.Value
		}
		opList = append(opList, entry)
	}
	return map[string]any{
		"type":  "json-ops",
		"adopt": "backup",
		"ops":   opList,
	}
}

// escapeConfigKey escapes dots in a config path segment so SplitConfigPath keeps
// it as a single key (e.g. "package.json" -> "package\\.json").
func escapeConfigKey(key string) string {
	return strings.ReplaceAll(key, ".", "\\.")
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

// configEnable is a single dot-path assignment patched into config.nix.
type configEnable struct {
	path  string
	value any
}

// flattenConfig turns a nested config attrset into leaf dot-paths. Map values
// are descended into; everything else (scalars, lists) is a leaf. Keys are
// sorted for deterministic patch ordering.
func flattenConfig(prefix string, m map[string]any) []configEnable {
	if len(m) == 0 {
		return nil
	}
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var out []configEnable
	for _, k := range keys {
		path := k
		if prefix != "" {
			path = prefix + "." + k
		}
		if child, ok := m[k].(map[string]any); ok {
			out = append(out, flattenConfig(path, child)...)
			continue
		}
		out = append(out, configEnable{path: path, value: m[k]})
	}
	return out
}

// -----------------------------------------------------------------------------
// Addon marker (.stack/addons.json)
// -----------------------------------------------------------------------------

// addonMarker records prior addon decisions so re-runs don't re-prompt. It is
// written alongside config.nix (committed, not gitignored).
type addonMarker struct {
	Version int            `json:"version"`
	Addons  map[string]any `json:"addons"`
}

func addonMarkerPath(targetDir string) string {
	configDir := filepath.Dir(nixdata.NewPaths(targetDir).ConfigFilePath())
	return filepath.Join(configDir, "addons.json")
}

func readAddonMarker(targetDir string) (addonMarker, error) {
	m := addonMarker{Version: 1, Addons: map[string]any{}}
	data, err := os.ReadFile(addonMarkerPath(targetDir))
	if errors.Is(err, os.ErrNotExist) {
		return m, nil
	}
	if err != nil {
		return m, err
	}
	if err := json.Unmarshal(data, &m); err != nil {
		return m, fmt.Errorf("parse %s: %w", addonMarkerPath(targetDir), err)
	}
	if m.Addons == nil {
		m.Addons = map[string]any{}
	}
	return m, nil
}

func writeAddonMarker(targetDir string, m addonMarker) error {
	m.Version = 1
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	p := addonMarkerPath(targetDir)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	return os.WriteFile(p, append(data, '\n'), 0o644)
}

// -----------------------------------------------------------------------------
// Addon helpers
// -----------------------------------------------------------------------------

func explicitAddonValue(pairs []string, id string) (string, bool) {
	for _, p := range pairs {
		idx := strings.IndexByte(p, '=')
		if idx < 0 {
			continue
		}
		if strings.EqualFold(strings.TrimSpace(p[:idx]), id) {
			return strings.TrimSpace(p[idx+1:]), true
		}
	}
	return "", false
}

func parseAddonValue(qType, raw string) addonAnswer {
	switch qType {
	case "bool":
		v := strings.EqualFold(raw, "true") || raw == "1" || strings.EqualFold(raw, "yes")
		return addonAnswer{boolVal: v}
	case "multiselect":
		var vals []string
		for _, part := range strings.Split(raw, ",") {
			part = strings.TrimSpace(part)
			if part != "" {
				vals = append(vals, part)
			}
		}
		return addonAnswer{multiVal: vals}
	default: // select
		return addonAnswer{selectVal: strings.TrimSpace(raw)}
	}
}

func containsFold(list []string, target string) bool {
	for _, s := range list {
		if strings.EqualFold(strings.TrimSpace(s), target) {
			return true
		}
	}
	return false
}

func defaultSelect(q nixeval.AddonQuestion) string {
	if s, ok := q.Default.(string); ok {
		return s
	}
	return ""
}

func defaultMulti(q nixeval.AddonQuestion) []string {
	arr, ok := q.Default.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(arr))
	for _, v := range arr {
		if s, ok := v.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func allChoiceValues(q nixeval.AddonQuestion) []string {
	out := make([]string, 0, len(q.Choices))
	for _, c := range q.Choices {
		out = append(out, c.Value)
	}
	return out
}

// choiceLabels returns the display labels and a label->value lookup. A choice
// with no label falls back to its value.
func choiceLabels(q nixeval.AddonQuestion) (labels []string, byLabel map[string]string) {
	byLabel = make(map[string]string, len(q.Choices))
	for _, c := range q.Choices {
		label := c.Label
		if label == "" {
			label = c.Value
		}
		labels = append(labels, label)
		byLabel[label] = c.Value
	}
	return labels, byLabel
}

func labelForValue(q nixeval.AddonQuestion, value string) string {
	for _, c := range q.Choices {
		if c.Value == value {
			if c.Label != "" {
				return c.Label
			}
			return c.Value
		}
	}
	return ""
}

func findChoice(q nixeval.AddonQuestion, value string) (nixeval.AddonChoice, bool) {
	for _, c := range q.Choices {
		if c.Value == value {
			return c, true
		}
	}
	return nixeval.AddonChoice{}, false
}

func mergeFiles(dst, src map[string]string) {
	for k, v := range src {
		dst[k] = v
	}
}

// -----------------------------------------------------------------------------
// File writing helper
// -----------------------------------------------------------------------------

// writeInitFiles writes every (path, content) pair under root, respecting
// `force`. Returns (created, skipped, error). Kept separate from the step so
// tests can call it directly.
func writeInitFiles(
	root string,
	files map[string]string,
	force, verbose bool,
) (int, int, error) {
	// Sort keys for deterministic output in tests and logs.
	keys := make([]string, 0, len(files))
	for k := range files {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var created, skipped int
	for _, rel := range keys {
		abs := filepath.Join(root, rel)
		exists := false
		if _, err := os.Stat(abs); err == nil {
			exists = true
		} else if !errors.Is(err, os.ErrNotExist) {
			return created, skipped, err
		}

		if exists && !force {
			if verbose {
				output.Dimmed(fmt.Sprintf("  skip: %s (exists)", rel))
			}
			skipped++
			continue
		}

		if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
			return created, skipped, fmt.Errorf(
				"failed to create directory for %s: %w",
				rel,
				err,
			)
		}
		if err := os.WriteFile(abs, []byte(files[rel]), 0o644); err != nil {
			return created, skipped, fmt.Errorf("failed to write %s: %w", rel, err)
		}
		if exists {
			output.Yellow.Fprintf(os.Stderr, "  overwrote: %s\n", rel)
		} else {
			output.Green.Fprintf(os.Stderr, "  created:   %s\n", rel)
		}
		created++
	}
	return created, skipped, nil
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

// getInitFilesFromFlake evaluates initFiles from a stackpanel flake reference.
// The flakeRef can be:
//   - "github:darkmatter/stackpanel" (default, from GitHub)
//   - "path:/local/path/to/stackpanel" (for local development)
//   - "git+file:///local/path/to/stackpanel" (faster local, uses git filtering)
//   - Any valid Nix flake reference
//
// "path:" references are automatically converted to "git+file://" for better
// performance (uses git to filter files instead of copying everything).
func getInitFilesFromFlake(
	ctx context.Context,
	flakeRef string,
	template string,
) (map[string]string, error) {
	return nixeval.GetInitFilesFromFlakeTemplate(ctx, normalizeFlakeRef(flakeRef), template)
}

// normalizeFlakeRef converts "path:" references to "git+file://" for better
// performance (git filters files instead of copying everything). Other
// reference forms are returned unchanged.
func normalizeFlakeRef(flakeRef string) string {
	if strings.HasPrefix(flakeRef, "path:") {
		return "git+file://" + strings.TrimPrefix(flakeRef, "path:")
	}
	return flakeRef
}

func initTargetDir(ctx context.Context, tmp bool, dryRun bool) (string, error) {
	if !tmp {
		targetDir, err := os.Getwd()
		if err != nil {
			return "", fmt.Errorf("failed to get current directory: %w", err)
		}
		return targetDir, nil
	}
	if dryRun {
		return "", fmt.Errorf("--tmp cannot be combined with --dry-run")
	}
	return createTmpInitTarget(ctx)
}

func createTmpInitTarget(ctx context.Context) (string, error) {
	targetDir, err := os.MkdirTemp("", "stackpanel-init-*")
	if err != nil {
		return "", fmt.Errorf("failed to create temporary init directory: %w", err)
	}

	cmd := exec.CommandContext(ctx, "git", "init", targetDir)
	if output, err := cmd.CombinedOutput(); err != nil {
		_ = os.RemoveAll(targetDir)
		return "", fmt.Errorf(
			"failed to initialize git repository: %w\n%s",
			err,
			string(output),
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
