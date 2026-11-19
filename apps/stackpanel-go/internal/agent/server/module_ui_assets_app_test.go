package server

import (
	"net/http"
	"path/filepath"
	"slices"
	"testing"

	"connectrpc.com/connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

func TestUIAppPatchScope(t *testing.T) {
	root := t.TempDir()
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(root, "user.yaml"))
	s := newUITestServer(t)
	for _, scenario := range []string{"own", "value change", "changed item schema", "schema missing", "schema key mismatch", "untyped schema", "untyped items", "value violates schema", "new nested key", "removed key", "undeclared key", "private field", "store value", "malformed", "wrong slot", "missing app", "no downgrade", "disabled", "different app"} {
		t.Run(scenario, func(t *testing.T) {
			state, panel, _ := uiTestState()
			panel["slot"] = "app:tab"
			b := panel["uiBundle"].(map[string]any)
			b["permissions"] = []any{"config:read", "config:patch"}
			fields := map[string]any{"label": map[string]any{"count": float64(1)}}
			b["appSettings"] = map[string]any{"web": fields}
			prop := map[string]any{
				"type": "object",
				"properties": map[string]any{
					"count": map[string]any{"type": "integer"},
				},
				"additionalProperties": false,
			}
			props := map[string]any{"label": prop}
			b["appSchemas"] = map[string]any{
				"web": map[string]any{
					"type":                 "object",
					"properties":           props,
					"additionalProperties": false,
				},
			}
			appID := "web"
			switch scenario {
			case "schema missing":
				delete(b, "appSchemas")
			case "schema key mismatch":
				delete(props, "label")
				props["other"] = prop
			case "untyped schema":
				props["label"] = map[string]any{}
			case "untyped items":
				fields["label"] = []any{}
				props["label"] = map[string]any{"type": "array"}
			case "value violates schema":
				fields["label"] = false
			case "changed item schema":
				fields["label"] = []any{}
				props["label"] = map[string]any{
					"type":  "array",
					"items": map[string]any{"type": "string"},
				}
			case "wrong slot":
				panel["slot"] = "sidebar"
			case "missing app":
				appID = "missing"
			case "no downgrade":
				appID = ""
			case "disabled":
				panel["apps"].(map[string]any)["web"].(map[string]any)["enabled"] = false
			case "undeclared key":
				fields["undeclared"] = true
			case "private field":
				fields["label"] = []any{map[string]any{"secrets": "hidden"}}
			case "store value":
				fields["label"] = moduleStoreRoot + "/hidden"
			case "malformed":
				b["appSettings"] = "invalid"
			}
			token, err := s.issueModuleUIGrant(
				root,
				state,
				"demo",
				"inspector",
				appID,
				moduleStoreRoot,
				userconfig.LinkedModule{},
			)
			switch scenario {
			case "schema missing",
				"schema key mismatch",
				"untyped schema",
				"untyped items",
				"value violates schema",
				"wrong slot",
				"missing app",
				"no downgrade",
				"disabled",
				"undeclared key",
				"private field",
				"store value",
				"malformed":
				if connect.CodeOf(err) != connect.CodePermissionDenied {
					t.Fatalf("bad grant not rejected: %v", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			h := http.Header{}
			h.Set(moduleUIGrantHeader, token)
			rt := &projectRuntime{root: root}
			switch scenario {
			case "different app":
				b["appSettings"] = map[string]any{"api": fields}
			case "changed item schema":
				props["label"].(map[string]any)["items"] = map[string]any{"type": "integer"}
			case "removed key":
				delete(fields, "label")
			case "new nested key":
				fields["label"].(map[string]any)["extra"] = true
			case "value change":
				fields["label"].(map[string]any)["count"] = float64(3)
			}
			path, public, err := s.moduleUIConfigPatchScope(h, rt, state, "demo")
			if scenario != "own" && scenario != "value change" {
				if connect.CodeOf(err) != connect.CodePermissionDenied || path != nil ||
					public != nil {
					t.Fatal("stale grant did not fail closed")
				}
				return
			}
			if err != nil || !slices.Equal(path, []string{"apps", "web", "demo"}) ||
				len(public) != 1 {
				t.Fatal("wrong app scope", err)
			}
		})
	}
}
