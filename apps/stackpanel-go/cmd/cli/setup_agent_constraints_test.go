package cmd

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

func setupConstraintAddons() []nixeval.AddonSpec {
	return []nixeval.AddonSpec{
		{ID: "vscode", Question: nixeval.AddonQuestion{Type: "bool", Default: true}, Config: map[string]any{
			"ide": map[string]any{"vscode": map[string]any{"enable": true}},
		}},
		{ID: "zed", Question: nixeval.AddonQuestion{Type: "bool", Default: true}, Config: map[string]any{
			"ide": map[string]any{"zed": map[string]any{"enable": true}},
		}},
		{ID: "deploy", Question: nixeval.AddonQuestion{Type: "select", Default: "none", Choices: []nixeval.AddonChoice{
			{Value: "none"},
			{Value: "fly", Config: map[string]any{"deployment": map[string]any{"fly": map[string]any{"enable": true, "region": "ams"}}}},
			{Value: "worker", Config: map[string]any{"deployment": map[string]any{"worker": map[string]any{"enable": true}}}},
		}}},
		{ID: "editors", Question: nixeval.AddonQuestion{Type: "multiselect", Choices: []nixeval.AddonChoice{
			{Value: "vim", Config: map[string]any{"ide": map[string]any{"vim": map[string]any{"enable": true}}}},
			{Value: "emacs", Config: map[string]any{"ide": map[string]any{"emacs": map[string]any{"enable": true}}}},
		}}},
	}
}

func assertSetupConstraint(t *testing.T, expected reconcile.Expectations, path, value string) {
	t.Helper()
	for _, assertion := range expected.Config {
		if strings.Join(assertion.Path, ".") == path {
			if string(assertion.Equals) != value {
				t.Fatalf("%s = %s, want %s", path, assertion.Equals, value)
			}
			return
		}
	}
	t.Fatalf("missing %s = %s in %+v", path, value, expected.Config)
}

func TestSetupAgentExpectationsEnforcesCLIChoicesWithoutDefaults(t *testing.T) {
	initial := reconcile.Expectations{Version: 1, Config: []reconcile.ConfigAssertion{
		{Path: []string{"enable"}, Equals: json.RawMessage("false")},
		{Path: []string{"ide"}, Equals: json.RawMessage(`{"vscode":{"enable":true}}`)},
		{Path: []string{"apps", "web"}, Equals: json.RawMessage(`{"command":"bun run dev"}`)},
	}}
	expected, err := setupAgentExpectations(initial, setupFlags{without: []string{" VSCODE "}}, setupConstraintAddons())
	if err != nil {
		t.Fatal(err)
	}
	assertSetupConstraint(t, expected, "enable", "true")
	assertSetupConstraint(t, expected, "ide.vscode.enable", "false")
	assertSetupConstraint(t, expected, "apps.web", `{"command":"bun run dev"}`)
	if len(expected.Config) != 3 {
		t.Fatalf("unrequested defaults or conflicting ancestors leaked into contract: %+v", expected.Config)
	}
	if string(initial.Config[0].Equals) != "false" || len(initial.Config[1].Path) != 1 {
		t.Fatal("modified caller's plan")
	}
}

func TestSetupAgentExpectationsUsesExistingFlagPriority(t *testing.T) {
	for _, tt := range []struct {
		name string
		opts setupFlags
		want string
	}{
		{"with", setupFlags{with: []string{"vscode"}}, "true"},
		{"without wins", setupFlags{with: []string{"vscode"}, without: []string{"vscode"}}, "false"},
		{"value wins", setupFlags{without: []string{"vscode"}, addonValues: []string{"vscode=yes"}}, "true"},
		{"first value wins", setupFlags{addonValues: []string{"vscode=false", "vscode=true"}}, "false"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			expected, err := setupAgentExpectations(reconcile.Expectations{Version: 1}, tt.opts, setupConstraintAddons())
			if err != nil {
				t.Fatal(err)
			}
			assertSetupConstraint(t, expected, "ide.vscode.enable", tt.want)
		})
	}
}

func TestSetupAgentExpectationsFreezesSelectAndMultiselect(t *testing.T) {
	expected, err := setupAgentExpectations(reconcile.Expectations{Version: 1}, setupFlags{addonValues: []string{"deploy=fly", "editors=vim"}}, setupConstraintAddons())
	if err != nil {
		t.Fatal(err)
	}
	assertSetupConstraint(t, expected, "deployment.fly.enable", "true")
	assertSetupConstraint(t, expected, "deployment.fly.region", `"ams"`)
	assertSetupConstraint(t, expected, "deployment.worker.enable", "false")
	assertSetupConstraint(t, expected, "ide.vim.enable", "true")
	assertSetupConstraint(t, expected, "ide.emacs.enable", "false")
	expected, err = setupAgentExpectations(reconcile.Expectations{Version: 1}, setupFlags{addonValues: []string{"deploy=none", "editors="}}, setupConstraintAddons())
	if err != nil {
		t.Fatal(err)
	}
	assertSetupConstraint(t, expected, "deployment.fly.enable", "false")
	assertSetupConstraint(t, expected, "deployment.worker.enable", "false")
	assertSetupConstraint(t, expected, "ide.vim.enable", "false")
	assertSetupConstraint(t, expected, "ide.emacs.enable", "false")
}

func TestSetupAgentExpectationsRejectsInvalidExplicitConstraints(t *testing.T) {
	for _, opts := range []setupFlags{
		{with: []string{"missing"}},
		{without: []string{"missing"}},
		{addonValues: []string{"missing=true"}},
		{addonValues: []string{"vscode"}},
		{addonValues: []string{"vscode=treu"}},
		{addonValues: []string{"deploy=unknown"}},
		{addonValues: []string{"editors=vim,unknown"}},
	} {
		if _, err := setupAgentExpectations(reconcile.Expectations{Version: 1}, opts, setupConstraintAddons()); err == nil {
			t.Fatalf("accepted invalid constraints %+v", opts)
		}
	}
}

func TestSetupAgentExpectationsDoesNotGuessDeclinedValues(t *testing.T) {
	addons := []nixeval.AddonSpec{{ID: "region", Question: nixeval.AddonQuestion{Type: "bool"}, Config: map[string]any{"region": "ams"}}}
	_, err := setupAgentExpectations(reconcile.Expectations{Version: 1}, setupFlags{without: []string{"region"}}, addons)
	if err == nil || !strings.Contains(err.Error(), "no enable switch") {
		t.Fatalf("declined arbitrary settings require an explicit inverse: %v", err)
	}
}

func TestSetupAgentExpectationsSelectedSharedSwitchWins(t *testing.T) {
	addons := []nixeval.AddonSpec{{ID: "deploy", Question: nixeval.AddonQuestion{Type: "select", Choices: []nixeval.AddonChoice{
		{Value: "east", Config: map[string]any{"deployment": map[string]any{"enable": true, "region": "east"}}},
		{Value: "west", Config: map[string]any{"deployment": map[string]any{"enable": true, "region": "west"}}},
	}}}}
	expected, err := setupAgentExpectations(reconcile.Expectations{Version: 1}, setupFlags{addonValues: []string{"deploy=east"}}, addons)
	if err != nil {
		t.Fatal(err)
	}
	assertSetupConstraint(t, expected, "deployment.enable", "true")
	assertSetupConstraint(t, expected, "deployment.region", `"east"`)
}
