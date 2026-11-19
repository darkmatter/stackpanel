package server

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"
	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

func TestUIGrantChecksDispatchSnapshot(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	s := newUITestServer(t)
	root := t.TempDir()
	for _, scenario := range []string{"valid", "different project", "other module", "config path", "new package", "disabled app", "new link", "revoked", "new executable", "new schema", "service port", "new issuer", "expired", "duplicate header", "empty header", "different operation"} {
		t.Run(scenario, func(t *testing.T) {
			state, panel, module := uiTestState()
			bundle := panel["uiBundle"].(map[string]any)
			bundle["permissions"] = []any{"actions:run", "config:read", "service:proxy"}
			action := map[string]any{
				"script":     "before",
				"argsSchema": map[string]any{"type": "object"},
			}
			module["actions"] = map[string]any{"inspect": action}
			svc := map[string]any{
				"module": "demo",
				"enable": true,
				"proxy":  map[string]any{"enable": true, "port": float64(9000)},
			}
			state["services"] = map[string]any{"api": svc}
			link := userconfig.LinkedModule{}
			if scenario == "new link" {
				link = userconfig.LinkedModule{Path: root, UIDevURL: "http://localhost:3100/"}
			}
			app := ""
			if scenario == "disabled app" {
				panel["slot"] = "app:tab"
				app = "web"
			}
			if scenario == "different operation" {
				bundle["permissions"] = []any{"config:read"}
			}
			grant, err := s.issueModuleUIGrant(
				root,
				state,
				"demo",
				"inspector",
				app,
				moduleStoreRoot,
				link,
			)
			if err != nil {
				t.Fatal(err)
			}
			h := http.Header{}
			h.Set(moduleUIGrantHeader, grant)
			selected, id := root, "demo"
			issuer := s
			switch scenario {
			case "different project":
				selected = t.TempDir()
			case "other module":
				id = "other"
			case "config path":
				module["configPath"] = "differently.scoped"
			case "new package":
				bundle["package"] = bundle["package"].(string) + "-new"
			case "revoked":
				bundle["permissions"] = []any{}
			case "new executable":
				action["script"] = "after"
			case "new schema":
				action["argsSchema"] = map[string]any{
					"type":                 "object",
					"additionalProperties": false,
				}
			case "service port":
				svc["proxy"].(map[string]any)["port"] = float64(9001)
			case "new issuer":
				issuer = newUITestServer(t)
			case "expired":
				c, err := s.decodeUIGrant(h)
				if err != nil {
					t.Fatal(err)
				}
				c.Expires = time.Now().Unix() - 1
				expired, err := s.encodeUIGrant(c)
				if err != nil {
					t.Fatal(err)
				}
				h.Set(moduleUIGrantHeader, expired)
			case "duplicate header":
				h.Add(moduleUIGrantHeader, grant)
			case "empty header":
				h.Set(moduleUIGrantHeader, "")
			case "disabled app":
				panel["apps"].(map[string]any)[app].(map[string]any)["enabled"] = false
			}
			err = issuer.checkModuleProxyGrant(h, &projectRuntime{root: selected}, state, id)
			if scenario == "valid" {
				if err != nil {
					t.Fatal(err)
				}
			} else if connect.CodeOf(err) != connect.CodePermissionDenied {
				t.Fatalf("expected denial: %v", err)
			}
		})
	}
}

func TestUIGrantEffectiveActions(t *testing.T) {
	state, panel, module := uiTestState()
	module["actions"] = map[string]any{
		"deploy": map[string]any{},
		"status": map[string]any{},
	}
	b := panel["uiBundle"].(map[string]any)
	for _, tc := range []struct {
		sel   any
		run   bool
		count int
	}{{nil, true, 2}, {[]any{}, true, 0}, {[]any{"status", "status", "missing"}, true, 1}, {nil, false, 0}} {
		b["actionIds"] = tc.sel
		b["permissions"] = []any{"config:read"}
		if tc.run {
			b["permissions"] = []any{"actions:run"}
		}
		got, err := evaluatedModuleBundle(state, "demo", "inspector", moduleStoreRoot)
		if err != nil {
			t.Fatal(err)
		}
		if len(got.actionIDs) != tc.count || tc.count == 1 && got.actionIDs[0] != "status" {
			t.Errorf("selector %v, actions %v", tc.sel, got.actionIDs)
		}
	}
}

func TestCustomPanelLaunchEligibility(t *testing.T) {
	for _, op := range []string{"actions:run", "service:proxy", "config:read"} {
		state, panel, _ := uiTestState()
		panel["slot"] = "app:tab"
		panel["uiBundle"].(map[string]any)["permissions"] = []any{op}
		b, err := evaluatedModuleBundle(state, "demo", "inspector", moduleStoreRoot)
		if err != nil {
			t.Fatal(err)
		}
		root := t.TempDir()
		revision := func(app string) error {
			_, err := uiGrantRevision(root, state, "demo", "inspector", app, b, userconfig.LinkedModule{}, "")
			return err
		}
		if err := revision("web"); err != nil {
			t.Fatal("eligible app denied:", err)
		}
		for _, app := range []string{"", "api", "absent"} {
			if err := revision(app); connect.CodeOf(err) != connect.CodePermissionDenied {
				t.Fatalf("%s accepted ineligible app %q: %v", op, app, err)
			}
		}
		state["apps"].(map[string]any)["web"].(map[string]any)["enable"] = false
		if err := revision("web"); connect.CodeOf(err) != connect.CodePermissionDenied {
			t.Fatalf("%s accepted a now-disabled project app: %v", op, err)
		}
	}
}

func TestMaxStatusAppSetRoundTrips(t *testing.T) {
	c := moduleUIGrant{Spec: true, Module: "demo", Panel: "panel", StatusAction: "status", Expires: time.Now().Add(time.Minute).Unix()}
	for i := range 128 {
		// Each route ID is exactly 128 ASCII bytes.
		c.StatusApps = append(c.StatusApps, fmt.Sprintf("%0128x", i))
	}
	s := newUITestServer(t)
	token, err := s.encodeUIGrant(c)
	if err != nil {
		t.Fatal(err)
	}
	h := http.Header{}
	h.Set(moduleUIGrantHeader, token)
	got, err := s.decodeUIGrant(h)
	if err != nil || len(got.StatusApps) != 128 || got.StatusApps[127] != c.StatusApps[127] {
		t.Fatalf("maximum grant lost targets: %v", err)
	}
}

func testReviewRevision(t *testing.T, root, store string, state map[string]any, id, panel string) string {
	t.Helper()
	mod, p, err := evaluatedUIPanel(state, id, panel)
	if err != nil {
		t.Fatal(err)
	}
	revision, _ := newUIReviewSnapshot(root, store, state, 9876).review(mod, p)
	if len(revision) != 64 {
		t.Fatal("no review for test panel", panel)
	}
	return revision
}

func (s *Server) issueModuleUIGrant(
	root string,
	state map[string]any,
	id, panel, app, storeRoot string,
	link userconfig.LinkedModule,
) (string, error) {
	b, err := evaluatedModuleBundle(state, id, panel, storeRoot)
	if err != nil {
		return "", err
	}
	digest, err := uiGrantRevision(root, state, id, panel, app, b, link, moduleActionProfile(root, storeRoot, state))
	if err != nil {
		return "", err
	}
	return s.encodeUIGrant(
		moduleUIGrant{
			Module:   id,
			Panel:    panel,
			App:      app,
			Revision: digest,
			Expires:  time.Now().Add(moduleUIGrantLifetime).Unix(),
		},
	)
}

// Exercise the production evaluator twice, not a shared in-memory map: an
// unrelated source edit changes the flake's store path in dirs.config even
// though the panel, executable, schema and profile are exactly the same.
func TestUIGrantSurvivesIndependentFlakeEvaluations(t *testing.T) {
	if _, err := exec.LookPath("nix"); err != nil {
		t.Skip("requires a local Nix installation")
	}
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	t.Setenv(
		"NIX_SYSTEM",
		"aarch64-darwin",
	) // fixture is data only; builds no derivations
	root := t.TempDir()
	write := func(name, body string, perm os.FileMode) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(root, name), []byte(body), perm); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Mkdir(filepath.Join(root, "bundle"), 0o700); err != nil {
		t.Fatal(err)
	}
	write("bundle/index.html", "<!doctype html><title>Test</title>", 0o600)
	write("report", "#!/bin/sh\nprintf ready", 0o700)
	write("profile", ".stack/profile", 0o600)
	write("flake.nix", `{
  outputs = { self }: { legacyPackages.aarch64-darwin.stackpanelSerializable = {
    dirs = { config = "${self.outPath}/.stack/config.nix"; profile = builtins.readFile ./profile; };
    modulesListAll = [{ id = "demo"; enabled = true; actions.report = {
      script = toString (builtins.path { path = ./report; name = "report"; });
      argsSchema.type = "object"; outputMode = "stream";
    }; }];
    panelsList = [{ module = "demo"; id = "preview"; enabled = true; type = "PANEL_TYPE_CUSTOM";
      uiBundle = { package = toString (builtins.path { path = ./bundle; name = "panel"; });
        entry = "index.html"; permissions = [ "actions:run" ]; actionIds = [ "report" ]; };
    }];
  }; };
}`, 0o600)
	rt := &projectRuntime{root: root} // nil evalModuleState uses the live selected flake
	ctx := context.WithValue(t.Context(), runtimeKey{}, rt)
	m := &moduleService{s: newUITestServer(t)}
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		t.Fatal(err)
	}
	review := testReviewRevision(t, root, moduleStoreRoot, state, "demo", "preview")
	opened, err := m.OpenModuleUI(
		ctx,
		connect.NewRequest(
			&agentv1.OpenModuleUIRequest{ModuleId: "demo", PanelId: "preview", ReviewRevision: review},
		),
	)
	if err != nil {
		t.Fatal(err)
	}
	h := http.Header{}
	h.Set(moduleUIGrantHeader, opened.Header().Get(moduleUIGrantHeader))
	write("notes", "a changed project snapshot, not a changed authority", 0o600)
	var out strings.Builder
	run := func() error {
		return m.runModuleActionWithHeader(
			ctx,
			moduleStoreRoot,
			h,
			&agentv1.RunModuleActionRequest{ModuleId: "demo", ActionId: "report"},
			func(event *agentv1.RunModuleActionResponse) error {
				out.WriteString(event.GetStdout())
				return nil
			},
		)
	}
	if err := run(); err != nil || out.String() != "ready" {
		t.Fatalf("unchanged action: output %q, err %v", out.String(), err)
	}
	write("profile", ".stack/replacement", 0o600)
	if err := run(); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("changed profile accepted: %v", err)
	}
}
