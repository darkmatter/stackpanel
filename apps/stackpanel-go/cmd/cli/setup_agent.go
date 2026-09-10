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
	root, err := setupTargetDir(cmd.Context(), opts.tmp, false)
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
		retErr = errors.Join(retErr, gitGuard.Check(cleanupCtx))
		if !keepNixInputs || retErr != nil {
			retErr = errors.Join(retErr, gitGuard.Close(cleanupCtx))
		}
	}()
	request, err := prepareSetupRequest(cmd.Context(), root, opts)
	if err != nil {
		return err
	}
	var metadata struct {
		Addons []nixeval.AddonSpec `json:"addons"`
	}
	if err := json.Unmarshal([]byte(request.Context), &metadata); err != nil {
		return err
	}
	// Validate flags before starting a billed agent invocation.
	if _, err := setupAgentExpectations(reconcile.Expectations{Version: 1}, opts, metadata.Addons); err != nil {
		return err
	}
	fmt.Fprintf(cmd.ErrOrStderr(), "Inspecting %s with %s (%s)\n", root, agent.ID, agent.Path)
	result, err := setupagent.Run(cmd.Context(), agent, setupagent.RunRequest{
		Dir: root, Env: freshSetupEnvironment(os.Environ()), ReadOnly: true,
		Prompt:  setupagent.BuildPrompt(request, setupagent.Inspection, nil, ""),
		Timeout: setupStageTimeout, Stdout: cmd.ErrOrStderr(), Stderr: cmd.ErrOrStderr(),
	})
	if err != nil {
		return fmt.Errorf("agent inspection: %w", err)
	}
	plan, err := setupagent.ParsePlan(result.Message)
	if err != nil {
		return fmt.Errorf("agent inspection plan: %w", err)
	}
	plan.Expectations, err = setupAgentExpectations(plan.Expectations, opts, metadata.Addons)
	if err != nil {
		return err
	}
	planJSON, err := json.MarshalIndent(plan, "", "  ")
	if err != nil {
		return err
	}
	fmt.Fprintf(cmd.ErrOrStderr(), "\nOnboarding plan:\n%s\n", planJSON)
	if interactive {
		accepted, err := tui.Confirm("Apply this onboarding plan and verify with doctor?", true)
		if err != nil {
			return err
		}
		if !accepted {
			return nil
		}
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
	var failure string
	for attempt := 0; attempt < 2; attempt++ {
		phase := setupagent.Setup
		if attempt > 0 {
			phase = setupagent.Repair
			fmt.Fprintln(cmd.ErrOrStderr(), "Doctor did not verify onboarding; requesting one repair attempt.")
		}
		_, err := setupagent.Run(cmd.Context(), agent, setupagent.RunRequest{
			Dir: root, Env: freshSetupEnvironment(os.Environ()),
			Prompt: setupagent.BuildPrompt(request, phase, plan, failure), Timeout: setupStageTimeout,
			Stdout: cmd.ErrOrStderr(), Stderr: cmd.ErrOrStderr(),
		})
		if err != nil {
			return fmt.Errorf("agent %s: %w", phase, err)
		}
		if err := gitGuard.AddNixInputs(cmd.Context()); err != nil {
			return err
		}
		if err := runFreshReconciliation(cmd.Context(), root, request.StackExecutable, cmd.ErrOrStderr()); err != nil {
			failure = "Fresh reconciliation failed: " + err.Error()
			if cmd.Context().Err() != nil {
				return cmd.Context().Err()
			}
			continue
		}
		if err := gitGuard.AddNixInputs(cmd.Context()); err != nil {
			return err
		}
		// Recreate this from the frozen value after every model invocation.
		if err := os.WriteFile(expectationsPath, frozen, 0o600); err != nil {
			return err
		}
		report, verifyErr := runFreshDoctor(cmd.Context(), root, request.StackExecutable, expectationsPath, cmd.ErrOrStderr())
		if report != nil {
			report.Render(cmd.ErrOrStderr(), reconcile.RenderOptions{Title: "stack doctor · onboarding verification", Verbose: true})
			data, err := report.JSON()
			if err != nil {
				return err
			}
			failure = string(data)
		}
		if verifyErr != nil {
			failure += "\n" + verifyErr.Error()
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
		fmt.Fprintln(cmd.ErrOrStderr(), "Repository onboarding verified by stack doctor.")
		if opts.tmp {
			fmt.Fprintln(cmd.OutOrStdout(), root)
		}
		return nil
	}
	return fmt.Errorf("repository onboarding remains unverified after one repair attempt:\n%s", failure)
}

func retainSetupChecks(expected *reconcile.Expectations, report *reconcile.Report) {
	seen := make(map[string]bool, len(expected.RequiredChecks))
	for _, id := range expected.RequiredChecks {
		seen[id] = true
	}
	for _, check := range report.CheckResults {
		if check.ID != "" && !seen[check.ID] {
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
	request := setupagent.SetupRequest{Root: root, Template: opts.template}
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
	if resolved.Locked.Rev == "" {
		// A dirty local checkout has no immutable revision URL. Nix's source
		// snapshot is immutable; leave its absolute path unprefixed because
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
		Files  map[string]string   `json:"templateFiles"`
		Addons []nixeval.AddonSpec `json:"addons"`
	}{files, addons})
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

func runFreshDoctor(ctx context.Context, root, stackExecutable, expectationsPath string, out io.Writer) (*reconcile.Report, error) {
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
	err = runSetupShell(ctx, root, out, "bash", "--noprofile", "--norc", "-c",
		`report=$1; shift; exec "$@" > "$report"`, "stackpanel-doctor", path,
		stackExecutable, "doctor", "--strict", "--scope", "repo,build", "--build", "--expectations", expectationsPath, "--json")
	data, readErr := os.ReadFile(path)
	if readErr != nil {
		return nil, readErr
	}
	var report reconcile.Report
	if parseErr := json.Unmarshal(data, &report); parseErr != nil {
		return nil, fmt.Errorf("doctor did not produce a valid report: %v (shell: %v)", parseErr, err)
	}
	// An older binary or an empty object must not be accepted as verification.
	for _, required := range []string{"codegen", "files", "fileops", "checks", "verification"} {
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
	sctx, cancel := context.WithTimeout(ctx, setupStageTimeout)
	defer cancel()
	nixArgs := append([]string{"develop", ".", "--no-update-lock-file", "--no-write-lock-file", "--command"}, args...)
	cmd := exec.CommandContext(sctx, "nix", nixArgs...)
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
		return fmt.Errorf("fresh Nix shell: %w\n%s", err, tail.data)
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
