package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
	"github.com/spf13/cobra"
)

// setupStageTimeout only guards against a hung process: a first devshell
// build or a long agent turn can legitimately take many minutes.
const setupStageTimeout = time.Hour

const (
	maxPlanReviews = 8 // plan revisions before setup gives up
	maxRepairs     = 1 // repair turns after doctor finds problems
)

// agentSetupRun carries one `stack setup --experimental-agent` invocation
// through the manifest stages. Each stage change is saved, so a rerun resumes
// where this one stopped.
type agentSetupRun struct {
	ctx         context.Context
	cmd         *cobra.Command
	opts        setupFlags
	interactive bool
	ui          *tui.SetupUI
	state       *setupManifest
	resuming    bool
	// request aliases state.Request, so answers are saved with the manifest.
	request  *setupagent.SetupRequest
	template setupTemplate
	newFiles *setupNewFiles
	debug    io.Writer
	// The agent is resolved on first use: re-verifying a resumed setup needs none.
	agent      setupagent.Agent
	agentReady bool
}

// setupTemplate is the part of request.Context the host itself uses.
type setupTemplate struct {
	Files  map[string]string   `json:"templateFiles"`
	Addons []nixeval.AddonSpec `json:"addons"`
}

// runAgentSetup resumes saved progress; only a fresh doctor run verifies it.
func runAgentSetup(cmd *cobra.Command, opts setupFlags) (retErr error) {
	switch opts.experimentalAgent {
	case "auto", "codex", "claude", "pi":
	default:
		return fmt.Errorf("unknown --experimental-agent %q: use auto, codex, claude, or pi", opts.experimentalAgent)
	}
	if len(opts.only) > 0 || len(opts.skip) > 0 || opts.reconsider {
		return errors.New("--experimental-agent cannot be combined with --only, --skip or --reconsider")
	}
	if opts.agentModel != "" && opts.experimentalAgent != "pi" && opts.experimentalAgent != "auto" {
		return errors.New("--agent-model requires --experimental-agent=pi")
	}
	originalContext := cmd.Context()
	defer cmd.SetContext(originalContext)
	ctx, stop := signal.NotifyContext(originalContext, os.Interrupt, syscall.SIGTERM)
	defer stop()
	noTUI, _ := cmd.Flags().GetBool("no-tui")
	daemon, _ := cmd.Flags().GetBool("daemon")
	interactive := tui.IsInteractiveStdio() && !opts.yes && !opts.nonInteractive && !noTUI && !daemon
	ui := tui.NewSetupUI(ctx, interactive, cmd.ErrOrStderr())
	defer ui.Close()
	ctx = ui.Context()
	cmd.SetContext(ctx)

	state, release, resuming, err := openSetupManifest(ctx, opts)
	if err != nil {
		return err
	}
	defer release()
	defer state.recordOutcome(&retErr)
	r := &agentSetupRun{ctx: ctx, cmd: cmd, opts: opts, interactive: interactive, ui: ui, state: state, resuming: resuming, debug: io.Discard}
	if resuming {
		r.resume()
	}
	ui.Progress("Setup manifest: " + state.path)
	if err := r.preflightPi(); err != nil {
		return err
	}
	if r.newFiles, err = newSetupFiles(ctx, state); err != nil {
		return err
	}
	ui.Identify(state.Root, state.Agent)
	if err := r.prepareRequest(); err != nil {
		return err
	}
	closeLog, err := r.openAgentLog()
	if err != nil {
		return err
	}
	defer closeLog()
	if err := r.agreePlan(); err != nil {
		return err
	}
	return r.applyAndVerify()
}

func (r *agentSetupRun) resume() {
	if changed := r.state.restoreOptions(r.cmd, &r.opts); changed != "" {
		r.ui.Progress(fmt.Sprintf("--%s differs from the saved setup; starting a new plan.", changed))
		r.state.restart(r.opts)
		r.resuming = false
		return
	}
	r.ui.Progress(fmt.Sprintf("Resuming %s · %d saved answers\n%s", r.state.Stage, len(r.state.Request.Answers), r.state.Root))
	// The user may have fixed a failed or finished setup since; check the
	// current files before spending another agent turn.
	switch r.state.Stage {
	case stageRepair, stageRuntime, stageComplete:
		r.state.Stage = stageVerify
	}
}

// A model selection implies Pi. Its API key is checked before anything is
// written when the next stage needs a model turn.
func (r *agentSetupRun) preflightPi() error {
	if r.opts.experimentalAgent == "auto" && r.opts.agentModel != "" {
		r.opts.experimentalAgent = "pi"
	}
	if r.opts.experimentalAgent == "pi" && (r.state.Stage == stageInspection || r.state.Stage == stageApply) {
		return r.loadPiAgent()
	}
	return nil
}

func (r *agentSetupRun) loadPiAgent() error {
	if r.agent.ID != "" {
		return nil
	}
	agent, err := setupagent.NewPiAgent(r.opts.agentModel)
	if err != nil {
		return err
	}
	r.agent = agent
	return nil
}

// ensureAgent resolves the coding agent before its first turn.
func (r *agentSetupRun) ensureAgent() error {
	if r.agentReady {
		return nil
	}
	if r.opts.experimentalAgent == "pi" {
		if err := r.loadPiAgent(); err != nil {
			return err
		}
	}
	r.ui.Stage(tui.SetupInspect, "Loading the pinned Stackpanel configuration schema…")
	if err := ensureSetupOptionContext(r.ctx, r.request); err != nil {
		return err
	}
	if r.agent.ID == "" {
		r.ui.Stage(tui.SetupInspect, "Finding available coding agents…")
		agent, err := selectSetupAgent(r.ctx, r.opts.experimentalAgent, r.interactive, r.ui)
		if err != nil {
			return err
		}
		r.agent = agent
	}
	r.state.Agent = r.agent.ID
	r.agentReady = true
	r.ui.Identify(r.state.Root, r.agent.ID)
	if r.agent.ID == "pi" {
		r.ui.Progress("Pi · " + r.opts.agentModel + " · direct API (metered usage)")
	}
	return r.state.save()
}

// prepareRequest loads the pinned template once per manifest and refreshes
// the fields that describe this invocation.
func (r *agentSetupRun) prepareRequest() error {
	state := r.state
	if state.Request.Context == "" {
		r.ui.Stage(tui.SetupInspect, "Loading the Stackpanel template…")
		var err error
		if state.Request, err = prepareSetupRequest(r.ctx, state.Root, r.opts); err != nil {
			return err
		}
	}
	r.request = &state.Request
	// Use this binary even if the one that started the setup was garbage
	// collected; the template and pinned inputs stay as saved.
	executable, err := currentStackExecutable()
	if err != nil {
		return err
	}
	r.request.StackExecutable = executable
	r.request.Resuming = r.resuming
	r.request.PreviousError = state.LastError
	if err := json.Unmarshal([]byte(r.request.Context), &r.template); err != nil {
		return fmt.Errorf("read saved template: %w", err)
	}
	// Report unknown addon flags before any agent turn.
	if _, err := setupAgentExpectations(reconcile.Expectations{Version: 1}, r.opts, r.template.Addons); err != nil {
		return err
	}
	return state.save()
}

// openAgentLog sends raw agent and Nix output to --agent-log. A resumed run
// writes a new sibling log instead of overwriting the previous one.
func (r *agentSetupRun) openAgentLog() (func(), error) {
	if r.opts.agentLog == "" {
		return func() {}, nil
	}
	file, err := os.OpenFile(r.opts.agentLog, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if r.resuming && os.IsExist(err) {
		file, err = os.CreateTemp(filepath.Dir(r.opts.agentLog), filepath.Base(r.opts.agentLog)+".resume-*.jsonl")
	}
	if err != nil {
		return nil, err
	}
	r.ui.Progress("Agent diagnostics: " + file.Name())
	r.debug = file
	return func() { file.Close() }, nil
}

// agreePlan alternates inspection and review until the user accepts a plan.
// Asking for changes queues a question whose answer the next inspection gets.
func (r *agentSetupRun) agreePlan() error {
	state := r.state
	for review := 0; state.Stage == stageInspection || state.Stage == stageReview; review++ {
		if review == maxPlanReviews {
			return errors.New("plan revision limit reached")
		}
		if state.Plan == nil {
			if err := r.inspect(); err != nil {
				return err
			}
		}
		decision, err := r.ui.ReviewPlan(renderSetupPlan(state.Plan, r.opts))
		if err != nil {
			return err
		}
		switch decision {
		case "Cancel":
			return context.Canceled
		case "Apply":
			state.Stage = stageApply
		default:
			state.Pending = []setupagent.Question{{ID: fmt.Sprintf("revision-%d", len(state.Conversation)), Prompt: "What should change in the plan?", Kind: "text", Required: true}}
			state.Plan, state.Stage = nil, stageInspection
		}
		if err := state.save(); err != nil {
			return err
		}
	}
	return nil
}

// inspect asks the agent for a plan in a read-only turn.
func (r *agentSetupRun) inspect() error {
	if err := r.ensureAgent(); err != nil {
		return err
	}
	r.ui.Stage(tui.SetupInspect, "Getting to know your repository…")
	reply, err := runAgentPhase(r.ctx, r.agent, r.request, setupagent.Inspection, nil, "", r.ui, r.debug, r.state)
	if err != nil {
		return err
	}
	plan := reply.Plan
	var supported []string
	for _, name := range plan.Services {
		if services.Get(name) == nil {
			r.ui.Warning(fmt.Sprintf("Leaving out service %q: Stackpanel does not support it.", name))
			continue
		}
		supported = append(supported, name)
	}
	plan.Services = supported
	// Flag choices become checks of their own, whatever the agent planned.
	if plan.Expectations, err = setupAgentExpectations(plan.Expectations, r.opts, r.template.Addons); err != nil {
		return err
	}
	r.state.Plan, r.state.Stage = plan, stageReview
	return r.state.save()
}

// applyAndVerify makes the agreed changes, then checks them with doctor. When
// doctor finds problems, the agent gets one repair turn with its findings.
func (r *agentSetupRun) applyAndVerify() error {
	state := r.state
	work, err := os.MkdirTemp("", "stackpanel-agent-setup-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)
	for repairs := 0; ; repairs++ {
		if state.Stage == stageApply || state.Stage == stageRepair {
			if err := r.apply(state.Plan); err != nil {
				return err
			}
		}
		report, verifyErr := r.verify(state.Plan, work)
		if r.ctx.Err() != nil {
			return r.ctx.Err()
		}
		problems := doctorProblems(report)
		if verifyErr == nil && len(problems) == 0 {
			return r.finish(report, nil)
		}
		failure := strings.Join(problems, "\n")
		if verifyErr != nil {
			failure = verifyErr.Error()
		}
		r.ui.Activity(failure)
		if repairs == maxRepairs {
			if verifyErr != nil {
				return fmt.Errorf("setup still fails after a repair turn: %w", verifyErr)
			}
			return r.finish(report, problems)
		}
		r.ui.Progress("The check found problems; the agent gets one turn to fix them.")
		state.Failure, state.Stage = failure, stageRepair
		if err := state.save(); err != nil {
			return err
		}
	}
}

// apply runs the write phase, or the repair phase after a failed check, on top
// of any template files that are still missing.
func (r *agentSetupRun) apply(plan *setupagent.Plan) error {
	if err := r.ensureAgent(); err != nil {
		return err
	}
	phase, message := setupagent.Setup, "Making the agreed changes…"
	if r.state.Stage == stageRepair {
		phase, message = setupagent.Repair, "Fixing the problems doctor found · repair 1 of 1"
	}
	r.ui.Stage(tui.SetupApply, message)
	if _, _, _, err := reconcile.WriteScaffold(r.state.Root, r.template.Files, false); err != nil {
		return fmt.Errorf("write template files: %w", err)
	}
	if _, err := runAgentPhase(r.ctx, r.agent, r.request, phase, plan, r.state.Failure, r.ui, r.debug, r.state); err != nil {
		return err
	}
	r.state.Stage = stageVerify
	return r.state.save()
}

// verify checks the repository the way the user will use it: in a fresh
// devshell, after generation and the plan's prepare commands, with doctor. An
// error means a step before doctor failed or doctor produced no report.
func (r *agentSetupRun) verify(plan *setupagent.Plan, work string) (*reconcile.Report, error) {
	root, executable := r.state.Root, r.request.StackExecutable
	expose := func() error { return r.newFiles.expose(r.ctx, plan.Expectations.Files) }
	if err := expose(); err != nil {
		return nil, err
	}
	r.ui.Stage(tui.SetupVerify, "Entering the devshell and generating files…")
	if err := runFreshReconciliation(r.ctx, root, executable, r.debug); err != nil {
		return nil, fmt.Errorf("devshell or file generation failed: %w", err)
	}
	// Locking and generation create files Nix reads, too.
	if err := expose(); err != nil {
		return nil, err
	}
	for _, step := range plan.Prepare {
		r.ui.Progress(fmt.Sprintf("Preparing %s · %s", step.ID, setupCommandLabel(step.Argv)))
		if err := runSetupPrepare(r.ctx, root, step, r.debug); err != nil {
			return nil, fmt.Errorf("prepare command %s failed: %w", step.ID, err)
		}
	}
	if err := expose(); err != nil {
		return nil, err
	}
	expectations, err := json.Marshal(plan.Expectations)
	if err != nil {
		return nil, err
	}
	path := filepath.Join(work, "expectations.json")
	if err := os.WriteFile(path, expectations, 0o600); err != nil {
		return nil, err
	}
	r.ui.Progress("Checking the setup with stack doctor…")
	return runFreshDoctor(r.ctx, root, executable, r.debug, "--strict", "--scope", "repo,build", "--build", "--expectations", path, "--json")
}

// finish starts the local runtime and Studio unless --no-runtime was given.
// Problems doctor still reports after the repair turn are shown, not fatal: the
// changes are in place, and rerunning setup checks them again.
func (r *agentSetupRun) finish(report *reconcile.Report, problems []string) error {
	state := r.state
	state.Failure, state.Stage = "", stageRuntime
	if err := state.save(); err != nil {
		return err
	}
	headline := "Repository set up and verified by stack doctor."
	if len(problems) == 0 {
		r.ui.Verified(fmt.Sprintf("Repository · %d doctor checks passed", countPassedChecks(report)))
	} else {
		headline = fmt.Sprintf("Repository set up, but stack doctor still reports:\n  %s\nFix these, then rerun this command to check again.", strings.Join(problems, "\n  "))
		r.ui.Warning(fmt.Sprintf("stack doctor still reports %d problem(s); continuing.", len(problems)))
	}
	runtime := "Runtime and Studio skipped (--no-runtime)."
	if !r.opts.noRuntime {
		var err error
		if runtime, err = runSetupRuntime(r.ctx, state.Root, r.request.StackExecutable, state.Plan.Services, r.opts, r.ui, r.debug, state); err != nil {
			return fmt.Errorf("repository set up; runtime setup incomplete: %w", err)
		}
	}
	state.Stage = stageComplete
	if err := state.save(); err != nil {
		return err
	}
	if len(problems) == 0 {
		r.ui.ShowResult(headline + "\n" + runtime)
	} else {
		r.ui.ShowWarningResult(headline + "\n" + runtime)
	}
	if r.opts.tmp {
		fmt.Fprintln(r.cmd.OutOrStdout(), state.Root)
	}
	return nil
}

func countPassedChecks(report *reconcile.Report) int {
	passed := 0
	for _, check := range report.CheckResults {
		if check.Status == "pass" {
			passed++
		}
	}
	return passed
}

// doctorProblems lists doctor's errors. Checks doctor skipped are left out:
// they cannot run here, and no change to the repository would make them pass.
func doctorProblems(report *reconcile.Report) []string {
	if report == nil {
		return nil
	}
	skipped := map[string]bool{}
	for _, result := range report.CheckResults {
		if result.Status == "skipped" {
			skipped[result.ID] = true
		}
	}
	var problems []string
	for _, e := range report.Errors {
		problems = append(problems, e.Reconciler+": "+e.Err)
	}
	for _, f := range report.Findings {
		check := strings.TrimPrefix(strings.TrimPrefix(f.ID, "strict:check:"), "check:")
		if f.Severity != reconcile.SeverityError || (check != f.ID && skipped[check]) {
			continue
		}
		problem := f.Title
		if f.Detail != "" {
			problem += ": " + f.Detail
		}
		problems = append(problems, problem)
	}
	return problems
}

func selectSetupAgent(ctx context.Context, requested string, interactive bool, ui *tui.SetupUI) (setupagent.Agent, error) {
	var available []setupagent.Agent
	var unusable []string
	for _, agent := range setupagent.Discover() {
		if requested != "auto" && requested != agent.ID {
			continue
		}
		if err := setupagent.Probe(ctx, agent); err != nil {
			unusable = append(unusable, err.Error())
			ui.Activity(err.Error())
			continue
		}
		available = append(available, agent)
	}
	if len(available) == 0 {
		message := fmt.Sprintf("no usable coding agent found for %q on PATH; install and sign in to codex or claude, or use --experimental-agent=pi", requested)
		if len(unusable) > 0 {
			message += "\n" + strings.Join(unusable, "\n")
		}
		return setupagent.Agent{}, errors.New(message)
	}
	if len(available) == 1 || !interactive {
		return available[0], nil
	}
	labels := make([]string, len(available))
	for i, agent := range available {
		labels[i] = agent.ID
		ui.Activity(fmt.Sprintf("%s · %s", agent.ID, agent.Path))
	}
	selected, err := ui.Ask("Which coding agent would you like to use?", "single", labels, labels[:1], true)
	if err != nil {
		return setupagent.Agent{}, err
	}
	for i, label := range labels {
		if len(selected) == 1 && label == selected[0] {
			return available[i], nil
		}
	}
	return setupagent.Agent{}, errors.New("no agent selected")
}

func currentStackExecutable() (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.EvalSymlinks(executable)
}

func prepareSetupRequest(ctx context.Context, root string, opts setupFlags) (setupagent.SetupRequest, error) {
	request := setupagent.SetupRequest{Root: root, Template: opts.template, Mode: "existing"}
	if opts.newDir != "" || opts.tmp {
		request.Mode = "new"
	}
	if request.Template == "" {
		request.Template = "default"
	}
	var err error
	if request.StackExecutable, err = currentStackExecutable(); err != nil {
		return request, err
	}
	flake := reconcile.NormalizeFlakeRef(resolveAgentSetupFlake(opts.flake))
	nctx, cancel := context.WithTimeout(ctx, setupStageTimeout)
	defer cancel()
	metadata := exec.CommandContext(nctx, "nix", "flake", "metadata", "--json", "--no-write-lock-file", flake)
	metadata.Dir = root
	metadata.Env = freshSetupEnvironment(os.Environ())
	var stderr bytes.Buffer
	metadata.Stderr = &stderr
	data, err := metadata.Output()
	if err != nil {
		return request, fmt.Errorf("resolve Stackpanel flake: %w\n%s", err, stderr.String())
	}
	var resolved struct {
		URL    string `json:"url"`
		Path   string `json:"path"`
		Locked struct {
			Rev string `json:"rev"`
		} `json:"locked"`
	}
	if err := json.Unmarshal(data, &resolved); err != nil {
		return request, fmt.Errorf("read flake metadata: %w", err)
	}
	request.FlakeRef = resolved.URL
	request.InspectionRef = resolved.URL
	if resolved.Locked.Rev == "" && strings.HasPrefix(resolved.URL, "git+file://") {
		return request, errors.New("local framework checkout has uncommitted changes; omit --flake to use the committed framework, or select a Git revision with --flake 'git+file:///path/to/stackpanel?rev=<commit>'. A raw directory input would copy ignored local state into the Nix store")
	}
	if resolved.Locked.Rev == "" {
		// Non-Git sources may have no revision URL. Nix's source snapshot
		// is immutable; leave its absolute path unprefixed because
		// ordinary setup normalizes path: references to Git references.
		request.InspectionRef = resolved.Path
		request.FlakeRef = flake
	}
	if request.FlakeRef == "" || request.InspectionRef == "" {
		return request, errors.New("flake metadata has no immutable source reference")
	}
	files, err := nixeval.GetInitFilesFromFlakeTemplate(nctx, request.InspectionRef, request.Template)
	if err != nil {
		return request, err
	}
	addons, err := nixeval.GetInitAddonsFromFlake(nctx, request.InspectionRef)
	if err != nil {
		return request, err
	}
	brief, err := json.Marshal(struct {
		Files    map[string]string   `json:"templateFiles"`
		Services []string            `json:"availableServices"`
		Addons   []nixeval.AddonSpec `json:"addons"`
	}{files, services.Names(), addons})
	if err != nil {
		return request, err
	}
	request.Context = string(brief)
	constraints, err := json.Marshal(struct {
		With    []string `json:"with"`
		Without []string `json:"without"`
		Values  []string `json:"addonValues"`
		Force   bool     `json:"force"`
	}{opts.with, opts.without, opts.addonValues, opts.force})
	if err != nil {
		return request, err
	}
	request.Constraints = string(constraints)
	return request, nil
}

// STACKPANEL_ROOT identifies the caller's project, which may be a consumer with
// no framework template exports. Only explicit source overrides apply here.
func resolveAgentSetupFlake(flag string) string {
	if flag != "" {
		return flag
	}
	if ref := os.Getenv("STACKPANEL_FLAKE"); ref != "" {
		return ref
	}
	return defaultStackpanelFlake
}

// freshSetupEnvironment prevents a caller's devshell from impersonating the
// target generation. CLI authentication and the user's Nix settings survive.
func freshSetupEnvironment(env []string) []string {
	clean := make([]string, 0, len(env))
	for _, value := range env {
		key, _, _ := strings.Cut(value, "=")
		if (strings.HasPrefix(key, "STACKPANEL_") && key != "STACKPANEL_USER_CONFIG") || strings.HasPrefix(key, "__STACKPANEL_") ||
			strings.HasPrefix(key, "DIRENV_") || key == "IN_NIX_SHELL" || key == "PWD" || key == "OLDPWD" {
			continue
		}
		clean = append(clean, value)
	}
	return clean
}

func runFreshReconciliation(ctx context.Context, root, stackExecutable string, out io.Writer) error {
	return runSetupShell(ctx, root, out, stackExecutable, "setup", "--yes", "--only", "codegen,files,fileops")
}

// runSetupPrepare runs one plan-approved command unchanged in a fresh devshell,
// like doctor's acceptance commands. Setup owns it so doctor stays a verifier.
func runSetupPrepare(ctx context.Context, root string, step setupagent.PrepareCommand, out io.Writer) error {
	dir, err := reconcile.AcceptancePath(root, step.Dir)
	if err != nil {
		return err
	}
	// The directory is a positional argument, never interpolated into shell code.
	args := []string{"bash", "--noprofile", "--norc", "-c", `cd -- "$1" && shift && exec "$@"`, "stackpanel-prepare", dir}
	return runSetupShell(ctx, root, out, append(args, step.Argv...)...)
}

// runFreshDoctor runs this binary's doctor in a fresh devshell and returns its
// report. An error means doctor produced no report; what doctor found is in
// the report.
func runFreshDoctor(ctx context.Context, root, stackExecutable string, out io.Writer, doctorArgs ...string) (*reconcile.Report, error) {
	reportFile, err := os.CreateTemp("", "stackpanel-doctor-*.json")
	if err != nil {
		return nil, err
	}
	path := reportFile.Name()
	defer os.Remove(path)
	if err := reportFile.Close(); err != nil {
		return nil, err
	}
	// All paths are positional arguments, never interpolated into shell code.
	args := []string{"bash", "--noprofile", "--norc", "-c",
		`report=$1; shift; exec "$@" > "$report"`, "stackpanel-doctor", path,
		stackExecutable, "doctor"}
	// Doctor exits nonzero when it finds problems, so the report decides.
	runErr := runSetupShell(ctx, root, out, append(args, doctorArgs...)...)
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var report reconcile.Report
	if err := json.Unmarshal(data, &report); err != nil {
		if runErr != nil {
			return nil, runErr
		}
		return nil, fmt.Errorf("doctor did not produce a report: %w", err)
	}
	return &report, nil
}

// runSetupShell runs a command in the repository's devshell. Nix creates or
// extends flake.lock as needed, as it does when the user enters the shell.
func runSetupShell(ctx context.Context, root string, out io.Writer, args ...string) error {
	return runSetupProcess(ctx, root, out, "nix", append([]string{"develop", ".", "--command"}, args...)...)
}

func runSetupProcess(ctx context.Context, root string, out io.Writer, executable string, args ...string) error {
	sctx, cancel := context.WithTimeout(ctx, setupStageTimeout)
	defer cancel()
	cmd := exec.CommandContext(sctx, executable, args...)
	cmd.Dir = root
	cmd.Env = freshSetupEnvironment(os.Environ())
	tail := &setupLogTail{}
	log := io.MultiWriter(out, tail)
	cmd.Stdout, cmd.Stderr = log, log
	// Nix and agent processes can leave grandchildren holding pipes open.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = time.Second
	if err := cmd.Run(); err != nil {
		if sctx.Err() != nil {
			return sctx.Err()
		}
		return fmt.Errorf("%s: %w\n%s", executable, err, tail.data)
	}
	return nil
}

// Only retain a bounded diagnostic tail to include in a repair prompt.
type setupLogTail struct{ data []byte }

func (b *setupLogTail) Write(p []byte) (int, error) {
	const limit = 32 * 1024
	n := len(p)
	if n >= limit {
		b.data = append(b.data[:0], p[n-limit:]...)
	} else {
		if len(b.data)+n > limit {
			b.data = b.data[len(b.data)+n-limit:]
		}
		b.data = append(b.data, p...)
	}
	return n, nil
}
