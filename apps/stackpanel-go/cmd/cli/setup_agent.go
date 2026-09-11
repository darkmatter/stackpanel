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

// runAgentSetup keeps the model's work separate from the authoritative doctor
// result. Expectations are accepted once and retained in memory through repair.
func runAgentSetup(cmd *cobra.Command, opts setupFlags) (retErr error) {
	originalContext := cmd.Context()
	ctx, stop := signal.NotifyContext(originalContext, os.Interrupt, syscall.SIGTERM)
	defer stop()
	cmd.SetContext(ctx)
	defer cmd.SetContext(originalContext)
	if len(opts.only) > 0 || len(opts.skip) > 0 || opts.reconsider {
		return errors.New("--experimental-agent cannot be combined with --only, --skip or --reconsider")
	}
	interactive := tui.IsInteractiveStdio() && !opts.yes && !opts.nonInteractive
	agent, err := selectSetupAgent(cmd.Context(), opts.experimentalAgent, interactive, cmd.ErrOrStderr())
	if err != nil {
		return err
	}
	root, err := prepareAgentSetupTarget(cmd.Context(), opts)
	if err != nil {
		return err
	}
	gitGuard, err := captureSetupGit(cmd.Context(), root)
	if err != nil {
		return err
	}
	keepNixInputs := false
	defer func() {
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		guardErr := gitGuard.Check(cleanupCtx)
		retErr = errors.Join(retErr, guardErr)
		if !keepNixInputs || guardErr != nil {
			retErr = errors.Join(retErr, gitGuard.Close(cleanupCtx))
		}
	}()
	request, err := prepareSetupRequest(cmd.Context(), root, opts)
	if err != nil {
		return err
	}
	var metadata struct {
		Files  map[string]string   `json:"templateFiles"`
		Addons []nixeval.AddonSpec `json:"addons"`
	}
	if err := json.Unmarshal([]byte(request.Context), &metadata); err != nil {
		return err
	}
	// Validate flags before starting a billed agent invocation.
	if _, err := setupAgentExpectations(reconcile.Expectations{Version: 1}, opts, metadata.Addons); err != nil {
		return err
	}
	ui := tui.NewSetupUI(cmd.Context(), interactive, cmd.ErrOrStderr())
	defer ui.Close()
	cmd.SetContext(ui.Context())
	var debug io.Writer = io.Discard
	if opts.agentLog != "" {
		file, err := os.OpenFile(opts.agentLog, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if err != nil {
			return err
		}
		defer file.Close()
		debug = file
	}
	var plan *setupagent.Plan
	for review := 0; review < 8; review++ {
		ui.Progress(fmt.Sprintf("Inspecting %s with %s (%s)", root, agent.ID, agent.Path))
		reply, err := runAgentPhase(cmd.Context(), agent, &request, setupagent.Inspection, nil, "", ui, debug)
		if err != nil {
			return err
		}
		if reply.Status != "plan" {
			return fmt.Errorf("inspection did not return a plan: %s", reply.Summary)
		}
		plan = reply.Plan
		for _, name := range plan.Services {
			if services.Get(name) == nil {
				return fmt.Errorf("unsupported service in plan: %s", name)
			}
		}
		plan.Expectations, err = setupAgentExpectations(plan.Expectations, opts, metadata.Addons)
		if err != nil {
			return err
		}
		if opts.newDir != "" && (len(plan.Expectations.Files) == 0 || len(plan.Expectations.Commands) == 0) {
			return errors.New("new repository plan requires source files and build/test acceptance commands")
		}
		decision, err := ui.ReviewPlan(renderSetupPlan(plan))
		if err != nil {
			return err
		}
		if decision == "Cancel" {
			return context.Canceled
		}
		if decision == "Apply" {
			break
		}
		answers, err := ui.Ask("What should change in the plan?", "text", nil, nil, true)
		if err != nil {
			return err
		}
		request.Answers = append(request.Answers, setupagent.Answer{ID: fmt.Sprintf("revision-%d", review), Values: answers})
		plan = nil
	}
	if plan == nil {
		return errors.New("plan revision limit reached")
	}
	frozen, err := json.Marshal(plan.Expectations)
	if err != nil {
		return err
	}
	work, err := os.MkdirTemp("", "stackpanel-agent-setup-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)
	expectationsPath := filepath.Join(work, "expectations.json")
	// Template evaluation happened on the host during inspection. Reuse those
	// exact files so the sandboxed coding agent never needs the Nix daemon.
	ui.Progress("Preparing Stackpanel template files…")
	if _, _, _, err := reconcile.WriteScaffold(root, metadata.Files, false); err != nil {
		return fmt.Errorf("prepare onboarding scaffold: %w", err)
	}
	if err := gitGuard.Check(cmd.Context()); err != nil {
		return err
	}
	var failure string
	var finalFailure string
	for attempt := 0; attempt < 2; attempt++ {
		phase := setupagent.Setup
		if attempt > 0 {
			phase = setupagent.Repair
			ui.Progress("Doctor did not verify onboarding; requesting one repair attempt.")
		}
		ui.Progress("Applying onboarding plan (" + string(phase) + ")")
		_, err := runAgentPhase(cmd.Context(), agent, &request, phase, plan, failure, ui, debug)
		if err != nil {
			return err
		}
		if err := gitGuard.AddNixInputs(cmd.Context(), plan.Expectations.Files...); err != nil {
			return err
		}
		ui.Progress("Resolving repository flake inputs with Nix…")
		if err := runSetupLock(cmd.Context(), root, work, gitGuard, debug); err != nil {
			failure = "Flake locking failed: " + err.Error()
			finalFailure = failure
			if cmd.Context().Err() != nil {
				return cmd.Context().Err()
			}
			continue
		}
		if err := gitGuard.AddNixInputs(cmd.Context(), plan.Expectations.Files...); err != nil {
			return err
		}
		ui.Progress("Entering the repository devshell and reconciling generated files…")
		if err := runFreshReconciliation(cmd.Context(), root, request.StackExecutable, debug); err != nil {
			failure = "Fresh reconciliation failed: " + err.Error()
			finalFailure = failure
			if cmd.Context().Err() != nil {
				return cmd.Context().Err()
			}
			continue
		}
		if err := gitGuard.AddNixInputs(cmd.Context(), plan.Expectations.Files...); err != nil {
			return err
		}
		// Recreate this from the frozen value after every model invocation.
		if err := os.WriteFile(expectationsPath, frozen, 0o600); err != nil {
			return err
		}
		ui.Progress("Verifying the agreed files, configuration, and build/test commands with stack doctor…")
		report, verifyErr := runFreshDoctor(cmd.Context(), root, request.StackExecutable, expectationsPath, debug)
		finalFailure = ""
		if report != nil {
			var rendered bytes.Buffer
			report.Render(&rendered, reconcile.RenderOptions{Title: "stack doctor · onboarding verification", Verbose: true})
			ui.Progress(rendered.String())
			finalFailure = rendered.String()
			data, err := report.JSON()
			if err != nil {
				return err
			}
			failure = string(data)
		}
		if verifyErr != nil {
			failure += "\n" + verifyErr.Error()
			finalFailure += "\n" + verifyErr.Error()
			if cmd.Context().Err() != nil {
				return cmd.Context().Err()
			}
			// Once checks have run, repair must not make them disappear. This
			// only strengthens the accepted contract; it never drops assertions.
			if report != nil && attempt == 0 {
				retainSetupChecks(&plan.Expectations, report)
				frozen, err = json.Marshal(plan.Expectations)
				if err != nil {
					return err
				}
			}
			continue
		}
		if err := gitGuard.Check(cmd.Context()); err != nil {
			return err
		}
		keepNixInputs = true
		if opts.noRuntime {
			ui.ShowResult("Repository onboarding verified by stack doctor. Runtime and Studio unverified (--no-runtime).")
		} else {
			if err := runSetupRuntime(cmd.Context(), root, request.StackExecutable, plan.Services, opts, ui, debug); err != nil {
				return fmt.Errorf("repository configured; runtime setup incomplete: %w", err)
			}
		}
		if opts.tmp {
			fmt.Fprintln(cmd.OutOrStdout(), root)
		}
		return nil
	}
	return fmt.Errorf("repository onboarding remains unverified after one repair attempt:\n%s", finalFailure)
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

func selectSetupAgent(ctx context.Context, requested string, interactive bool, out io.Writer) (setupagent.Agent, error) {
	var available []setupagent.Agent
	for _, agent := range setupagent.Discover() {
		if requested != "auto" && requested != agent.ID {
			continue
		}
		caps, err := setupagent.Probe(ctx, agent)
		if err != nil {
			fmt.Fprintf(out, "%s unavailable: %v\n", agent.ID, err)
			continue
		}
		if !caps.ReadOnly || !caps.Write {
			fmt.Fprintf(out, "%s unsupported: %s\n", agent.ID, caps.Reason)
			continue
		}
		available = append(available, agent)
	}
	if len(available) == 0 {
		return setupagent.Agent{}, fmt.Errorf("no supported agent found for %q on PATH; install/authenticate codex or claude, or use ordinary stack setup", requested)
	}
	if len(available) == 1 {
		return available[0], nil
	}
	if !interactive {
		return setupagent.Agent{}, errors.New("multiple agents available: select one with --experimental-agent=codex or --experimental-agent=claude")
	}
	labels := make([]string, len(available))
	for i, agent := range available {
		labels[i] = fmt.Sprintf("%s (%s)", agent.ID, agent.Path)
	}
	selected, err := tui.Select("Use which agent for onboarding?", labels, labels[0])
	if err != nil {
		return setupagent.Agent{}, err
	}
	for i, label := range labels {
		if label == selected {
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
	if err != nil {
		return &report, err
	}
	report.EnforceStrict()
	if report.HasErrors() || report.HasChanges() {
		return &report, errors.New("doctor found errors or pending changes")
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
