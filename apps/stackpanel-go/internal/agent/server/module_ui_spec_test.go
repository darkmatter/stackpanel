package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/structpb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

type specUIFixture struct {
	*actionFixture
	m        *moduleService
	rt       *projectRuntime
	panel    map[string]any
	elements map[string]any
}

func newSpecUIFixture(t *testing.T) *specUIFixture {
	t.Helper()
	f := newActionFixture(t, `: >ran; IFS= read -r args; printf '%s' "$args"`)
	f.action["label"], f.action["outputMode"] = "Status", "json"
	actions := f.module["actions"].(map[string]any)
	actions["remove"] = maps.Clone(f.action)
	actions["remove"].(map[string]any)["confirm"] = "Delete resources?"
	actions["other"], actions["buttonsOnly"] = maps.Clone(f.action), maps.Clone(f.action)
	selection := map[string]any{"$state": "/local/selection"}
	elements := map[string]any{
		"main":    map[string]any{"type": "Stack", "props": map[string]any{}, "children": []any{"status", "picked", "second", "literal", "picker", "buttons", "unsafe", "missing"}},
		"status":  map[string]any{"type": "StatusView", "props": map[string]any{"action": "run"}},
		"picked":  map[string]any{"type": "StatusView", "props": map[string]any{"action": "run", "app": selection}},
		"second":  map[string]any{"type": "StatusView", "props": map[string]any{"action": "other", "app": selection}},
		"literal": map[string]any{"type": "StatusView", "props": map[string]any{"action": "run", "app": "edge"}},
		"picker": map[string]any{"type": "AppPicker", "props": map[string]any{
			"apps": map[string]any{"$state": "/data/targets"}, "value": map[string]any{"$bindState": "/local/selection"},
		}},
		"buttons": map[string]any{"type": "Actions", "props": map[string]any{}},
		"unsafe":  map[string]any{"type": "StatusView", "props": map[string]any{"action": "remove"}},
		"missing": map[string]any{"type": "StatusView", "props": map[string]any{"action": "undeclared"}},
	}
	p := map[string]any{
		"id": "inspector", "module": "sample", "enabled": true, "type": "PANEL_TYPE_SPEC", "slot": "module",
		"spec": map[string]any{"root": "main", "elements": elements, "state": map[string]any{
			"data": map[string]any{"targets": []any{"web", "api", "worker"}}, "local": map[string]any{"selection": "web"},
		}},
	}
	f.state["panelsList"] = []any{p}
	f.state["apps"] = map[string]any{"web": map[string]any{"enable": true}}
	rt := &projectRuntime{root: f.root, evalModuleState: func(context.Context, string) ([]byte, error) { return json.Marshal(f.state) }}
	return &specUIFixture{f, &moduleService{s: newUITestServer(t)}, rt, p, elements}
}

func (f *specUIFixture) request(t *testing.T, app, action string, targets ...string) *connect.Request[agentv1.OpenModuleUIRequest] {
	t.Helper()
	return connect.NewRequest(&agentv1.OpenModuleUIRequest{
		ModuleId: "sample", PanelId: "inspector", AppId: app, StatusAction: action, StatusApps: targets,
		ReviewRevision: testReviewRevision(t, f.root, f.store, f.state, "sample", "inspector"),
	})
}

func (f *specUIFixture) open(t *testing.T, app string, targets ...string) http.Header {
	t.Helper()
	ctx := context.WithValue(t.Context(), runtimeKey{}, f.rt)
	req := f.request(t, app, "run", targets...)
	res, err := f.m.openModuleUI(ctx, req, f.store)
	if err != nil {
		t.Fatal(err)
	}
	msg := res.Msg
	if msg.Url != "" || msg.DevUrl != "" || msg.Settings != nil || msg.ReviewRevision != req.Msg.ReviewRevision ||
		!slices.Equal(msg.Permissions, []string{"actions:run"}) || !slices.Equal(msg.ActionIds, []string{"run"}) ||
		len(msg.Actions) != 1 || msg.Actions["run"].GetLabel() != "Status" {
		t.Fatalf("unexpected spec grant projection: %v", msg)
	}
	h := http.Header{}
	h.Set(moduleUIGrantHeader, res.Header().Get(moduleUIGrantHeader))
	if h.Get(moduleUIGrantHeader) == "" || res.Header().Get(moduleUIExpiryHeader) == "" || res.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("missing host grant headers")
	}
	return h
}

func TestSpecUIGrantDispatch(t *testing.T) {
	// A declarative layout does not launch a dev server or need a realized UI
	// bundle; the machine custom UI policy must not block its action grant.
	t.Setenv("STACKPANEL_DISABLE_CUSTOM_UI", "1")
	picker := []string{"api", "web"} // deliberately omits the third offered app, worker
	web := []string{"web"}
	for _, tc := range []struct {
		name, app string
		reviewed  []string
		args      map[string]any
		want      connect.Code
	}{
		{"global", "", nil, nil, 0},
		{"picker", "", picker, map[string]any{"app": "api"}, 0},
		{"second reviewed app", "", picker, map[string]any{"app": "web"}, 0},
		{"unreviewed picker option", "", picker, map[string]any{"app": "worker"}, connect.CodePermissionDenied},
		{"unreviewed literal", "", picker, map[string]any{"app": "edge"}, connect.CodePermissionDenied},
		{"empty object with picker grant", "", picker, nil, connect.CodePermissionDenied},
		{"app with no-args grant", "", nil, map[string]any{"app": "api"}, connect.CodePermissionDenied},
		{"literal", "", []string{"edge"}, map[string]any{"app": "edge"}, 0},
		{"selected", "web", web, map[string]any{"app": "web"}, 0},
		{"other app", "web", web, map[string]any{"app": "api"}, connect.CodePermissionDenied},
		{"omitted app", "web", web, nil, connect.CodePermissionDenied},
		{"extra arg", "", picker, map[string]any{"app": "api", "force": true}, connect.CodePermissionDenied},
		{"wrong key", "", picker, map[string]any{"name": "api"}, connect.CodePermissionDenied},
		{"nonstring", "", picker, map[string]any{"app": nil}, connect.CodePermissionDenied},
		{"schema changed", "", picker, map[string]any{"app": "api"}, connect.CodePermissionDenied},
		{"wrong action", "", picker, map[string]any{"app": "api"}, connect.CodePermissionDenied},
		{"confirmation", "", nil, nil, connect.CodePermissionDenied},
		{"wrong module", "", nil, nil, connect.CodePermissionDenied},
		{"other project", "", nil, nil, connect.CodePermissionDenied},
		{"spec changed", "", nil, nil, connect.CodePermissionDenied},
		{"executable changed", "", nil, nil, connect.CodePermissionDenied},
		{"owned target changed", "", nil, nil, connect.CodePermissionDenied},
		{"profile changed", "", nil, nil, connect.CodePermissionDenied},
		{"warning added", "", nil, nil, connect.CodePermissionDenied},
		{"converted to iframe", "", nil, nil, connect.CodePermissionDenied},
		{"lost owner", "", nil, nil, connect.CodePermissionDenied},
		{"disabled module", "", nil, nil, connect.CodePermissionDenied},
		{"disabled app", "web", web, map[string]any{"app": "web"}, connect.CodePermissionDenied},
		{"disabled panel", "", nil, nil, connect.CodePermissionDenied},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newSpecUIFixture(t)
			if tc.app != "" {
				f.panel["slot"] = "app:tab"
			}
			h := f.open(t, tc.app, tc.reviewed...)
			switch tc.name {
			case "wrong action":
				f.req.ActionId = "other" // independently eligible at the very same app
			case "schema changed":
				f.action["argsSchema"] = map[string]any{"type": "object", "required": []any{"newArg"}}
			case "disabled app":
				f.state["apps"].(map[string]any)["web"].(map[string]any)["enable"] = false
			case "confirmation":
				f.req.ActionId = "remove"
			case "wrong module":
				f.req.ModuleId = "other"
			case "other project":
				f.rt.root = t.TempDir()
			case "spec changed":
				f.panel["spec"].(map[string]any)["state"] = map[string]any{"data": map[string]any{"label": "new"}}
			case "executable changed":
				f.action["script"] = f.script
			case "owned target changed":
				delete(f.state, "moduleOutputs")
			case "profile changed":
				if err := os.Remove(filepath.Join(f.root, ".stack/profile/profile")); err != nil {
					t.Fatal(err)
				}
			case "warning added":
				f.action["confirm"] = "Proceed?"
			case "converted to iframe":
				f.panel["type"] = "PANEL_TYPE_CUSTOM"
			case "lost owner":
				f.panel["module"] = "other"
			case "disabled module":
				f.module["enabled"] = false
			case "disabled panel":
				f.panel["enabled"] = false
			}
			if tc.args != nil {
				var err error
				f.req.Args, err = structpb.NewStruct(tc.args)
				if err != nil {
					t.Fatal(err)
				}
			}
			ctx := context.WithValue(t.Context(), runtimeKey{}, f.rt)
			var events []*agentv1.RunModuleActionResponse
			err := f.m.runModuleActionWithHeader(ctx, f.store, h, f.req, func(msg *agentv1.RunModuleActionResponse) error {
				events = append(events, msg)
				return nil
			})
			if tc.want != 0 {
				if connect.CodeOf(err) != tc.want || len(events) != 0 {
					t.Fatalf("got %v (%d events), want %v before exec", err, len(events), tc.want)
				}
				if _, err := os.Stat(filepath.Join(f.root, "ran")); !errors.Is(err, os.ErrNotExist) {
					t.Fatal("rejected status action executed")
				}
				return
			}
			if err != nil || len(events) != 2 || events[0].GetJson().GetStructValue() == nil || !maps.Equal(events[0].GetJson().GetStructValue().AsMap(), tc.args) {
				t.Fatalf("status read: %v, events %v", err, events)
			}
		})
	}
}

func TestStatusValueIDs(t *testing.T) {
	for _, valid := range []string{"_api", "café / east", strings.Repeat("界", 128)} {
		if !validStatusID(valid) {
			t.Errorf("rejected literal value %q", valid)
		}
	}
	for _, invalid := range []string{"", " trailing ", "a\nb", "a\u202eb", "a\u2028b", "a\u2029b", "__proto__", "prototype", strings.Repeat("界", 129)} {
		if validStatusID(invalid) {
			t.Errorf("accepted invalid value %q", invalid)
		}
	}
}

func TestSpecScopedValueIDsExecute(t *testing.T) {
	f := newSpecUIFixture(t)
	f.panel["slot"] = "app:tab"
	f.state["apps"] = map[string]any{"_api": map[string]any{"enable": true}}
	f.module["actions"].(map[string]any)["_action"] = f.action
	f.elements["literal"].(map[string]any)["props"] = map[string]any{"action": "_action", "app": "_api"}
	ctx := context.WithValue(t.Context(), runtimeKey{}, f.rt)
	res, err := f.m.openModuleUI(ctx, f.request(t, "_api", "_action", "_api"), f.store)
	if err != nil {
		t.Fatal(err)
	}
	f.req.ActionId = "_action"
	f.req.Args, _ = structpb.NewStruct(map[string]any{"app": "_api"})
	var app string
	err = f.m.runModuleActionWithHeader(ctx, f.store, res.Header(), f.req, func(ev *agentv1.RunModuleActionResponse) error {
		if obj := ev.GetJson().GetStructValue(); obj != nil {
			app = obj.GetFields()["app"].GetStringValue()
		}
		return nil
	})
	if err != nil || app != "_api" {
		t.Fatalf("scoped status read: app=%q, err=%v", app, err)
	}
}

func TestSpecOpenRejectsUnreviewableTargets(t *testing.T) {
	for _, tc := range []struct {
		name, action, app string
		targets           []string
	}{
		{"no action", "", "", nil},
		{"wildcard button only", "buttonsOnly", "", nil},
		{"confirmed action", "remove", "", nil},
		{"undeclared action", "undeclared", "", nil},
		{"picker is not a no-args view", "other", "", nil},
		{"not offered", "run", "", []string{"absent"}},
		{"union of different views", "run", "", []string{"web", "edge"}},
		{"empty app", "run", "", []string{""}},
		{"duplicate apps", "run", "", []string{"api", "api"}},
		{"unsafe app", "run", "", []string{"prototype"}},
		{"excess apps", "run", "", make([]string, 129)},
		{"scope mismatch", "run", "web", []string{"api"}},
		{"scope widened", "run", "web", []string{"web", "api"}},
		{"scoped no-args", "run", "web", nil},
		{"no project app", "run", "api", []string{"api"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newSpecUIFixture(t)
			if tc.app != "" {
				f.panel["slot"] = "app:tab"
			}
			req := f.request(t, tc.app, tc.action, tc.targets...)
			ctx := context.WithValue(t.Context(), runtimeKey{}, f.rt)
			if res, err := f.m.openModuleUI(ctx, req, f.store); res != nil || connect.CodeOf(err) != connect.CodePermissionDenied {
				t.Fatalf("opened outside review: response %v, err %v", res, err)
			}
		})
	}
}

func TestSpecStatusPreflightReportsBothEligibleActions(t *testing.T) {
	f := newSpecUIFixture(t)
	ids, err := statusActionIDs(f.panel["spec"].(map[string]any), f.module["actions"].(map[string]any))
	if err != nil || !slices.Equal(ids, []string{"other", "run"}) {
		t.Fatalf("preflight actions: %v, %v", ids, err)
	}
	ctx := context.WithValue(t.Context(), runtimeKey{}, f.rt)
	res, err := f.m.openModuleUI(ctx, f.request(t, "", "other", "api"), f.store)
	if err != nil || !slices.Equal(res.Msg.ActionIds, []string{"other"}) || len(res.Msg.Actions) != 1 || res.Msg.Actions["other"] == nil {
		t.Fatalf("second action's separate review: %v, %v", res, err)
	}
}

func TestSpecOpenChecksEachTargetAgainstActionSchema(t *testing.T) {
	f := newSpecUIFixture(t)
	f.action["argsSchema"] = map[string]any{
		"type": "object", "required": []any{"app"},
		"properties": map[string]any{"app": map[string]any{"$ref": "#/$defs/app"}},
		"$defs":      map[string]any{"app": map[string]any{"not": map[string]any{"const": "worker"}}},
	}
	f.open(t, "", "web", "api")
	ctx := context.WithValue(t.Context(), runtimeKey{}, f.rt)
	for _, targets := range [][]string{nil, {"web", "worker"}} {
		req := f.request(t, "", "run", targets...)
		if res, err := f.m.openModuleUI(ctx, req, f.store); res != nil || connect.CodeOf(err) != connect.CodePermissionDenied {
			t.Fatalf("approved schema-invalid targets %v: %v, %v", targets, res, err)
		}
	}
}

func TestSpecOpenRejectsStaleReview(t *testing.T) {
	f := newSpecUIFixture(t)
	req := f.request(t, "", "run", "web")
	// Still a valid open for the same action and app, but no longer what was reviewed.
	f.panel["title"] = "Renamed panel"
	ctx := context.WithValue(t.Context(), runtimeKey{}, f.rt)
	if res, err := f.m.openModuleUI(ctx, req, f.store); res != nil || connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("stale review opened: %v, %v", res, err)
	}
}

func TestSpecPickerMaximumLiteralList(t *testing.T) {
	f := newSpecUIFixture(t)
	apps, targets := make([]any, 128), make([]string, 128)
	for i := range targets {
		targets[i] = fmt.Sprintf("%0128d", i)
		apps[i] = targets[i]
	}
	picker := f.elements["picker"].(map[string]any)["props"].(map[string]any)
	picker["apps"] = apps
	spec := f.panel["spec"].(map[string]any)
	spec["state"].(map[string]any)["local"] = map[string]any{"selection": ""}
	h := f.open(t, "", targets...)
	f.req.Args, _ = structpb.NewStruct(map[string]any{"app": targets[127]})
	if err := f.m.s.checkActionGrant(h, f.rt, f.state, f.req, moduleActionProfile(f.root, f.store, f.state)); err != nil {
		t.Fatalf("valid maximum-size grant unusable: %v", err)
	}
	picker["apps"] = append(apps, "overflow")
	if _, err := statusActionIDs(spec, f.module["actions"].(map[string]any)); err == nil {
		t.Fatal("129 unique safe options eligible for review")
	}
}

func TestSpecUIGrantOperationIsolation(t *testing.T) {
	f := newSpecUIFixture(t)
	h := f.open(t, "")
	ctx := context.WithValue(t.Context(), runtimeKey{}, f.rt)
	req := f.request(t, "", "run")
	req.Header().Set(moduleUIGrantHeader, h.Get(moduleUIGrantHeader))
	if _, err := f.m.openModuleUI(ctx, req, f.store); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("refreshed spec grant: %v", err)
	}
	if err := f.m.s.checkModuleProxyGrant(h, f.rt, f.state, "sample"); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Errorf("spec grant accepted for proxy: %v", err)
	}
	if _, _, err := f.m.s.moduleUIConfigPatchScope(h, f.rt, f.state, "sample"); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("granted settings patch: %v", err)
	}
	if _, err := evaluatedModuleBundle(f.state, "sample", "inspector", f.store); err == nil {
		t.Fatal("spec resolved as authenticated asset bundle")
	}
	_, custom, _ := uiTestState()
	f.panel["type"], f.panel["uiBundle"] = "PANEL_TYPE_CUSTOM", custom["uiBundle"]
	f.panel["uiBundle"].(map[string]any)["permissions"] = []any{"actions:run", "config:read"}
	if err := f.m.s.checkActionGrant(h, f.rt, f.state, f.req, moduleActionProfile(f.root, f.store, f.state)); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("transferred status grant to replacement iframe: %v", err)
	}
}

func TestSpecUIRejectsMalformedTree(t *testing.T) {
	for _, scenario := range []string{"missing root", "dangling child", "cycle", "shared child", "unreachable", "leaf children", "nonliteral action", "missing type", "wrong props", "nonlist children"} {
		t.Run(scenario, func(t *testing.T) {
			f := newSpecUIFixture(t)
			spec := f.panel["spec"].(map[string]any)
			main := f.elements["main"].(map[string]any)
			status := f.elements["status"].(map[string]any)
			switch scenario {
			case "missing root":
				spec["root"] = "none"
			case "dangling child":
				delete(f.elements, "status")
			case "cycle":
				main["children"] = []any{"main"}
			case "shared child":
				main["children"] = append(main["children"].([]any), "status")
			case "unreachable":
				f.elements["ghost"] = status
			case "leaf children":
				main["type"] = "Actions"
			case "nonliteral action":
				status["props"].(map[string]any)["action"] = map[string]any{"$state": "/data/name"}
			case "missing type":
				delete(main, "type")
			case "wrong props":
				main["props"] = []any{}
			case "nonlist children":
				main["children"] = "status"
			}
			if _, err := statusActionIDs(spec, f.module["actions"].(map[string]any)); connect.CodeOf(err) != connect.CodeFailedPrecondition {
				t.Fatalf("malformed graph eligible for review: %v", err)
			}
		})
	}
}

func TestSpecRejectsMalformedAppSources(t *testing.T) {
	for _, tc := range []struct {
		name, node, prop string
		value            any
	}{
		{"null target", "picked", "app", nil},
		{"unsafe literal", "picked", "app", "constructor"},
		{"ambient app", "picked", "app", map[string]any{"$state": "/app/id"}},
		{"missing picker", "picked", "app", map[string]any{"$state": "/local/other"}},
		{"nested path", "picked", "app", map[string]any{"$state": "/local/selection/child"}},
		{"mixed expression", "picked", "app", map[string]any{"$state": "/local/selection", "fallback": "web"}},
		{"read-only picker", "picker", "value", map[string]any{"$state": "/local/selection"}},
		{"undeclared local", "picker", "value", map[string]any{"$bindState": "/local/missing"}},
		{"unsafe data path", "picker", "apps", map[string]any{"$state": "/data/toString"}},
		{"missing public data", "picker", "apps", map[string]any{"$state": "/data/missing"}},
		{"private options", "picker", "apps", map[string]any{"$state": "/local/selection"}},
		{"nonstring option", "picker", "apps", []any{"web", false}},
		{"duplicate option", "picker", "apps", []any{"web", "web"}},
		{"unsafe option", "picker", "apps", []any{"web", "api\nother"}},
		{"prototype option", "picker", "apps", []any{"web", "prototype"}},
		{"unoffered initial value", "picker", "apps", []any{"api"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newSpecUIFixture(t)
			f.elements[tc.node].(map[string]any)["props"].(map[string]any)[tc.prop] = tc.value
			if _, err := statusActionIDs(f.panel["spec"].(map[string]any), f.module["actions"].(map[string]any)); err == nil {
				t.Fatal("malformed authority eligible for review")
			}
		})
	}
	t.Run("two pickers write same local", func(t *testing.T) {
		f := newSpecUIFixture(t)
		f.elements["buttons"] = f.elements["picker"]
		if _, err := statusActionIDs(f.panel["spec"].(map[string]any), f.module["actions"].(map[string]any)); err == nil {
			t.Fatal("ambiguous binding eligible for review")
		}
	})
}

func TestExistingCustomGrantDeniedByPolicyOrSpec(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	f := newSpecUIFixture(t)
	_, custom, _ := uiTestState()
	f.panel["type"], f.panel["uiBundle"] = "PANEL_TYPE_CUSTOM", custom["uiBundle"]
	f.panel["uiBundle"].(map[string]any)["permissions"] = []any{"actions:run"}
	grant, err := f.m.s.issueModuleUIGrant(f.root, f.state, "sample", "inspector", "", moduleStoreRoot, userconfig.LinkedModule{})
	if err != nil {
		t.Fatal(err)
	}
	h := http.Header{}
	h.Set(moduleUIGrantHeader, grant)
	check := func() error { return f.m.s.checkActionGrant(h, f.rt, f.state, f.req, "") }
	if err := check(); err != nil {
		t.Fatal("custom grant unusable before policy change:", err)
	}
	t.Run("disable", func(t *testing.T) {
		t.Setenv("STACKPANEL_DISABLE_CUSTOM_UI", "1")
		if err := check(); connect.CodeOf(err) != connect.CodePermissionDenied {
			t.Fatalf("old iframe grant accepted after opt-out: %v", err)
		}
		// Authenticated direct reads must stop before resolving a package too.
		f.rt.evalModuleState = func(context.Context, string) ([]byte, error) {
			t.Fatal("disabled direct asset request evaluated a bundle")
			return nil, nil
		}
		r := httptest.NewRequestWithContext(context.WithValue(t.Context(), runtimeKey{}, f.rt), "GET", "http://localhost/index.html", nil)
		r.SetPathValue("module", "sample")
		r.SetPathValue("panel", "inspector")
		r.SetPathValue("rest", "index.html")
		w := httptest.NewRecorder()
		f.m.s.handleModuleAsset(w, r)
		if w.Code != http.StatusNotFound {
			t.Fatalf("disabled authenticated asset route returned %d", w.Code)
		}
	})
	f.panel["type"], f.panel["uiBundle"] = "PANEL_TYPE_SPEC", nil
	if err := check(); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("transferred iframe grant to spec: %v", err)
	}
}
