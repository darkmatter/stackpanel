package fileops

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeFixture(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestPlanManifestReportsWithoutWriting(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	stateDir := filepath.Join(root, ".stack", "profile")
	target := filepath.Join(root, "package.json")
	writeFixture(t, target, `{"name":"web","scripts":{"dev":"vite"}}`)
	before, _ := os.ReadFile(target)

	manifest := Manifest{Version: 1, Files: []Entry{
		{
			Path:  "package.json",
			Type:  "json-ops",
			Adopt: "backup",
			Ops: []JSONOp{
				{Op: "set", Path: []string{"scripts", "test:e2e"}, Value: "playwright test"},
			},
		},
	}}

	summary, err := PlanManifest(root, stateDir, manifest)
	if err != nil {
		t.Fatalf("PlanManifest: %v", err)
	}
	if len(summary.Writes) != 1 || len(summary.Backups) != 1 {
		t.Fatalf("plan should report one write and one backup, got %+v", summary)
	}

	after, _ := os.ReadFile(target)
	if string(before) != string(after) {
		t.Fatal("PlanManifest must not modify the target")
	}
	if _, err := os.Stat(target + ".backup"); !os.IsNotExist(err) {
		t.Fatal("PlanManifest must not create backups")
	}
	if _, err := os.Stat(filepath.Join(stateDir, stateFilename)); !os.IsNotExist(err) {
		t.Fatal("PlanManifest must not persist state")
	}

	// The real apply then does exactly what the plan said.
	applied, err := ApplyManifest(root, stateDir, manifest)
	if err != nil {
		t.Fatalf("ApplyManifest: %v", err)
	}
	if len(applied.Writes) != 1 || len(applied.Backups) != 1 {
		t.Fatalf("apply should match plan, got %+v", applied)
	}
	// And is idempotent: a second plan shows nothing.
	again, err := PlanManifest(root, stateDir, manifest)
	if err != nil {
		t.Fatal(err)
	}
	if len(again.Writes) != 0 || len(again.Backups) != 0 {
		t.Fatalf("second plan should be a no-op, got %+v", again)
	}
}

func TestYAMLAndTOMLOpsKeepUnmanagedKeysAndRevert(t *testing.T) {
	t.Parallel()

	cases := []struct {
		entryType string
		file      string
		initial   string
	}{
		{"yaml-ops", "config.yaml", "name: demo\nowner:\n  team: platform\n"},
		{"toml-ops", "config.toml", "name = \"demo\"\n\n[owner]\nteam = \"platform\"\n"},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.entryType, func(t *testing.T) {
			t.Parallel()
			root := t.TempDir()
			stateDir := filepath.Join(root, ".stack", "profile")
			target := filepath.Join(root, tc.file)
			writeFixture(t, target, tc.initial)

			manifest := Manifest{Version: 1, Files: []Entry{
				{
					Path: tc.file,
					Type: tc.entryType,
					Ops: []JSONOp{
						{
							Op:    "set",
							Path:  []string{"scripts", "test:e2e"},
							Value: "playwright test",
						},
					},
				},
			}}
			if _, err := ApplyManifest(root, stateDir, manifest); err != nil {
				t.Fatalf("apply: %v", err)
			}
			c, _ := codecForType(tc.entryType)
			written, _, err := loadStructured(target, c)
			if err != nil {
				t.Fatal(err)
			}
			scripts, _ := written["scripts"].(map[string]any)
			if scripts["test:e2e"] != "playwright test" {
				t.Fatalf("managed key missing, got %v", written)
			}
			if owner, _ := written["owner"].(map[string]any); owner["team"] != "platform" {
				t.Fatalf("unmanaged key lost, got %v", written)
			}

			// Dropping the entry restores the baseline document.
			if _, err := ApplyManifest(root, stateDir, Manifest{Version: 1}); err != nil {
				t.Fatalf("revert: %v", err)
			}
			doc, _, err := loadStructured(target, c)
			if err != nil {
				t.Fatal(err)
			}
			if _, has := doc["scripts"]; has {
				t.Fatalf(
					"managed path and the empty parent it created should be removed on revert, got %v",
					doc,
				)
			}
			if doc["name"] != "demo" {
				t.Fatalf("baseline should survive revert, got %v", doc)
			}
		})
	}
}

func TestAdoptRefuseFailsOnApplyAndReportsOnPlan(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	stateDir := filepath.Join(root, ".stack", "profile")
	target := filepath.Join(root, "playwright.config.ts")
	writeFixture(t, target, "// user-owned\n")
	store := filepath.Join(root, "store", "playwright.config.ts")
	writeFixture(t, store, "// managed\n")

	manifest := Manifest{Version: 1, Files: []Entry{{
		Path:      "playwright.config.ts",
		Type:      "full-copy",
		Adopt:     "refuse",
		StorePath: store,
	}}}

	plan, err := PlanManifest(root, stateDir, manifest)
	if err != nil {
		t.Fatalf("plan should not fail: %v", err)
	}
	if len(plan.Refused) != 1 || len(plan.Writes) != 0 {
		t.Fatalf("plan should report the refusal and no write, got %+v", plan)
	}

	if _, err := ApplyManifest(
		root,
		stateDir,
		manifest,
	); err == nil ||
		!strings.Contains(err.Error(), "refusing to adopt") {
		t.Fatalf("apply should refuse loudly, got %v", err)
	}
	got, _ := os.ReadFile(target)
	if string(got) != "// user-owned\n" {
		t.Fatal("refused file must be left untouched")
	}

	// A file stackpanel creates itself is never "adopted", so refuse is inert.
	if err := os.Remove(target); err != nil {
		t.Fatal(err)
	}
	if _, err := ApplyManifest(root, stateDir, manifest); err != nil {
		t.Fatalf("apply on a missing file should succeed: %v", err)
	}
}

func TestNormalizeJSONOpsKeepsCooperativeOps(t *testing.T) {
	t.Parallel()

	ops := []JSONOp{
		{Op: "appendUnique", Path: []string{"keywords"}, Value: "a"},
		{Op: "appendUnique", Path: []string{"keywords"}, Value: "b"},
		{Op: "merge", Path: []string{"scripts"}, Value: map[string]any{"dev": "x"}},
		{Op: "merge", Path: []string{"scripts"}, Value: map[string]any{"test": "y"}},
		{Op: "set", Path: []string{"name"}, Value: "first"},
		{Op: "set", Path: []string{"name"}, Value: "second"},
	}
	normalized, managed, err := normalizeJSONOps(ops)
	if err != nil {
		t.Fatal(err)
	}
	if len(normalized) != 5 {
		t.Fatalf(
			"expected both appends, both merges and one set, got %d: %+v",
			len(normalized),
			normalized,
		)
	}
	if len(managed) != 3 {
		t.Fatalf("expected 3 managed paths, got %v", managed)
	}
	doc := map[string]any{}
	for _, op := range normalized {
		if err := applyJSONOp(doc, op); err != nil {
			t.Fatal(err)
		}
	}
	if doc["name"] != "second" {
		t.Errorf("last set should win, got %v", doc["name"])
	}
	if kw := doc["keywords"].([]any); len(kw) != 2 {
		t.Errorf("both appendUnique values should apply, got %v", kw)
	}
	if scripts := doc["scripts"].(map[string]any); len(scripts) != 2 {
		t.Errorf("both merges should apply, got %v", scripts)
	}
}

func TestPreviewOpsAndDocumentsEqual(t *testing.T) {
	t.Parallel()

	doc, err := DecodeDocument("yaml", []byte("a: 1\nb:\n  c: x\n"))
	if err != nil {
		t.Fatal(err)
	}
	next, err := PreviewOps(
		doc,
		[]JSONOp{{Op: "set", Path: []string{"b", "d"}, Value: float64(2)}},
	)
	if err != nil {
		t.Fatal(err)
	}
	if DocumentsEqual(doc, next) {
		t.Fatal("preview should differ from the input")
	}
	if _, ok := doc["b"].(map[string]any)["d"]; ok {
		t.Fatal("PreviewOps must not mutate its input")
	}
	// yaml ints and json floats compare equal.
	if !DocumentsEqual(map[string]any{"a": 1}, map[string]any{"a": float64(1)}) {
		t.Fatal("numeric types across codecs should compare equal")
	}
}
