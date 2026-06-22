package cmd

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// fakeStep returns a step whose isDone/apply counters are observable via the
// returned pointers. Useful for testing the step orchestration independent of
// real filesystem / Nix side effects.
func fakeStep(
	id string,
	checks *int,
	applies *int,
	startDone bool,
	persistent bool,
) step {
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
	seenRegister := -1
	for i, s := range steps {
		switch s.ID {
		case "fetch-init-files":
			seenFetch = i
		case "write-init-files":
			seenWrite = i
		case "register-project":
			seenRegister = i
		}
	}
	if seenFetch < 0 || seenWrite < 0 || seenRegister < 0 {
		t.Fatalf("missing expected steps in buildSteps(): %+v", steps)
	}
	if seenFetch > seenWrite {
		t.Errorf("fetch (%d) must run before write (%d)", seenFetch, seenWrite)
	}
}

func TestWriteInitFiles_PreservesExistingEnvrc(t *testing.T) {
	// If the user has customised .envrc (e.g. added extra env exports), we
	// must not clobber it unless --force. The .envrc ships in initFiles like
	// every other scaffolding file, so the generic skip-existing rule applies.
	dir := t.TempDir()
	custom := "# custom envrc\nuse flake .\nexport FOO=bar\n"
	if err := os.WriteFile(
		filepath.Join(dir, ".envrc"),
		[]byte(custom),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{".envrc": "use flake .\n"}
	if _, _, err := writeInitFiles(dir, files, false /*force*/, false); err != nil {
		t.Fatalf("writeInitFiles: %v", err)
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
			".stackpanel/config.nix":    "# config\n",
			".stackpanel/.gitignore":    "state/\n",
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

// TestFullPipeline_Idempotent exercises the full step list end-to-end without
// hitting the network: we stub the initFiles cache directly and assert that
// running the pipeline twice results in every step reporting "done" on the
// second pass. This is the acceptance test from the task spec.
func TestFullPipeline_Idempotent(t *testing.T) {
	dir := t.TempDir()
	// Pre-seed so the fetch step thinks it's already cached. The .envrc ships
	// in initFiles like every other scaffolding file.
	const envrcContent = "use flake .\n"
	fakeFiles := map[string]string{
		".envrc":            envrcContent,
		".stack/config.nix": "# config\n",
		".stack/data.nix":   "{ }\n",
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

func TestCreateTmpInitTargetCreatesGitRepo(t *testing.T) {
	t.Parallel()

	targetDir, err := createTmpInitTarget(context.Background())
	if err != nil {
		t.Fatalf("createTmpInitTarget returned error: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(targetDir) })

	if !strings.Contains(filepath.Base(targetDir), "stackpanel-init-") {
		t.Fatalf("expected stackpanel-init-* temp dir, got %s", targetDir)
	}
	if info, err := os.Stat(filepath.Join(targetDir, ".git")); err != nil {
		t.Fatalf("expected .git after tmp init: %v", err)
	} else if !info.IsDir() {
		t.Fatalf("expected .git to be a directory")
	}
}

// -----------------------------------------------------------------------------
// Addons
// -----------------------------------------------------------------------------

func TestFlattenConfig(t *testing.T) {
	in := map[string]any{
		"ide": map[string]any{
			"vscode": map[string]any{"enable": true},
		},
		"theme": map[string]any{"enable": true},
	}
	got := flattenConfig("", in)
	// Sorted: ide.vscode.enable, then theme.enable.
	if len(got) != 2 {
		t.Fatalf("expected 2 leaves, got %d: %+v", len(got), got)
	}
	if got[0].path != "ide.vscode.enable" || got[0].value != true {
		t.Errorf("leaf 0 = %+v, want ide.vscode.enable=true", got[0])
	}
	if got[1].path != "theme.enable" {
		t.Errorf("leaf 1 path = %q, want theme.enable", got[1].path)
	}
}

func TestMaterializeAddon_Bool(t *testing.T) {
	a := nixeval.AddonSpec{
		ID:       "vscode",
		Question: nixeval.AddonQuestion{Type: "bool"},
		Config:   map[string]any{"ide": map[string]any{"vscode": map[string]any{"enable": true}}},
	}

	plan := materializeAddon(a, addonAnswer{boolVal: true})
	if !plan.active {
		t.Fatal("bool=true should be active")
	}
	if plan.record != true {
		t.Errorf("record = %v, want true", plan.record)
	}
	if len(plan.enables) != 1 || plan.enables[0].path != "ide.vscode.enable" {
		t.Errorf("enables = %+v, want ide.vscode.enable", plan.enables)
	}

	plan = materializeAddon(a, addonAnswer{boolVal: false})
	if plan.active {
		t.Error("bool=false should not be active")
	}
	if plan.record != false {
		t.Errorf("declined record = %v, want false", plan.record)
	}
}

func TestMaterializeAddon_JSONOps(t *testing.T) {
	a := nixeval.AddonSpec{
		ID:       "biome",
		Question: nixeval.AddonQuestion{Type: "bool"},
		JSONOps: map[string][]nixeval.AddonJSONOp{
			"package.json": {
				{Op: "merge", Path: []string{"scripts"}, Value: map[string]any{"check": "biome check ."}},
			},
		},
	}

	// An addon with only json-ops (no files/config) is still active when accepted.
	plan := materializeAddon(a, addonAnswer{boolVal: true})
	if !plan.active {
		t.Fatal("json-ops-only addon should be active when accepted")
	}
	if _, ok := plan.jsonOps["package.json"]; !ok {
		t.Errorf("expected json-ops for package.json, got %+v", plan.jsonOps)
	}

	// Declined -> inactive.
	if materializeAddon(a, addonAnswer{boolVal: false}).active {
		t.Error("declined json-ops addon should be inactive")
	}
}

func TestJSONOpsEntryValue(t *testing.T) {
	ops := []nixeval.AddonJSONOp{
		{Op: "set", Path: []string{"private"}, Value: true},
		{Op: "remove", Path: []string{"old"}}, // no value
	}
	entry := jsonOpsEntryValue(ops)
	if entry["type"] != "json-ops" {
		t.Errorf("type = %v, want json-ops", entry["type"])
	}
	if entry["adopt"] != "backup" {
		t.Errorf("adopt = %v, want backup", entry["adopt"])
	}
	opList, ok := entry["ops"].([]any)
	if !ok || len(opList) != 2 {
		t.Fatalf("ops = %+v, want 2-element []any", entry["ops"])
	}
	// The "remove" op must not carry a value key.
	removeOp := opList[1].(map[string]any)
	if _, hasValue := removeOp["value"]; hasValue {
		t.Errorf("remove op should omit value, got %+v", removeOp)
	}
}

func TestEscapeConfigKey(t *testing.T) {
	if got := escapeConfigKey("package.json"); got != `package\.json` {
		t.Errorf("escapeConfigKey = %q, want %q", got, `package\.json`)
	}
	if got := escapeConfigKey("apps/web/tsconfig.json"); got != `apps/web/tsconfig\.json` {
		t.Errorf("escapeConfigKey = %q, want %q", got, `apps/web/tsconfig\.json`)
	}
}

func TestMaterializeAddon_Select(t *testing.T) {
	a := nixeval.AddonSpec{
		ID: "deploy",
		Question: nixeval.AddonQuestion{
			Type: "select",
			Choices: []nixeval.AddonChoice{
				{Value: "none"},
				{
					Value:  "fly",
					Config: map[string]any{"deployment": map[string]any{"fly": map[string]any{"enable": true}}},
					Files:  map[string]string{"fly.toml": "app = \"x\"\n"},
				},
			},
		},
	}

	plan := materializeAddon(a, addonAnswer{selectVal: "fly"})
	if !plan.active {
		t.Fatal("select=fly should be active")
	}
	if plan.record != "fly" {
		t.Errorf("record = %v, want fly", plan.record)
	}
	if _, ok := plan.files["fly.toml"]; !ok {
		t.Errorf("expected fly.toml in files, got %+v", plan.files)
	}
	if len(plan.enables) != 1 || plan.enables[0].path != "deployment.fly.enable" {
		t.Errorf("enables = %+v, want deployment.fly.enable", plan.enables)
	}

	// The "none" choice carries nothing -> inactive.
	if materializeAddon(a, addonAnswer{selectVal: "none"}).active {
		t.Error("select=none (no files/config) should not be active")
	}
}

func TestResolveAddonAnswer_Flags(t *testing.T) {
	a := nixeval.AddonSpec{
		ID:       "vscode",
		Question: nixeval.AddonQuestion{Type: "bool", Default: true},
	}

	// --without wins and yields a declined answer.
	ans, err := resolveAddonAnswer(&stepContext{withoutAddons: []string{"vscode"}}, a)
	if err != nil || ans.boolVal {
		t.Errorf("--without vscode -> %+v, %v; want boolVal=false", ans, err)
	}

	// --with yields true.
	ans, _ = resolveAddonAnswer(&stepContext{withAddons: []string{"vscode"}}, a)
	if !ans.boolVal {
		t.Error("--with vscode -> want boolVal=true")
	}

	// --addon id=false is explicit.
	ans, _ = resolveAddonAnswer(&stepContext{addonValues: []string{"vscode=false"}}, a)
	if ans.boolVal {
		t.Error("--addon vscode=false -> want boolVal=false")
	}

	// Non-interactive with no flags falls back to the default (true).
	ans, _ = resolveAddonAnswer(&stepContext{interactive: false}, a)
	if !ans.boolVal {
		t.Error("non-interactive default -> want boolVal=true")
	}
}

func TestAddonMarker_RoundTrip(t *testing.T) {
	dir := t.TempDir()
	if _, err := os.Stat(addonMarkerPath(dir)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("marker should not exist yet")
	}

	m, err := readAddonMarker(dir)
	if err != nil {
		t.Fatalf("readAddonMarker (missing): %v", err)
	}
	m.Addons["vscode"] = true
	m.Addons["editorconfig"] = false
	if err := writeAddonMarker(dir, m); err != nil {
		t.Fatalf("writeAddonMarker: %v", err)
	}

	got, err := readAddonMarker(dir)
	if err != nil {
		t.Fatalf("readAddonMarker: %v", err)
	}
	if got.Addons["vscode"] != true {
		t.Errorf("vscode = %v, want true", got.Addons["vscode"])
	}
	if _, ok := got.Addons["editorconfig"]; !ok {
		t.Errorf("editorconfig decision should be recorded")
	}
}

// TestApplyAddonsStep_PatchesConfigAndIsIdempotent pre-seeds the addon cache
// (so no nix eval runs) with a config-only bool addon, then asserts the first
// pass patches config.nix and records the marker, and a second pass is a no-op.
func TestApplyAddonsStep_PatchesConfigAndIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	configDir := filepath.Join(dir, ".stack")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(configDir, "config.nix")
	if err := os.WriteFile(configPath, []byte("{ }\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	vscode := nixeval.AddonSpec{
		ID:       "vscode",
		Question: nixeval.AddonQuestion{Type: "bool", Default: true},
		Config:   map[string]any{"ide": map[string]any{"vscode": map[string]any{"enable": true}}},
	}

	sctx := &stepContext{
		ctx:         context.Background(),
		targetDir:   dir,
		interactive: false, // use the default (true)
		addons:      []nixeval.AddonSpec{vscode},
	}

	if _, err := applyAddonsStep(sctx); err != nil {
		t.Fatalf("applyAddonsStep (first): %v", err)
	}

	after, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(after), "vscode") {
		t.Errorf("config.nix should mention vscode after apply, got:\n%s", string(after))
	}

	marker, err := readAddonMarker(dir)
	if err != nil {
		t.Fatal(err)
	}
	if marker.Addons["vscode"] != true {
		t.Errorf("marker should record vscode=true, got %+v", marker.Addons)
	}

	// Second pass: vscode is already in the marker, so config.nix is untouched.
	info1, _ := os.Stat(configPath)
	sctx.addonsResolved = false // allow the step body to run again
	if _, err := applyAddonsStep(sctx); err != nil {
		t.Fatalf("applyAddonsStep (second): %v", err)
	}
	info2, _ := os.Stat(configPath)
	if !info1.ModTime().Equal(info2.ModTime()) {
		t.Errorf("config.nix was rewritten on second run; addon apply not idempotent")
	}
}

// TestApplyAddonsStep_RegistersJSONOps verifies that a json-ops addon writes a
// stackpanel.files.entries "json-ops" entry into config.nix (the existing
// implementation then merges it into the target JSON on shell entry).
func TestApplyAddonsStep_RegistersJSONOps(t *testing.T) {
	dir := t.TempDir()
	configDir := filepath.Join(dir, ".stack")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(configDir, "config.nix")
	if err := os.WriteFile(configPath, []byte("{ }\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	biome := nixeval.AddonSpec{
		ID:       "biome",
		Question: nixeval.AddonQuestion{Type: "bool", Default: true},
		JSONOps: map[string][]nixeval.AddonJSONOp{
			"package.json": {
				{Op: "merge", Path: []string{"scripts"}, Value: map[string]any{"check": "biome check ."}},
			},
		},
	}

	sctx := &stepContext{
		ctx:         context.Background(),
		targetDir:   dir,
		interactive: false, // accept the default (true)
		addons:      []nixeval.AddonSpec{biome},
	}

	if _, err := applyAddonsStep(sctx); err != nil {
		t.Fatalf("applyAddonsStep: %v", err)
	}

	got, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"json-ops", "package.json", "scripts", "biome check ."} {
		if !strings.Contains(string(got), want) {
			t.Errorf("config.nix missing %q after json-ops apply, got:\n%s", want, string(got))
		}
	}
}

func TestStepRegisterProjectSkipsTmpProjects(t *testing.T) {
	t.Parallel()

	s := stepRegisterProject()
	sctx := &stepContext{ctx: context.Background(), targetDir: t.TempDir(), tmp: true}
	done, msg, err := s.IsDone(sctx)
	if err != nil {
		t.Fatalf("IsDone returned error: %v", err)
	}
	if !done {
		t.Fatal("expected tmp projects to skip registration")
	}
	if msg != "Temporary project not registered" {
		t.Fatalf("unexpected done message: %q", msg)
	}
}
