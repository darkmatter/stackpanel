package cmd

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

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

func TestSetupAndDoctorAreTopLevelCommands(t *testing.T) {
	t.Parallel()

	var haveSetup, haveDoctor, haveInit bool
	for _, c := range rootCmd.Commands() {
		switch c.Name() {
		case "setup":
			haveSetup = true
		case "doctor":
			haveDoctor = true
		case "init":
			haveInit = true
		}
	}
	if !haveSetup || !haveDoctor {
		t.Errorf(
			"setup and doctor must be flat top-level commands (setup=%v doctor=%v)",
			haveSetup,
			haveDoctor,
		)
	}
	if haveInit {
		t.Error("the deprecated init alias must be gone")
	}
}

// TestDecideOffers_DeclineWritesNoMutation pins the "not now is not never"
// rule: a declined bool addon is recorded but contributes no config mutation.
func TestDecideOffers_DeclineWritesNoMutation(t *testing.T) {
	t.Parallel()

	pw := nixeval.AddonSpec{
		ID:       "playwright",
		Revision: 1,
		Question: nixeval.AddonQuestion{
			Type:    "bool",
			Label:   "Add Playwright?",
			Default: false,
		},
		Config: map[string]any{
			"modules": map[string]any{"playwright": map[string]any{"enable": true}},
		},
	}
	offers := []reconcile.Offer{
		{ID: "playwright", Revision: 1, Label: pw.Question.Label, Reason: "new"},
	}

	decisions, mutations, err := decideOffers(
		offers,
		[]nixeval.AddonSpec{pw},
		reconcile.AnswerInputs{Without: []string{"playwright"}},
		true,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(decisions) != 1 || decisions[0].answer.Bool {
		t.Fatalf("expected one declined decision, got %+v", decisions)
	}
	if len(mutations) != 0 {
		t.Fatalf(
			"declining must not produce mutations (no enable = false), got %+v",
			mutations,
		)
	}

	// Accepting produces exactly the module enable.
	_, mutations, err = decideOffers(
		offers,
		[]nixeval.AddonSpec{pw},
		reconcile.AnswerInputs{With: []string{"playwright"}},
		true,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(mutations) != 1 || mutations[0].Path != "modules.playwright.enable" ||
		mutations[0].Value != true {
		t.Fatalf("expected modules.playwright.enable = true, got %+v", mutations)
	}
}

// TestRecordDecisions_LedgerMigratesLegacyMarker exercises the addons.json ->
// reconcile.json migration through the setup helper.
func TestRecordDecisions_LedgerMigratesLegacyMarker(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, ".stack"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(dir, ".stack", "addons.json"),
		[]byte(`{"version":1,"addons":{"vscode":true,"zed":false}}`),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	pw := nixeval.AddonSpec{
		ID:       "playwright",
		Revision: 2,
		Question: nixeval.AddonQuestion{Type: "bool"},
	}
	vscode := nixeval.AddonSpec{
		ID:       "vscode",
		Revision: 1,
		Question: nixeval.AddonQuestion{Type: "bool"},
	}
	addons := []nixeval.AddonSpec{pw, vscode}

	if err := recordDecisions(
		dir,
		addons,
		[]offerDecision{{addon: pw, answer: reconcile.Answer{Bool: false}}},
	); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(
		filepath.Join(dir, ".stack", "addons.json"),
	); !os.IsNotExist(
		err,
	) {
		t.Error("legacy addons.json should be removed after migration")
	}
	ledger, err := reconcile.LoadLedger(dir, reconcile.RevisionsOf(addons))
	if err != nil {
		t.Fatal(err)
	}
	if e := ledger.Seen["vscode"]; e.Revision != 1 || e.Answer != true {
		t.Errorf("migrated vscode entry = %+v", e)
	}
	if e := ledger.Seen["playwright"]; e.Revision != 2 || e.Answer != false ||
		e.At == "" {
		t.Errorf("playwright entry = %+v", e)
	}
	if ok, _ := ledger.ShouldOffer("playwright", 2, false); ok {
		t.Error("declined at current revision must not be re-offered")
	}
	if ok, reason := ledger.ShouldOffer(
		"playwright",
		3,
		false,
	); !ok ||
		reason != "revised" {
		t.Error("bumped revision must re-offer")
	}
	if ok, reason := ledger.ShouldOffer(
		"playwright",
		2,
		true,
	); !ok ||
		reason != "reconsider" {
		t.Error("--reconsider must re-offer")
	}
}
