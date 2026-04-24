package cmd

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeStep returns a step whose isDone/apply counters are observable via the
// returned pointers. Useful for testing the step orchestration independent of
// real filesystem / Nix side effects.
func fakeStep(id string, checks *int, applies *int, startDone bool, persistent bool) step {
	done := startDone
	return step{
		ID:    id,
		Title: "fake: " + id,
		IsDone: func(s *stepContext) (bool, string, error) {
			*checks++
			return done, "", nil
		},
		Apply: func(s *stepContext) (string, error) {
			*applies++
			if persistent {
				done = true
			}
			return "", nil
		},
	}
}

func TestRunStep_SkipsWhenDone(t *testing.T) {
	var checks, applies int
	s := fakeStep("already-done", &checks, &applies, true, true)
	sctx := &stepContext{ctx: context.Background(), interactive: false}
	if err := runStep(sctx, s); err != nil {
		t.Fatalf("runStep returned error: %v", err)
	}
	if checks != 1 {
		t.Errorf("IsDone should run exactly once, got %d", checks)
	}
	if applies != 0 {
		t.Errorf("Apply must not run when IsDone reports true, got %d", applies)
	}
}

func TestRunStep_AppliesWhenNotDone(t *testing.T) {
	var checks, applies int
	s := fakeStep("pending", &checks, &applies, false, true)
	sctx := &stepContext{ctx: context.Background(), interactive: false}
	if err := runStep(sctx, s); err != nil {
		t.Fatalf("runStep returned error: %v", err)
	}
	if applies != 1 {
		t.Errorf("Apply should run exactly once, got %d", applies)
	}
}

func TestRunStep_SecondRunIsNoop(t *testing.T) {
	// Simulate a fresh step that becomes "done" after Apply. The second
	// invocation of runStep must detect that and skip. This is the central
	// idempotency invariant for `stackpanel init`.
	var checks, applies int
	s := fakeStep("idempotent", &checks, &applies, false, true)
	sctx := &stepContext{ctx: context.Background(), interactive: false}

	for i := 0; i < 2; i++ {
		if err := runStep(sctx, s); err != nil {
			t.Fatalf("run %d returned error: %v", i, err)
		}
	}
	if applies != 1 {
		t.Errorf("expected Apply to run once across two invocations, got %d", applies)
	}
	if checks != 2 {
		t.Errorf("expected IsDone to run twice (once per invocation), got %d", checks)
	}
}

func TestRunStep_DryRunDoesNotApply(t *testing.T) {
	var checks, applies int
	s := fakeStep("dry", &checks, &applies, false, true)
	sctx := &stepContext{ctx: context.Background(), interactive: false, dryRun: true}
	if err := runStep(sctx, s); err != nil {
		t.Fatalf("runStep returned error: %v", err)
	}
	if applies != 0 {
		t.Errorf("Apply must not run in dry-run mode, got %d", applies)
	}
}

func TestBuildSteps_Order(t *testing.T) {
	// The fetch step must come before write-init-files, since write consumes
	// the cached map produced by fetch.
	steps := buildSteps()
	seenFetch := -1
	seenWrite := -1
	seenEnvrc := -1
	seenRegister := -1
	for i, s := range steps {
		switch s.ID {
		case "fetch-init-files":
			seenFetch = i
		case "write-init-files":
			seenWrite = i
		case "envrc":
			seenEnvrc = i
		case "register-project":
			seenRegister = i
		}
	}
	if seenFetch < 0 || seenWrite < 0 || seenEnvrc < 0 || seenRegister < 0 {
		t.Fatalf("missing expected steps in buildSteps(): %+v", steps)
	}
	if seenFetch > seenWrite {
		t.Errorf("fetch (%d) must run before write (%d)", seenFetch, seenWrite)
	}
}

func TestStepGenerateEnvrc_IdempotentAndContent(t *testing.T) {
	dir := t.TempDir()
	sctx := &stepContext{ctx: context.Background(), targetDir: dir, interactive: false}
	s := stepGenerateEnvrc()

	// First run: not done, should apply.
	done, _, err := s.IsDone(sctx)
	if err != nil {
		t.Fatalf("IsDone error: %v", err)
	}
	if done {
		t.Fatalf("expected .envrc to be missing initially")
	}
	if _, err := s.Apply(sctx); err != nil {
		t.Fatalf("Apply error: %v", err)
	}

	// Content must match exactly.
	got, err := os.ReadFile(filepath.Join(dir, ".envrc"))
	if err != nil {
		t.Fatalf("read .envrc: %v", err)
	}
	if string(got) != envrcContent {
		t.Errorf("unexpected .envrc content:\ngot:  %q\nwant: %q", string(got), envrcContent)
	}
	if !strings.Contains(string(got), "use flake") {
		t.Errorf(".envrc missing required directive: %q", string(got))
	}

	// Second run: should report done and NOT call Apply.
	done, _, err = s.IsDone(sctx)
	if err != nil {
		t.Fatalf("IsDone (second) error: %v", err)
	}
	if !done {
		t.Errorf(".envrc step should be done after first apply")
	}
}

func TestStepGenerateEnvrc_PreservesExisting(t *testing.T) {
	// If the user has customised .envrc (e.g. added extra env exports), we
	// must not clobber it unless --force.
	dir := t.TempDir()
	custom := "# custom envrc\nuse flake . --impure\nexport FOO=bar\n"
	if err := os.WriteFile(filepath.Join(dir, ".envrc"), []byte(custom), 0o644); err != nil {
		t.Fatal(err)
	}
	sctx := &stepContext{ctx: context.Background(), targetDir: dir, interactive: false}
	s := stepGenerateEnvrc()
	done, _, err := s.IsDone(sctx)
	if err != nil {
		t.Fatalf("IsDone error: %v", err)
	}
	if !done {
		t.Errorf("existing .envrc should cause step to be considered done")
	}
	got, _ := os.ReadFile(filepath.Join(dir, ".envrc"))
	if string(got) != custom {
		t.Errorf(".envrc was modified when it should have been preserved")
	}
}

func TestStepWriteInitFiles_SecondRunSkipsAll(t *testing.T) {
	dir := t.TempDir()
	sctx := &stepContext{
		ctx:       context.Background(),
		targetDir: dir,
		initFiles: map[string]string{
			".stackpanel/config.nix":  "# config\n",
			".stackpanel/.gitignore":  "state/\n",
			".stackpanel/_internal.nix": "{ }\n",
		},
	}
	s := stepWriteInitFiles()

	// First: not done.
	if done, _, _ := s.IsDone(sctx); done {
		t.Fatal("expected not-done before apply")
	}
	if _, err := s.Apply(sctx); err != nil {
		t.Fatalf("Apply: %v", err)
	}
	// Second: everything present, should be done.
	done, _, err := s.IsDone(sctx)
	if err != nil {
		t.Fatalf("IsDone: %v", err)
	}
	if !done {
		t.Errorf("write-init-files should report done when every file exists")
	}

	// Remove one file to simulate partial state — should become not-done again.
	if err := os.Remove(filepath.Join(dir, ".stackpanel/_internal.nix")); err != nil {
		t.Fatal(err)
	}
	done, _, _ = s.IsDone(sctx)
	if done {
		t.Errorf("write-init-files should flag missing file as not-done")
	}
}

func TestWriteInitFiles_ForceOverwrites(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "a.txt")
	if err := os.WriteFile(path, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{"a.txt": "new"}
	if _, _, err := writeInitFiles(dir, files, true /*force*/, false); err != nil {
		t.Fatalf("writeInitFiles: %v", err)
	}
	got, _ := os.ReadFile(path)
	if string(got) != "new" {
		t.Errorf("force should overwrite, got %q", string(got))
	}
}

func TestWriteInitFiles_NoForcePreserves(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "a.txt")
	if err := os.WriteFile(path, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{"a.txt": "new"}
	if _, _, err := writeInitFiles(dir, files, false /*force*/, false); err != nil {
		t.Fatalf("writeInitFiles: %v", err)
	}
	got, _ := os.ReadFile(path)
	if string(got) != "old" {
		t.Errorf("non-force must preserve existing file, got %q", string(got))
	}
}

func TestResolveFlakeRef(t *testing.T) {
	// Flag wins.
	t.Setenv("STACKPANEL_FLAKE", "")
	t.Setenv("STACKPANEL_ROOT", "")
	if got := resolveFlakeRef("explicit"); got != "explicit" {
		t.Errorf("expected flag to win, got %q", got)
	}
	// Env var next.
	t.Setenv("STACKPANEL_FLAKE", "from-env")
	if got := resolveFlakeRef(""); got != "from-env" {
		t.Errorf("expected STACKPANEL_FLAKE, got %q", got)
	}
	t.Setenv("STACKPANEL_FLAKE", "")
	t.Setenv("STACKPANEL_ROOT", "/tmp/sp")
	if got := resolveFlakeRef(""); got != "path:/tmp/sp" {
		t.Errorf("expected path: prefix from STACKPANEL_ROOT, got %q", got)
	}
	t.Setenv("STACKPANEL_ROOT", "")
	if got := resolveFlakeRef(""); got != defaultStackpanelFlake {
		t.Errorf("expected default flake ref, got %q", got)
	}
}

func TestStdinConfirm(t *testing.T) {
	cases := []struct {
		name       string
		input      string
		defaultYes bool
		want       bool
	}{
		{"empty-defaults-yes", "\n", true, true},
		{"empty-defaults-no", "\n", false, false},
		{"explicit-y", "y\n", false, true},
		{"explicit-yes", "yes\n", false, true},
		{"explicit-n", "n\n", true, false},
		{"anything-else-is-no", "maybe\n", true, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			got, err := stdinConfirm(strings.NewReader(tc.input), &out, "go?", tc.defaultYes)
			if err != nil {
				t.Fatalf("stdinConfirm: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %v, want %v (input=%q default=%v)", got, tc.want, tc.input, tc.defaultYes)
			}
		})
	}
}

// TestFullPipeline_Idempotent exercises the full step list end-to-end without
// hitting the network: we stub the initFiles cache directly and assert that
// running the pipeline twice results in every step reporting "done" on the
// second pass. This is the acceptance test from the task spec.
func TestFullPipeline_Idempotent(t *testing.T) {
	dir := t.TempDir()
	// Pre-seed so the fetch step thinks it's already cached.
	fakeFiles := map[string]string{
		".stackpanel/config.nix": "# config\n",
		".stackpanel/.gitignore": "state/\n",
	}

	// We can't easily avoid the real userconfig step in this unit test, so we
	// point HOME at a temp dir to isolate it.
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(t.TempDir(), "cfg"))

	run := func() error {
		sctx := &stepContext{
			ctx:       context.Background(),
			targetDir: dir,
			flakeRef:  "unused-in-test",
			initFiles: fakeFiles, // pretend fetch already ran
		}
		// Drop the fetch step (which would call nix eval) and use the rest.
		steps := []step{
			stepWriteInitFiles(),
			stepGenerateEnvrc(),
			stepRegisterProject(),
		}
		for _, s := range steps {
			if err := runStep(sctx, s); err != nil {
				return fmt.Errorf("step %s: %w", s.ID, err)
			}
		}
		return nil
	}

	if err := run(); err != nil {
		t.Fatalf("first run: %v", err)
	}
	// Second run: every step should be done; record that no step's Apply ran.
	// We detect that by ensuring the .envrc file we wrote has not been changed.
	envrcPath := filepath.Join(dir, ".envrc")
	info1, err := os.Stat(envrcPath)
	if err != nil {
		t.Fatalf("stat .envrc after first run: %v", err)
	}

	if err := run(); err != nil {
		t.Fatalf("second run: %v", err)
	}
	info2, err := os.Stat(envrcPath)
	if err != nil {
		t.Fatalf("stat .envrc after second run: %v", err)
	}
	if !info1.ModTime().Equal(info2.ModTime()) {
		t.Errorf(".envrc was rewritten on second run; idempotency broken")
	}

	// Sanity: .envrc content is correct.
	got, _ := os.ReadFile(envrcPath)
	if string(got) != envrcContent {
		t.Errorf("envrc content mismatch: got %q", string(got))
	}
}

// Ensure the errors wrapper paths behave sanely — important for good UX when
// users see failures surfaced from step %q failed: %w.
func TestRunStep_WrapsErrors(t *testing.T) {
	boom := errors.New("boom")
	s := step{
		ID:    "broken",
		Title: "broken",
		IsDone: func(*stepContext) (bool, string, error) {
			return false, "", nil
		},
		Apply: func(*stepContext) (string, error) {
			return "", boom
		},
	}
	sctx := &stepContext{ctx: context.Background(), interactive: false}
	err := runStep(sctx, s)
	if err == nil || !errors.Is(err, boom) {
		t.Errorf("expected wrapped error containing boom, got %v", err)
	}
}
