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

const setupStageTimeout = 15 * time.Minute

// runAgentSetup resumes host checkpoints; only fresh doctor results prove success.
func runAgentSetup(cmd *cobra.Command, opts setupFlags) (retErr error) {
	originalContext := cmd.Context()
	ctx, stop := signal.NotifyContext(originalContext, os.Interrupt, syscall.SIGTERM)
	defer stop()
	cmd.SetContext(ctx)
	defer cmd.SetContext(originalContext)
	if len(opts.only) > 0 || len(opts.skip) > 0 || opts.reconsider {
		return errors.New("--experimental-agent cannot be combined with --only, --skip or --reconsider")
	}
	noTUI, _ := cmd.Flags().GetBool("no-tui")
	daemon, _ := cmd.Flags().GetBool("daemon")
	interactive := tui.IsInteractiveStdio() && !opts.yes && !opts.nonInteractive && !noTUI && !daemon
	ui := tui.NewSetupUI(cmd.Context(), interactive, cmd.ErrOrStderr())
	defer ui.Close()
	cmd.SetContext(ui.Context())
	state, release, resuming, err := openSetupManifest(cmd.Context(), opts)
	if err != nil {
		return err
	}
	defer release()
	defer func() {
		state.LastError = ""
		if retErr != nil {
			state.LastError = retErr.Error()
		}
		retErr = errors.Join(retErr, state.save())
		if retErr != nil {
			retErr = fmt.Errorf("%w\nSetup saved for %s\nRerun the same command to resume. Manifest: %s", retErr, state.Root, state.path)
		}
	}()
	if resuming {
		if err := state.restoreOptions(cmd, &opts); err != nil {
			return err
		}
		if err := state.checkGitViolation(cmd.Context()); err != nil {
			return err
		}
		ui.Progress(fmt.Sprintf("Resuming %s · %d saved answers\n%s", state.Stage, len(state.Request.Answers), state.Root))
		// A failed repair or previously verified runtime may have been fixed by
		// the user. Check current files before spending another model turn.
		if state.Stage == "repair" || state.Stage == "runtime" || state.Stage == "complete" {
			state.Stage = "verify"
		}
	}
	ui.Progress("Setup manifest: " + state.path)
	var agent setupagent.Agent
	ensureCodingAgent := func() error {
		if agent.Path != "" {
			return nil
		}
		ui.Stage(tui.SetupInspect, "Loading the pinned Stackpanel configuration schema…")
		if err := ensureSetupOptionContext(cmd.Context(), &state.Request); err != nil {
			return err
		}
		ui.Stage(tui.SetupInspect, "Finding available coding agents…")
		var err error
		agent, err = selectSetupAgent(cmd.Context(), opts.experimentalAgent, interactive, ui)
		if err != nil {
			return err
		}
		state.Agent = agent.ID
		ui.Identify(state.Root, agent.ID)
		return state.save()
	}
	root := state.Root
	gitGuard, err := captureSetupGit(cmd.Context(), root)
	if err != nil {
		return err
	}
	if resuming {
		state.restoreGit(gitGuard)
	}
	keepNixInputs := false
	defer func() {
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		guardErr := gitGuard.Check(cleanupCtx)
		retErr = errors.Join(retErr, guardErr)
		if guardErr != nil && gitGuard.root != "" {
			state.GitViolation = &setupGitCheckpoint{Root: gitGuard.root, Head: gitGuard.head, Index: gitGuard.index, Protected: gitGuard.protected}
		}
		if !keepNixInputs || guardErr != nil {
			retErr = errors.Join(retErr, gitGuard.Close(cleanupCtx))
		}
		// This also records partial agent output on cancellation or CLI errors.
		if guardErr == nil {
			retErr = errors.Join(retErr, state.checkpoint(cleanupCtx, gitGuard))
		}
	}()
	ui.Identify(root, state.Agent)
	if state.Request.Context == "" {
		ui.Stage(tui.SetupInspect, "Loading the Stackpanel template…")
		state.Request, err = prepareSetupRequest(cmd.Context(), root, opts)
		if err != nil {
			return err
		}
	}
	request := &state.Request
	// Use this invocation's binary even if the previously used Nix build has
	// been garbage collected; retain the original template and pinned inputs.
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	request.StackExecutable, err = filepath.EvalSymlinks(executable)
	if err != nil {
		return err
	}
	request.Resuming = resuming
	request.PreviousError = state.LastError
	request.ProtectedPaths = nil
	for _, path := range sortedKeys(gitGuard.protected) {
		rel, err := filepath.Rel(root, filepath.Join(gitGuard.root, path))
		if err == nil && filepath.IsLocal(rel) {
			request.ProtectedPaths = append(request.ProtectedPaths, rel)
		}
	}
	var metadata struct {
		Files  map[string]string   `json:"templateFiles"`
		Addons []nixeval.AddonSpec `json:"addons"`
	}
	if err := json.Unmarshal([]byte(request.Context), &metadata); err != nil {
		return err
	}
	if _, err := setupAgentExpectations(reconcile.Expectations{Version: 1}, opts, metadata.Addons); err != nil {
		return err
	}
	if err := state.checkpoint(cmd.Context(), gitGuard); err != nil {
		return err
	}
	var debug io.Writer = io.Discard
	if opts.agentLog != "" {
		file, err := os.OpenFile(opts.agentLog, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if resuming && os.IsExist(err) {
			file, err = os.CreateTemp(filepath.Dir(opts.agentLog), filepath.Base(opts.agentLog)+".resume-*.jsonl")
		}
		if err != nil {
			return err
		}
		defer file.Close()
		ui.Progress("Agent diagnostics: " + file.Name())
		debug = file
	}
	for review := 0; state.Stage == "inspection" || state.Stage == "review"; review++ {
		if review == 8 {
			return errors.New("plan revision limit reached")
		}
		if state.Plan == nil {
			if err := ensureCodingAgent(); err != nil {
				return err
			}
			ui.Stage(tui.SetupInspect, "Getting to know your repository…")
			reply, err := runAgentPhase(cmd.Context(), agent, request, setupagent.Inspection, nil, "", ui, debug, state)
			if err != nil {
				return err
			}
			if reply.Status != "plan" {
				return fmt.Errorf("inspection did not return a plan: %s", reply.Summary)
			}
			plan := reply.Plan
			for _, name := range plan.Services {
				if services.Get(name) == nil {
					return fmt.Errorf("unsupported service in plan: %s", name)
				}
			}
			plan.Expectations, err = setupAgentExpectations(plan.Expectations, opts, metadata.Addons)
			if err != nil {
				return err
			}
			if request.Mode == "new" && (len(plan.Expectations.Files) == 0 || len(plan.Expectations.Commands) == 0) {
				return errors.New("new repository plan requires source files and build/test acceptance commands")
			}
			state.Plan, state.Stage = plan, "review"
			if err := state.checkpoint(cmd.Context(), gitGuard); err != nil {
				return err
			}
		}
		decision, err := ui.ReviewPlan(renderSetupPlan(state.Plan, opts))
		if err != nil {
			return err
		}
		if decision == "Cancel" {
			return context.Canceled
		}
		if decision == "Apply" {
			state.Stage = "apply"
		} else {
			state.Pending = []setupagent.Question{{ID: fmt.Sprintf("revision-%d", len(state.Conversation)), Prompt: "What should change in the plan?", Kind: "text", Required: true}}
			state.Plan, state.Stage = nil, "inspection"
		}
		if err := state.save(); err != nil {
			return err
		}
	}
	plan := state.Plan
	work, err := os.MkdirTemp("", "stackpanel-agent-setup-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)
	for repairs := 0; ; {
		if state.Stage == "apply" || state.Stage == "repair" {
			if err := ensureCodingAgent(); err != nil {
				return err
			}
			phase := setupagent.Setup
			ui.Stage(tui.SetupApply, "Continuing your agreed files and configuration…")
			if state.Stage == "repair" {
				phase = setupagent.Repair
				ui.Stage(tui.SetupApply, "Addressing verification findings · repair 1 of 1")
			}
			if _, _, _, err := reconcile.WriteScaffold(root, metadata.Files, false); err != nil {
				return fmt.Errorf("prepare onboarding scaffold: %w", err)
			}
			if err := state.checkpoint(cmd.Context(), gitGuard); err != nil {
				return err
			}
			if _, err := runAgentPhase(cmd.Context(), agent, request, phase, plan, state.Failure, ui, debug, state); err != nil {
				return err
			}
			state.Stage = "verify"
			if err := state.checkpoint(cmd.Context(), gitGuard); err != nil {
				return err
			}
		}
		report, verifyErr := verifyAgentSetup(cmd.Context(), root, work, request.StackExecutable, plan, gitGuard, ui, debug, state)
		failure := ""
		if report != nil {
			var rendered bytes.Buffer
			report.Render(&rendered, reconcile.RenderOptions{Title: "stack doctor · onboarding verification", Verbose: true})
			ui.Activity(rendered.String())
			failure = rendered.String()
			data, err := report.JSON()
			if err != nil {
				return err
			}
			state.Failure = string(data)
			retainSetupChecks(&plan.Expectations, report)
		}
		if verifyErr != nil {
			if cmd.Context().Err() != nil {
				return cmd.Context().Err()
			}
			state.Failure += "\n" + verifyErr.Error()
			state.Stage = "repair"
			if err := state.checkpoint(cmd.Context(), gitGuard); err != nil {
				return err
			}
			if repairs == 1 {
				var findings *setupDoctorFindingsError
				if errors.As(verifyErr, &findings) {
					keepNixInputs = true
					ui.Warning("Repository setup has verification warnings. It remains unverified; runtime and Studio checks are pending.")
					quote := func(s string) string { return "'" + strings.ReplaceAll(s, "'", "'\"'\"'") + "'" }
					ui.ShowResult(fmt.Sprintf("Your files and choices are saved. Run doctor again without an agent:\n\ncd %s\nnix develop --command %s doctor --onboarding\n\nRerun the same setup command to resume repair and Studio setup.\nManifest: %s", quote(root), quote(request.StackExecutable), state.path))
					if opts.tmp {
						fmt.Fprintln(cmd.OutOrStdout(), root)
					}
					return nil
				}
				return fmt.Errorf("repository onboarding remains unverified after one repair attempt:\n%s\n%w", failure, verifyErr)
			}
			repairs++
			continue
		}
		state.Failure, state.Stage = "", "runtime"
		if err := state.checkpoint(cmd.Context(), gitGuard); err != nil {
			return err
		}
		keepNixInputs = true
		passed := 0
		for _, check := range report.CheckResults {
			if check.Status == "pass" {
				passed++
			}
		}
		ui.Verified(fmt.Sprintf("Repository · %d doctor checks passed", passed))
		summary := "Repository onboarding verified by stack doctor. Runtime and Studio unverified (--no-runtime)."
		if !opts.noRuntime {
			summary, err = runSetupRuntime(cmd.Context(), root, request.StackExecutable, plan.Services, opts, ui, debug, state)
			if err != nil {
				return fmt.Errorf("repository configured; runtime setup incomplete: %w", err)
			}
		}
		state.Stage = "complete"
		if err := state.checkpoint(cmd.Context(), gitGuard); err != nil {
			return err
		}
		ui.ShowResult(summary)
		if opts.tmp {
			fmt.Fprintln(cmd.OutOrStdout(), root)
		}
		return nil
	}
}

func verifyAgentSetup(ctx context.Context, root, work, executable string, plan *setupagent.Plan, guard *setupGitGuard, ui *tui.SetupUI, debug io.Writer, state *setupManifest) (*reconcile.Report, error) {
	if err := guard.AddNixInputs(ctx, plan.Expectations.Files...); err != nil {
		return nil, err
	}
	if err := state.checkpoint(ctx, guard); err != nil {
		return nil, err
	}
	ui.Progress("Resolving repository flake inputs with Nix…")
	if err := runSetupLock(ctx, root, work, guard, debug); err != nil {
		return nil, fmt.Errorf("flake locking failed: %w", err)
	}
	if err := guard.AddNixInputs(ctx, plan.Expectations.Files...); err != nil {
		return nil, err
	}
	if err := state.checkpoint(ctx, guard); err != nil {
		return nil, err
	}
	ui.Progress("Entering the repository devshell and reconciling generated files…")
	if err := runFreshReconciliation(ctx, root, executable, debug); err != nil {
		return nil, fmt.Errorf("fresh reconciliation failed: %w", err)
	}
	if err := guard.AddNixInputs(ctx, plan.Expectations.Files...); err != nil {
		return nil, err
	}
	if err := state.checkpoint(ctx, guard); err != nil {
		return nil, err
	}
	// Never trust a file the coding agent could have modified during its turn.
	frozen, err := json.Marshal(plan.Expectations)
	if err != nil {
		return nil, err
	}
	expectationsPath := filepath.Join(work, "expectations.json")
	if err := os.WriteFile(expectationsPath, frozen, 0o600); err != nil {
		return nil, err
	}
	ui.Stage(tui.SetupVerify, "Checking files, configuration, and build/test commands…")
	return runFreshDoctor(ctx, root, executable, expectationsPath, debug)
}

func retainSetupChecks(expected *reconcile.Expectations, report *reconcile.Report) {
	seen := make(map[string]bool, len(expected.RequiredChecks))
	for _, id := range expected.RequiredChecks {
		seen[id] = true
	}
	for _, check := range report.CheckResults {
		if check.ID != "" && check.Module != "onboarding" && !seen[check.ID] {
			expected.RequiredChecks = append(expected.RequiredChecks, check.ID)
			seen[check.ID] = true
		}
	}
}

func selectSetupAgent(ctx context.Context, requested string, interactive bool, ui *tui.SetupUI) (setupagent.Agent, error) {
	var available []setupagent.Agent
	var diagnostics []string
	for _, agent := range setupagent.Discover() {
		if requested != "auto" && requested != agent.ID {
			continue
		}
		caps, err := setupagent.Probe(ctx, agent)
		if err != nil {
			message := fmt.Sprintf("%s unavailable: %v", agent.ID, err)
			diagnostics = append(diagnostics, message)
			ui.Activity(message)
			continue
		}
		if !caps.ReadOnly || !caps.Write {
			message := fmt.Sprintf("%s unsupported: %s", agent.ID, caps.Reason)
			diagnostics = append(diagnostics, message)
			ui.Activity(message)
			continue
		}
		available = append(available, agent)
	}
	if len(available) == 0 {
		message := fmt.Sprintf("no supported agent found for %q on PATH; install/authenticate codex or claude, or use ordinary stack setup", requested)
		if len(diagnostics) > 0 {
			message += "\n" + strings.Join(diagnostics, "\n")
		}
		return setupagent.Agent{}, errors.New(message)
	}
	if len(available) == 1 {
		return available[0], nil
	}
	if !interactive {
		return setupagent.Agent{}, errors.New("multiple agents available: select one with --experimental-agent=codex or --experimental-agent=claude")
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

func prepareSetupRequest(ctx context.Context, root string, opts setupFlags) (setupagent.SetupRequest, error) {
	request := setupagent.SetupRequest{Root: root, Template: opts.template, Mode: "existing"}
	if opts.newDir != "" || opts.tmp {
		request.Mode = "new"
	}
	if request.Template == "" {
		request.Template = "default"
	}
	executable, err := os.Executable()
	if err != nil {
		return request, err
	}
	request.StackExecutable, err = filepath.EvalSymlinks(executable)
	if err != nil {
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

// runSetupLock owns the daemon-dependent operation. A separate output file
// prevents Nix from staging flake.lock and lets us preserve existing user edits.
func runSetupLock(ctx context.Context, root, work string, guard *setupGitGuard, out io.Writer) error {
	output := filepath.Join(work, "flake.lock")
	if err := os.Remove(output); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := runSetupProcess(ctx, root, out, "nix", "flake", "lock", ".", "--output-lock-file", output); err != nil {
		return err
	}
	data, err := os.ReadFile(output)
	if err != nil {
		return fmt.Errorf("read resolved flake lock: %w", err)
	}
	path := filepath.Join(root, "flake.lock")
	if current, err := os.ReadFile(path); err == nil && bytes.Equal(current, data) {
		return nil
	}
	if rel, err := filepath.Rel(guard.root, path); err == nil {
		if _, protected := guard.protected[rel]; protected {
			return errors.New("flake inputs require changing preexisting user edits in flake.lock; lock file was left unchanged")
		}
	}
	if info, err := os.Lstat(path); err == nil && !info.Mode().IsRegular() {
		return errors.New("refusing to replace a non-regular flake.lock")
	}
	return os.WriteFile(path, data, 0o644)
}

func runFreshDoctor(ctx context.Context, root, stackExecutable, expectationsPath string, out io.Writer) (*reconcile.Report, error) {
	return runFreshDoctorArgs(ctx, root, stackExecutable, out, []string{"--strict", "--scope", "repo,build", "--build", "--expectations", expectationsPath, "--json"}, []string{"codegen", "files", "fileops", "checks", "verification"})
}

// A completed diagnosis with findings is distinct from a broken verifier or
// failed Nix invocation. Setup may warn about findings; doctor still fails.
type setupDoctorFindingsError struct{}

func (*setupDoctorFindingsError) Error() string { return "doctor found errors or pending changes" }

func runFreshDoctorArgs(ctx context.Context, root, stackExecutable string, out io.Writer, doctorArgs, requiredIDs []string) (*reconcile.Report, error) {
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
	err = runSetupShell(ctx, root, out, append(args, doctorArgs...)...)
	data, readErr := os.ReadFile(path)
	if readErr != nil {
		return nil, readErr
	}
	var report reconcile.Report
	if parseErr := json.Unmarshal(data, &report); parseErr != nil {
		return nil, fmt.Errorf("doctor did not produce a valid report: %v (shell: %v)", parseErr, err)
	}
	// An older binary or an empty object must not be accepted as verification.
	for _, required := range requiredIDs {
		found := false
		for _, id := range report.Reconcilers {
			found = found || id == required
		}
		if !found {
			return &report, fmt.Errorf("doctor report omitted required reconciler %q", required)
		}
	}
	var exitErr *exec.ExitError
	if err != nil && (!errors.As(err, &exitErr) || exitErr.ExitCode() != 1) {
		return &report, err
	}
	report.EnforceStrict()
	if report.HasErrors() || report.HasChanges() {
		return &report, &setupDoctorFindingsError{}
	}
	if err != nil {
		return &report, err
	}
	return &report, nil
}

func runSetupShell(ctx context.Context, root string, out io.Writer, args ...string) error {
	if _, err := os.Stat(filepath.Join(root, "flake.lock")); err != nil {
		return fmt.Errorf("onboarding requires flake.lock before verification: %w", err)
	}
	nixArgs := append([]string{"develop", ".", "--no-update-lock-file", "--no-write-lock-file", "--command"}, args...)
	return runSetupProcess(ctx, root, out, "nix", nixArgs...)
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
