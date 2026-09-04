package reconcile

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/fileops"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

func TestLedgerMigratesLegacyMarkerAndKeysOnRevision(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".stack"), 0o755); err != nil {
		t.Fatal(err)
	}
	legacy := filepath.Join(root, ".stack", "addons.json")
	if err := os.WriteFile(
		legacy,
		[]byte(`{"version":1,"addons":{"vscode":true,"deploy":"fly"}}`),
		0o644,
	); err != nil {
		t.Fatal(err)
	}

	ledger, err := LoadLedger(root, map[string]int{"vscode": 3})
	if err != nil {
		t.Fatal(err)
	}
	if ledger.MigratedFrom() != legacy {
		t.Fatalf("expected migration from %s", legacy)
	}
	if e := ledger.Seen["vscode"]; e.Revision != 3 || e.Answer != true {
		t.Fatalf("known addon should take its current revision, got %+v", e)
	}
	if e := ledger.Seen["deploy"]; e.Revision != 1 || e.Answer != "fly" {
		t.Fatalf("unknown addon should default to revision 1, got %+v", e)
	}

	// Migration never re-nags at the current revision.
	if ok, _ := ledger.ShouldOffer("vscode", 3, false); ok {
		t.Fatal("migrated decision must not be re-offered")
	}
	if ok, reason := ledger.ShouldOffer("brand-new", 1, false); !ok || reason != "new" {
		t.Fatal("unseen addon must be offered as new")
	}

	ledger.Record("brand-new", 1, false, time.Date(2026, 9, 4, 1, 22, 11, 0, time.UTC))
	if err := ledger.Save(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(legacy); !os.IsNotExist(err) {
		t.Fatal("legacy marker should be removed after save")
	}
	data, _ := os.ReadFile(LedgerPath(root))
	if !strings.Contains(string(data), `"at": "2026-09-04T01:22:11Z"`) {
		t.Fatalf("ledger should record when the offer was shown:\n%s", data)
	}
	reloaded, err := LoadLedger(root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if reloaded.MigratedFrom() != "" || len(reloaded.Seen) != 3 {
		t.Fatalf("reloaded ledger = %+v", reloaded.Seen)
	}
}

func TestMaterializeAndOverlay(t *testing.T) {
	t.Parallel()

	pw := nixeval.AddonSpec{
		ID:       "playwright",
		Question: nixeval.AddonQuestion{Type: "bool", Default: false},
		Config: map[string]any{
			"modules": map[string]any{"playwright": map[string]any{"enable": true}},
		},
	}
	if muts, active := Materialize(pw, Answer{Bool: false}); active || len(muts) != 0 {
		t.Fatal("declining must produce no mutation at all")
	}
	muts, active := Materialize(pw, Answer{Bool: true})
	if !active || len(muts) != 1 || muts[0].Path != "modules.playwright.enable" {
		t.Fatalf("accepting should enable the module, got %+v", muts)
	}

	deploy := nixeval.AddonSpec{
		ID: "deploy",
		Question: nixeval.AddonQuestion{Type: "select", Choices: []nixeval.AddonChoice{
			{Value: "none"},
			{
				Value: "fly",
				Config: map[string]any{
					"deployment": map[string]any{"fly": map[string]any{"enable": true}},
				},
			},
		}},
	}
	if _, active := Materialize(deploy, Answer{Select: "none"}); active {
		t.Fatal("a choice with no config is recorded but not active")
	}
	flyMuts, _ := Materialize(deploy, Answer{Select: "fly"})

	overlay := Overlay(append(muts, flyMuts...))
	modules := overlay["modules"].(map[string]any)["playwright"].(map[string]any)
	if modules["enable"] != true {
		t.Fatalf("overlay should nest modules.playwright.enable, got %v", overlay)
	}
	if overlay["deployment"].(map[string]any)["fly"].(map[string]any)["enable"] != true {
		t.Fatalf("overlay should nest deployment.fly.enable, got %v", overlay)
	}
}

func TestResolveAnswerPriority(t *testing.T) {
	t.Parallel()

	a := nixeval.AddonSpec{
		ID:       "vscode",
		Question: nixeval.AddonQuestion{Type: "bool", Default: true},
	}
	if ans, _ := ResolveAnswer(AnswerInputs{Without: []string{"vscode"}}, a); ans.Bool {
		t.Error("--without must decline")
	}
	if ans, _ := ResolveAnswer(
		AnswerInputs{
			With:    []string{"vscode"},
			Without: []string{"vscode"},
			Values:  []string{"vscode=false"},
		},
		a,
	); ans.Bool {
		t.Error("--addon id=value must win over --with")
	}
	prompted := false
	prompt := func(nixeval.AddonSpec) (Answer, error) { prompted = true; return Answer{Bool: false}, nil }
	if ans, _ := ResolveAnswer(AnswerInputs{Prompt: prompt}, a); ans.Bool || !prompted {
		t.Error("prompt should be consulted when no flag decides")
	}
	if ans, _ := ResolveAnswer(AnswerInputs{}, a); !ans.Bool {
		t.Error("default should apply when nothing else decides")
	}
}

func TestDiffPlanAgainstDisk(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	stateDir := filepath.Join(root, ".stack", "profile")
	if err := os.WriteFile(
		filepath.Join(root, "same.txt"),
		[]byte("hello\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(root, "package.json"),
		[]byte(`{"name":"web"}`),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(root, "owned.ts"),
		[]byte("mine\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	same := "hello\n"
	changed := "bye\n"
	entries := []PlanEntry{
		{
			Path:         "same.txt",
			Format:       "text",
			Writer:       "full",
			Adopt:        "none",
			Kind:         "pure",
			ManifestType: "pure",
			Content:      &same,
		},
		{
			Path:         "new.txt",
			Format:       "text",
			Writer:       "full",
			Adopt:        "none",
			Kind:         "pure",
			ManifestType: "pure",
			Content:      &changed,
		},
		{
			Path:         "package.json",
			Format:       "json",
			Writer:       "paths",
			Adopt:        "backup",
			Kind:         "preflight",
			ManifestType: "json-ops",
			Ops: []fileops.JSONOp{
				{Op: "set", Path: []string{"scripts", "test:e2e"}, Value: "playwright test"},
			},
		},
		{
			Path:         "owned.ts",
			Format:       "text",
			Writer:       "full",
			Adopt:        "refuse",
			Kind:         "preflight",
			ManifestType: "full-copy",
			Content:      &changed,
		},
		{
			Path:         ".gitignore",
			Format:       "lines",
			Writer:       "block",
			Adopt:        "none",
			Kind:         "preflight",
			ManifestType: "block",
			Content:      &same,
			Collisions: []fileops.Collision{
				{
					Path:  []string{"x"},
					Count: 2,
					Ops:   []fileops.JSONOp{{Op: "set", Value: 1}, {Op: "set", Value: 2}},
				},
			},
		},
	}

	diag := DiffPlan(root, stateDir, "adopt", entries)

	kinds := map[string]ChangeKind{}
	for _, c := range diag.Changes {
		kinds[c.Path] = c.Kind
	}
	if _, ok := kinds["same.txt"]; ok {
		t.Error("identical content must not be a change")
	}
	if kinds["new.txt"] != ChangeCreate {
		t.Errorf("missing file should be a create, got %v", kinds["new.txt"])
	}
	if kinds["package.json"] != ChangeUpdate ||
		kinds["package.json.backup"] != ChangeBackup {
		t.Errorf("paths writer on first contact should update and back up, got %v", kinds)
	}
	if kinds[".gitignore"] != ChangeCreate {
		t.Errorf("missing block file should be a create, got %v", kinds[".gitignore"])
	}
	if _, ok := kinds["owned.ts"]; ok {
		t.Error("refused file must not appear as a change")
	}
	var refused, collision bool
	for _, f := range diag.Findings {
		if f.ID == "adopt-refuse" && f.Path == "owned.ts" && f.Severity == SeverityError {
			refused = true
		}
		if f.ID == "collision" && f.Path == ".gitignore" && f.Severity == SeverityWarning {
			collision = true
		}
	}
	if !refused || !collision {
		t.Errorf("expected refuse error and collision warning, got %+v", diag.Findings)
	}
}

func TestReportRenderAndExitSemantics(t *testing.T) {
	t.Parallel()

	rep := &Report{
		Reconcilers: []string{"files", "checks", "addons"},
		Changes: []Change{
			{Reconciler: "files", Kind: ChangeUpdate, Path: ".vscode/settings.json"},
		},
		Findings: []Finding{
			{
				Reconciler: "checks",
				Severity:   SeverityWarning,
				Title:      "playwright: browsers (runtime)",
				FixCommand: "bunx playwright install",
			},
		},
		Offers: []Offer{
			{ID: "playwright", Revision: 1, Label: "Add Playwright?", Reason: "new"},
		},
	}
	if rep.HasErrors() {
		t.Fatal("warnings alone are not errors")
	}
	var buf bytes.Buffer
	rep.Render(&buf, RenderOptions{Title: "stack doctor", NextStep: "run setup"})
	out := buf.String()
	for _, want := range []string{"files", "1 change(s) pending", ".vscode/settings.json", "fix: bunx playwright install", "playwright", "run setup"} {
		if !strings.Contains(out, want) {
			t.Errorf("render missing %q:\n%s", want, out)
		}
	}
	rep.Findings = append(
		rep.Findings,
		Finding{Reconciler: "fileops", Severity: SeverityError, Title: "refused"},
	)
	if !rep.HasErrors() {
		t.Fatal("an error finding must flip HasErrors")
	}
}

func TestRegistrySelectAndDiagnoseIsolatesFailures(t *testing.T) {
	t.Parallel()

	reg := NewRegistry(&fakeReconciler{id: "ok"}, &fakeReconciler{id: "boom", fail: true})
	if _, err := reg.Select([]string{"typo"}, nil); err == nil {
		t.Fatal("unknown --only id must error")
	}
	sub, err := reg.Select(nil, []string{"boom"})
	if err != nil || len(sub.IDs()) != 1 {
		t.Fatalf("skip should drop boom, got %v %v", sub.IDs(), err)
	}
	ctx := &Context{ProjectRoot: t.TempDir(), Getenv: func(string) string { return "" }}
	rep := reg.Diagnose(ctx)
	if !rep.HasErrors() || len(rep.Errors) != 1 || rep.Errors[0].Reconciler != "boom" {
		t.Fatalf("failing reconciler must surface as an attributed error, got %+v", rep)
	}
	if len(rep.Changes) != 1 || rep.Changes[0].Reconciler != "ok" {
		t.Fatalf("healthy reconciler output must survive, got %+v", rep.Changes)
	}
}

type fakeReconciler struct {
	id   string
	fail bool
}

func (f *fakeReconciler) ID() string { return f.id }
func (f *fakeReconciler) Diagnose(*Context) (*Diagnosis, error) {
	if f.fail {
		return nil, os.ErrPermission
	}
	return &Diagnosis{
		Changes: []Change{{Reconciler: f.id, Kind: ChangeUpdate, Path: "x"}},
	}, nil
}

func (f *fakeReconciler) Apply(
	*Context,
) (*ApplyResult, error) {
	return &ApplyResult{}, nil
}

func TestLoadProjectConfigFileSubstitutesRoot(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")
	content := `{"version":1,"projectRoot":"$STACKPANEL_ROOT","doctor":[{"id":"pw-browsers","module":"pw","scope":"runtime","severity":"HEALTHCHECK_SEVERITY_WARNING","type":"HEALTHCHECK_TYPE_SCRIPT","enabled":true,"fixCommand":"bunx playwright install"}],"addons":[{"id":"playwright","question":{"type":"bool","label":"Add?"}}]}`
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg, err := LoadProjectConfigFile(path, "/repo")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ProjectRoot != "/repo" {
		t.Errorf("root placeholder not substituted: %q", cfg.ProjectRoot)
	}
	if len(cfg.Doctor) != 1 || *cfg.Doctor[0].FixCommand != "bunx playwright install" {
		t.Errorf("doctor checks not parsed: %+v", cfg.Doctor)
	}
	if len(cfg.Addons) != 1 || cfg.Addons[0].Revision != 1 {
		t.Errorf("addon revision should default to 1: %+v", cfg.Addons)
	}
	hc := cfg.Doctor[0].Healthcheck()
	if hc.ID != "pw-browsers" || hc.Type != "HEALTHCHECK_TYPE_SCRIPT" {
		t.Errorf("healthcheck adapter lost fields: %+v", hc)
	}
}
