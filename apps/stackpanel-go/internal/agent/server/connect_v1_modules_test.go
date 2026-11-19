package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"maps"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"connectrpc.com/connect"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/structpb"

	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/gopbconnect"
	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

// No nixpkgs, lockfile, shell profile, network inputs or derivations. Both
// consumers expose the real flake function/data boundary used by ModuleService.
const moduleTestFlake = `{
  outputs = { self }: let
    tree = builtins.pathExists ./.stack/config/modules.nix;
    cfg = if tree then { modules = import ./.stack/config/modules.nix; } else import ./.stack/config.nix;
    enabled = if tree then cfg.modules.demo.enable else cfg.custom.active;
    settings = if tree then cfg.modules.demo.settings else cfg.custom.prefs;
    expected = if tree then [ "modules" "demo" "enable" ] else [ "custom" "active" ];
    mod = { id = "demo"; inherit enabled settings; readme = "Read me";
      linked = true; uiDevUrl = "https://untrusted.invalid";
      enablePath = if tree then "modules.demo.enable" else "custom.active";
      configPath = if tree then "modules.demo.settings" else "custom.prefs";
    };
    other = { id = "other"; enabled = true; };
    settingsPatch = attrs: if tree then { modules.demo.settings = attrs; } else { custom.prefs = attrs; };
    choice = value: label: attrs: { inherit value label; config = settingsPatch attrs; };
    offers = [
      { id = "adopt"; module = "demo"; revision = if settings.revBumped or false then 2 else 1;
        question = { type = "bool"; label = "Import existing config?"; description = "Import legacy settings.";
          order = 1; default = true; choices = []; }; config = settingsPatch { imported = "PRIVATE"; }; }
      { id = "layout"; module = "demo"; revision = 3; config = {};
        question = { type = "select"; label = "Which layout?"; description = null; order = 2; default = "compact"; choices = [
          (choice "compact" "Compact" { layout = "compact"; }) (choice "wide" "Wide" { layout = "wide"; })
          (choice "broken" "Incompatible" { layout = "broken"; reject = true; })
        ]; }; }
      { id = "tools"; module = "demo"; revision = 4; config = {};
        question = { type = "multiselect"; label = "Which tools?"; description = null; order = 3; default = ["bench"]; choices = [
          (choice "docs" "Documentation" { docs = true; }) (choice "lint" "Linting" { lint = true; })
          (choice "bench" "Benchmarks" { bench = true; })
        ]; }; }
    ];
    adoptionFiles = prefs:
      (if prefs ? imported then [{ path = "imported.json"; }] else [])
      ++ (if prefs ? layout then [{ path = "layout-" + prefs.layout + ".json"; }] else [])
      ++ map (name: { path = name + ".json"; }) (builtins.filter (name: prefs.${name} or false) ["docs" "lint" "bench"]);
    outputs = { files = [{ path = "demo.json"; content = "PRIVATE"; }] ++ adoptionFiles settings;
      services = [{ name = "demo-http"; proxy = { enable = true; port = 12080; }; }];
      scripts = []; packages = []; tasks = []; healthchecks = []; };
  in { legacyPackages.fixture = {
    stackpanelRawConfig = cfg;
    stackpanelSerializable = assert !(settings.reject or false); {
      modulesListAll = [mod other]; moduleOutputs.demo = outputs;
      secrets = { token = "PRIVATE"; };
    };
    stackpanelSpeculate = {enablePath ? null, adoption ? {}, ...}: let
      active = if enablePath == null then enabled else assert enablePath == expected; true;
      prefs = settings // (if tree then adoption.modules.demo.settings or {} else adoption.custom.prefs or {});
    in { files = [{path="shared"; content=if active then "PRIVATE" else "old";}]
      ++ (if active then [{path="demo.json";}] ++ adoptionFiles prefs else [{path="old";}]);
      packageFingerprints = { shared = if active then "2" else "1"; } // (if active then { demo-pkg = "1"; } else {});
      serviceFingerprints = if active then { demo-http = "new"; } else { legacy-http = "old"; };
      addons = if active then offers else [];
    };
  }; };
}`

func moduleFixtureFile(t *testing.T, root, name, data string) {
	t.Helper()
	path := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
}

func moduleFixtureSnapshot(t *testing.T, root string) map[string]string {
	t.Helper()
	files := map[string]string{}
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, err := os.ReadFile(path)
		files[path] = string(b)
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	return files
}

func moduleFixtureRequest[T any](project string, msg *T) *connect.Request[T] {
	r := connect.NewRequest(msg)
	r.Header().Set("Authorization", "Bearer paired")
	r.Header().Set(projectHeader, project)
	return r
}

func moduleFixtureClient(
	t *testing.T,
	roots map[string]string,
) (agentv1connect.ModuleServiceClient, *runtimeRegistry) {
	t.Helper()
	if _, err := exec.LookPath("nix"); err != nil {
		t.Skip("integration test requires Nix flakes")
	}
	t.Setenv("NIX_SYSTEM", "fixture")
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	t.Setenv(
		"NIX_CONFIG",
		os.Getenv(
			"NIX_CONFIG",
		)+"\nexperimental-features = nix-command flakes\nsubstituters =\nflake-registry =\n",
	)
	for _, root := range roots {
		moduleFixtureFile(t, root, "flake.nix", moduleTestFlake)
	}
	registry, _ := newTestRegistry()
	registry.create = func(root string) (*projectRuntime, error) {
		return &projectRuntime{root: root, store: nixdata.NewStore(root, nil)}, nil
	}
	deps := testV1Deps(
		func(token string) bool { return token == "paired" },
		agentv1connect.UnimplementedProjectServiceHandler{},
	)
	deps.modules = &moduleService{s: newUITestServer(t)}
	deps.scope = projectInterceptor{
		runtimes: registry,
		resolve: func(id string) (string, error) {
			if root, ok := roots[id]; ok {
				return root, nil
			}
			return "", connect.NewError(connect.CodeNotFound, errors.New("unknown project"))
		},
	}
	mux := http.NewServeMux()
	for _, route := range newV1Routes(deps) {
		mux.Handle(route.path, route.handler)
	}
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return agentv1connect.NewModuleServiceClient(srv.Client(), srv.URL), registry
}

func TestModuleRPCProjectPersistenceAndReadOnlyPreview(t *testing.T) {
	a, b := t.TempDir(), t.TempDir()
	client, registry := moduleFixtureClient(t, map[string]string{"a": a, "b": b})
	moduleFixtureFile(t, a, ".stack/config.nix", `{
  # This comment and expression belong to the user.
  untouched = 2 + 3;
  custom.active = false;
  custom.prefs.marker = "A";
}
`)
	moduleFixtureFile(t, b, ".stack/config/modules.nix", `{
  # Keep these bytes unchanged.
  demo.enable = false;
  demo.settings.marker = "B";
}
`)
	ctx := t.Context()
	if _, err := client.ListModules(
		ctx,
		connect.NewRequest(&agentv1.ListModulesRequest{}),
	); connect.CodeOf(
		err,
	) != connect.CodeUnauthenticated {
		t.Fatalf("no auth: %v", err)
	}
	for _, ids := range [][]string{nil, {""}, {"a", "b"}, {"a,b"}} {
		req := connect.NewRequest(&agentv1.EnableModuleRequest{ModuleId: "demo"})
		req.Header().Set("Authorization", "Bearer paired")
		for _, id := range ids {
			req.Header().Add(projectHeader, id)
		}
		_, err := client.EnableModule(ctx, req)
		require.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err))
	}
	require.Empty(
		t,
		registry.runtimes,
		"ambiguous writes must be rejected before project startup",
	)
	list, err := client.ListModules(
		ctx,
		moduleFixtureRequest("a", &agentv1.ListModulesRequest{}),
	)
	if err != nil {
		t.Fatal(err)
	}
	require.Len(t, list.Msg.Modules, 2)
	require.False(t, list.Msg.Modules[0].Enabled)
	require.True(t, list.Msg.Modules[1].Enabled)
	require.False(t, list.Msg.Modules[0].Linked)
	require.Nil(t, list.Msg.Modules[0].UiDevUrl)
	if _, err := client.GetModule(
		ctx,
		moduleFixtureRequest("a", &agentv1.GetModuleRequest{ModuleId: "missing"}),
	); connect.CodeOf(
		err,
	) != connect.CodeNotFound {
		t.Fatalf("missing: %v", err)
	}
	if _, err := client.GetModule(
		ctx,
		moduleFixtureRequest("a", &agentv1.GetModuleRequest{}),
	); connect.CodeOf(
		err,
	) != connect.CodeInvalidArgument {
		t.Fatalf("empty id: %v", err)
	}
	outputs, err := client.GetModuleOutputs(
		ctx,
		moduleFixtureRequest("a", &agentv1.GetModuleOutputsRequest{ModuleId: "demo"}),
	)
	if err != nil {
		t.Fatal(err)
	}
	o := outputs.Msg.Outputs
	require.Equal(t, "demo", o.ModuleId)
	require.Len(t, o.Files, 1)
	require.Equal(t, "demo.json", o.Files[0].Path)
	require.Len(t, o.Services, 1)
	require.True(t, o.Services[0].ProxyEnabled)
	require.NotContains(t, o.String(), "PRIVATE")

	original := moduleFixtureSnapshot(t, a)
	result, err := client.PreviewModuleEnable(
		ctx,
		moduleFixtureRequest("a", &agentv1.PreviewModuleEnableRequest{ModuleId: "demo"}),
	)
	if err != nil {
		t.Fatal(err)
	}
	p := result.Msg.Preview
	require.Equal(t, []string{"old", "shared"}, p.Files.Before)
	require.Equal(t, []string{"demo.json", "shared"}, p.Files.After)
	require.Equal(t, []string{"shared"}, p.Files.Changed)
	require.Equal(t, []string{"old"}, p.Files.Removed)
	require.Equal(t, []string{"demo.json"}, p.Files.Added)
	require.Equal(t, []string{"demo-pkg"}, p.Packages.Added)
	require.Equal(t, []string{"shared"}, p.Packages.Changed)
	require.Equal(t, []string{"demo-http"}, p.Services.Added)
	require.Equal(t, []string{"legacy-http"}, p.Services.Removed)
	require.Len(t, p.Offers, 3)
	require.NotContains(t, p.String(), "PRIVATE")
	if !maps.Equal(original, moduleFixtureSnapshot(t, a)) {
		t.Fatal("preview wrote project files")
	}

	get := func(project string) *agentv1.Module {
		t.Helper()
		res, err := client.GetModule(
			ctx,
			moduleFixtureRequest(project, &agentv1.GetModuleRequest{ModuleId: "demo"}),
		)
		if err != nil {
			t.Fatal(err)
		}
		return res.Msg.Module
	}
	other := moduleFixtureSnapshot(t, b)
	if _, err := client.EnableModule(
		ctx,
		moduleFixtureRequest("a", &agentv1.EnableModuleRequest{ModuleId: "demo"}),
	); err != nil {
		t.Fatal(err)
	}
	key := `option."${name}"`
	val := "line 1\n${not-an-expression} 'test'"
	settings, err := structpb.NewStruct(
		map[string]any{
			key:      val,
			"nested": map[string]any{"list": []any{true, 3, "${name}"}},
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.UpdateModuleConfig(
		ctx,
		moduleFixtureRequest(
			"a",
			&agentv1.UpdateModuleConfigRequest{ModuleId: "demo", Settings: settings},
		),
	); err != nil {
		t.Fatal(err)
	}
	m := get("a")
	if !m.Enabled || m.GetReadmeContent() != "Read me" ||
		m.Settings.AsMap()[key] != val ||
		m.Settings.AsMap()["marker"] != "A" {
		t.Fatalf("config round trip: %v", m)
	}
	if bmod := get(
		"b",
	); bmod.Enabled || bmod.Settings.AsMap()["marker"] != "B" ||
		!maps.Equal(other, moduleFixtureSnapshot(t, b)) {
		t.Fatalf("project b affected: %v", bmod)
	}
	aFiles := moduleFixtureSnapshot(t, a)
	bad, err := structpb.NewStruct(map[string]any{"reject": true})
	require.NoError(t, err)
	_, err = client.UpdateModuleConfig(
		ctx,
		moduleFixtureRequest(
			"a",
			&agentv1.UpdateModuleConfigRequest{ModuleId: "demo", Settings: bad},
		),
	)
	require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))
	require.Equal(
		t,
		aFiles,
		moduleFixtureSnapshot(t, a),
		"rejected config must restore exact bytes",
	)
	if len(original) != len(aFiles) ||
		!strings.Contains(
			aFiles[filepath.Join(a, ".stack/config.nix")],
			"  # This comment and expression belong to the user.\n  untouched = 2 + 3;",
		) {
		t.Fatal("config edit rewrote unrelated files or fields")
	}
	if _, err := client.EnableModule(
		ctx,
		moduleFixtureRequest("b", &agentv1.EnableModuleRequest{ModuleId: "demo"}),
	); err != nil {
		t.Fatal(err)
	}
	if !get("b").Enabled {
		t.Fatal("tree edit not visible to pure eval")
	}
	if _, err := client.DisableModule(
		ctx,
		moduleFixtureRequest("a", &agentv1.DisableModuleRequest{ModuleId: "demo"}),
	); err != nil {
		t.Fatal(err)
	}
	if get("a").Enabled || !get("b").Enabled {
		t.Fatal("disable crossed project scopes")
	}
}

func TestModuleRPCAdoption(t *testing.T) {
	root := t.TempDir()
	client, _ := moduleFixtureClient(t, map[string]string{"project": root})
	moduleFixtureFile(t, root, ".stack/config/modules.nix", `{
  # This project predates demo adoption.
  demo.enable = false;
  demo.settings.marker = "keep";
}
`)
	ctx := t.Context()
	preview := func(answers ...*agentv1.ModuleAdoptionAnswer) *agentv1.ModulePreview {
		t.Helper()
		before := moduleFixtureSnapshot(t, root)
		res, err := client.PreviewModuleEnable(
			ctx,
			moduleFixtureRequest(
				"project",
				&agentv1.PreviewModuleEnableRequest{ModuleId: "demo", Answers: answers},
			),
		)
		require.NoError(t, err)
		require.Equal(
			t,
			before,
			moduleFixtureSnapshot(t, root),
			"preview must not edit config or ledger",
		)
		require.NotContains(t, res.Msg.Preview.String(), "PRIVATE")
		return res.Msg.Preview
	}
	enable := func(answers ...*agentv1.ModuleAdoptionAnswer) error {
		_, err := client.EnableModule(
			ctx,
			moduleFixtureRequest(
				"project",
				&agentv1.EnableModuleRequest{ModuleId: "demo", Answers: answers},
			),
		)
		return err
	}
	disable := func() {
		t.Helper()
		_, err := client.DisableModule(
			ctx,
			moduleFixtureRequest("project", &agentv1.DisableModuleRequest{ModuleId: "demo"}),
		)
		require.NoError(t, err)
	}
	get := func() *agentv1.Module {
		t.Helper()
		res, err := client.GetModule(
			ctx,
			moduleFixtureRequest("project", &agentv1.GetModuleRequest{ModuleId: "demo"}),
		)
		require.NoError(t, err)
		return res.Msg.Module
	}
	seen := func() map[string]reconcile.LedgerEntry {
		t.Helper()
		data, err := os.ReadFile(filepath.Join(root, ".stack/reconcile.json"))
		require.NoError(t, err)
		var ledger reconcile.Ledger
		require.NoError(t, json.Unmarshal(data, &ledger))
		require.Equal(t, 1, ledger.Version)
		return ledger.Seen
	}

	// Defaults are suggestions, not decisions: preview shows only enable's output.
	initial := preview()
	require.Equal(t, []string{"demo.json"}, initial.Files.Added)
	require.Len(t, initial.Offers, 3)
	offers := map[string]*agentv1.ModuleAdoptionOffer{}
	for _, o := range initial.Offers {
		offers[o.Id] = o
	}
	for _, want := range []struct {
		id, typ, rev string
		def          any
		choices      map[string]string
	}{
		{"adopt", "bool", "1", true, map[string]string{}},
		{"layout", "select", "3", "compact", map[string]string{"compact": "Compact", "wide": "Wide", "broken": "Incompatible"}},
		{"tools", "multiselect", "4", []any{"bench"}, map[string]string{"docs": "Documentation", "lint": "Linting", "bench": "Benchmarks"}},
	} {
		o := offers[want.id]
		require.NotNil(t, o, want.id)
		require.Equal(t, want.typ, o.Type, want.id)
		require.Equal(t, want.rev, o.Revision, want.id)
		require.Equal(t, want.def, o.Default.AsInterface(), want.id)
		choices := map[string]string{}
		for _, c := range o.Choices {
			choices[c.Value] = c.Label
		}
		require.Equal(t, want.choices, choices, want.id)
	}
	answer := func(id string, value any) *agentv1.ModuleAdoptionAnswer {
		t.Helper()
		v, err := structpb.NewValue(value)
		require.NoError(t, err)
		return &agentv1.ModuleAdoptionAnswer{
			Id:       id,
			Revision: offers[id].Revision,
			Answer:   v,
		}
	}

	// An explicit no is recorded; omitted select/multiselect are still pending.
	stale := answer("adopt", true)
	require.NoError(t, enable(answer("adopt", false)))
	m := get()
	require.True(t, m.Enabled)
	require.Equal(t, map[string]any{"marker": "keep"}, m.Settings.AsMap())
	declined := seen()
	require.Len(t, declined, 1)
	require.Equal(t, 1, declined["adopt"].Revision)
	require.Equal(t, false, declined["adopt"].Answer)
	disable()
	pending := preview().Offers
	var ids []string
	for _, o := range pending {
		ids = append(ids, o.Id)
	}
	require.ElementsMatch(t, []string{"layout", "tools"}, ids)

	// Change the actual evaluated offer revision after the first preview.
	bump, err := structpb.NewStruct(map[string]any{"revBumped": true})
	require.NoError(t, err)
	_, err = client.UpdateModuleConfig(
		ctx,
		moduleFixtureRequest(
			"project",
			&agentv1.UpdateModuleConfigRequest{ModuleId: "demo", Settings: bump},
		),
	)
	require.NoError(t, err)
	before := moduleFixtureSnapshot(t, root)
	for _, tc := range []struct {
		name string
		bad  *agentv1.ModuleAdoptionAnswer
		code connect.Code
	}{
		{"stale preview revision", stale, connect.CodeFailedPrecondition},
		{"wrong multiselect type", answer("tools", "lint"), connect.CodeInvalidArgument},
		{"unknown multiselect choice", answer("tools", []any{"docs", "unknown"}), connect.CodeInvalidArgument},
	} {
		batch := []*agentv1.ModuleAdoptionAnswer{answer("layout", "wide"), tc.bad}
		_, err := client.PreviewModuleEnable(
			ctx,
			moduleFixtureRequest(
				"project",
				&agentv1.PreviewModuleEnableRequest{ModuleId: "demo", Answers: batch},
			),
		)
		require.Equal(t, tc.code, connect.CodeOf(err), tc.name)
		require.Equal(t, before, moduleFixtureSnapshot(t, root), tc.name)
		require.Equal(t, tc.code, connect.CodeOf(enable(batch...)), tc.name)
		require.Equal(t, before, moduleFixtureSnapshot(t, root), tc.name)
	}

	revised := preview()
	require.Equal(t, []string{"demo.json"}, revised.Files.Added)
	require.Len(t, revised.Offers, 3)
	for _, o := range revised.Offers {
		offers[o.Id] = o
	}
	require.Equal(t, "2", offers["adopt"].Revision)
	require.Equal(t, "revised", offers["adopt"].Reason)
	adopt, tools := answer("adopt", true), answer("tools", []any{"docs", "lint"})

	// A declared, type-correct choice can speculate successfully but fail the
	// real stackpanelSerializable eval after patching. Restore even ledger bytes.
	broken := answer("layout", "broken")
	require.Contains(t, preview(adopt, tools, broken).Files.Added, "layout-broken.json")
	require.Equal(
		t,
		connect.CodeFailedPrecondition,
		connect.CodeOf(enable(adopt, tools, broken)),
	)
	require.Equal(
		t,
		before,
		moduleFixtureSnapshot(t, root),
		"post-patch eval failure must restore all files",
	)

	wide := answer("layout", "wide")
	chosen := preview(adopt, tools, wide)
	require.Equal(t, revised.Files.Before, chosen.Files.Before)
	require.Equal(
		t,
		[]string{
			"demo.json",
			"docs.json",
			"imported.json",
			"layout-wide.json",
			"lint.json",
		},
		chosen.Files.Added,
	)
	require.NoError(t, enable(adopt, tools, wide))
	m = get()
	require.True(t, m.Enabled)
	require.Equal(
		t,
		map[string]any{
			"marker":    "keep",
			"revBumped": true,
			"imported":  "PRIVATE",
			"layout":    "wide",
			"docs":      true,
			"lint":      true,
		},
		m.Settings.AsMap(),
	)
	outputs, err := client.GetModuleOutputs(
		ctx,
		moduleFixtureRequest("project", &agentv1.GetModuleOutputsRequest{ModuleId: "demo"}),
	)
	require.NoError(t, err)
	var files []string
	for _, f := range outputs.Msg.Outputs.Files {
		files = append(files, f.Path)
	}
	require.ElementsMatch(
		t,
		chosen.Files.Added,
		files,
		"committed outputs must agree with the chosen preview",
	)
	records := seen()
	require.Len(t, records, 3)
	require.Equal(t, 2, records["adopt"].Revision)
	require.Equal(t, true, records["adopt"].Answer)
	require.Equal(t, 3, records["layout"].Revision)
	require.Equal(t, "wide", records["layout"].Answer)
	require.Equal(t, 4, records["tools"].Revision)
	require.Equal(t, []any{"docs", "lint"}, records["tools"].Answer)
	disable()
	require.Empty(
		t,
		preview().Offers,
		"disabling and re-enabling must not re-offer a recorded revision",
	)
}

func TestModuleStateErrorsDoNotExposePrivateEvalDiagnostics(t *testing.T) {
	rt := &projectRuntime{
		root:            t.TempDir(),
		evalModuleState: func(context.Context, string) ([]byte, error) { return nil, errors.New("PRIVATE") },
	}
	ctx := context.WithValue(t.Context(), runtimeKey{}, rt)
	_, err := (&moduleService{}).GetModule(
		ctx,
		connect.NewRequest(&agentv1.GetModuleRequest{ModuleId: "demo"}),
	)
	if connect.CodeOf(err) != connect.CodeFailedPrecondition ||
		strings.Contains(err.Error(), "PRIVATE") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLegacyRPCScopedFullProjectConfig(t *testing.T) {
	if _, err := exec.LookPath("nix"); err != nil {
		t.Skip("integration test requires Nix flakes")
	}
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	t.Setenv("NIX_SYSTEM", "fixture")
	t.Setenv(
		"NIX_CONFIG",
		os.Getenv(
			"NIX_CONFIG",
		)+"\nexperimental-features = nix-command flakes\nsubstituters =\nflake-registry =\n",
	)
	projects := t.TempDir()
	if errors.Is(project.QuickValidate(projects), project.ErrSuspiciousPath) {
		home, err := os.UserHomeDir()
		require.NoError(t, err)
		projects, err = os.MkdirTemp(home, ".stackpanel-v0-test-")
		require.NoError(t, err)
		t.Cleanup(func() { require.NoError(t, os.RemoveAll(projects)) })
	}
	mgr, err := project.NewManager(t.TempDir())
	require.NoError(t, err)
	ids := map[string]string{}
	for _, name := range []string{"a", "b"} {
		root := filepath.Join(projects, name)
		moduleFixtureFile(
			t,
			root,
			".stack/config.nix",
			fmt.Sprintf(`{ apps.web.name = "%s"; }`, name),
		)
		moduleFixtureFile(t, root, "flake.nix", `{
  outputs = { self }: let cfg = import ./.stack/config.nix; in { legacyPackages.fixture = {
    stackpanelRawConfig = cfg;
    stackpanelConfig = cfg // { variables.backend = "fixture"; variables.scope.value = "full-" + cfg.apps.web.name; };
  }; };
}`)
		registryCommand(t, root, "git", "init", "-q")
		registryCommand(t, root, "git", "add", "-f", "flake.nix", ".stack/config.nix")
		registryGitCommit(t, root, "test project")
		p, err := mgr.UserConfigManager().AddProject(root, name)
		require.NoError(t, err)
		ids[name] = p.ID
	}
	s := &Server{
		config:     &config.Config{ProjectRoot: filepath.Join(projects, "a")},
		projectMgr: mgr,
	}
	s.runtimes, _ = newTestRegistry()
	s.runtimes.create = func(root string) (*projectRuntime, error) {
		return &projectRuntime{root: root, store: nixdata.NewStore(root, nil)}, nil
	}
	mux := http.NewServeMux()
	mux.Handle(gopbconnect.NewAgentServiceHandler(NewAgentServiceServer(s)))
	server := httptest.NewServer(mux)
	defer server.Close()
	v0 := gopbconnect.NewAgentServiceClient(server.Client(), server.URL)
	ctx := t.Context()
	patch, err := v0.PatchNixData(
		ctx,
		moduleFixtureRequest(ids["b"], &gopb.PatchNixDataRequest{
			Entity: "apps", Key: "web", Path: "name", ValueType: "string", Value: `"patched"`,
		}),
	)
	require.NoError(t, err)
	require.True(t, patch.Msg.Success)
	require.Contains(t, patch.Msg.UpdatedJson, "patched")
	for id, expected := range map[string]string{"": "a", ids["b"]: "patched"} {
		apps, err := v0.GetApps(ctx, moduleFixtureRequest(id, &gopb.GetAppsRequest{}))
		require.NoError(t, err)
		require.Equal(t, expected, apps.Msg.GetApps()["web"].GetName())
		vars, err := v0.GetVariables(
			ctx,
			moduleFixtureRequest(id, &gopb.GetVariablesRequest{}),
		)
		require.NoError(t, err)
		require.Equal(t, "full-"+expected, vars.Msg.GetVariables()["scope"].GetValue())
		cfg, err := v0.GetNixConfig(
			ctx,
			moduleFixtureRequest(id, &gopb.GetNixConfigRequest{}),
		)
		require.NoError(t, err)
		require.Contains(t, cfg.Msg.ConfigJson, "full-"+expected)
	}
}

func TestModuleConfigGrantCheckedAgainstOperativeState(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	root := t.TempDir()
	moduleFixtureFile(t, root, ".stack/config.nix", "{ # unchanged\n}\n")
	server := newUITestServer(t)
	for _, mutation := range []string{"revoke", "retarget"} {
		t.Run(mutation, func(t *testing.T) {
			state, panel, module := uiTestState()
			bundle := panel["uiBundle"].(map[string]any)
			bundle["permissions"] = []any{"config:patch"}
			module["configPath"] = "custom.settings"
			grant, err := server.issueModuleUIGrant(
				root,
				state,
				"demo",
				"inspector",
				"",
				moduleStoreRoot,
				userconfig.LinkedModule{},
			)
			require.NoError(t, err)
			if mutation == "revoke" {
				bundle["permissions"] = []any{}
			} else {
				module["configPath"] = "other.settings"
			}
			rt := &projectRuntime{
				root:            root,
				store:           nixdata.NewStore(root, nil),
				evalModuleState: func(context.Context, string) ([]byte, error) { return json.Marshal(state) },
			}
			settings, err := structpb.NewStruct(map[string]any{"color": "blue"})
			require.NoError(t, err)
			req := moduleFixtureRequest(
				"selected",
				&agentv1.UpdateModuleConfigRequest{ModuleId: "demo", Settings: settings},
			)
			req.Header().Set(moduleUIGrantHeader, grant)
			before := moduleFixtureSnapshot(t, root)
			_, err = (&moduleService{s: server}).UpdateModuleConfig(
				context.WithValue(t.Context(), runtimeKey{}, rt),
				req,
			)
			require.Equal(t, connect.CodePermissionDenied, connect.CodeOf(err))
			require.Equal(t, before, moduleFixtureSnapshot(t, root))
		})
	}
}

// The request carries neither an app ID nor an option path. Only the host's
// launch grant selects the panel projection and the app's literal namespace.
func TestModuleRPCAppGrantPatchesOnlyProjectedSettings(t *testing.T) {
	root, other := t.TempDir(), t.TempDir()
	client, _ := moduleFixtureClient(t, map[string]string{"one": root, "two": other})
	const fixture = `{
  outputs = { self }: let
    cfg = import ./.stack/config.nix;
    projected = app: {
      inherit (app.demo) label retries;
      "with.dot" = app.demo."with.dot" or "default";
      fixed = "evaluated constant";
    };
  in { legacyPackages.fixture.stackpanelSerializable = {
    modulesListAll = [{id="demo"; enabled=true; settings = cfg.modules.demo.settings;}];
    apps = builtins.mapAttrs (_: _: {enable=true;}) cfg.apps;
    panelsList = [{id="preview"; module="demo"; enabled=true; type="PANEL_TYPE_CUSTOM"; slot="app:tab";
      apps = builtins.mapAttrs (_: app: {enabled=true; config=builtins.mapAttrs (_: v: toString v) (projected app);}) cfg.apps;
      uiBundle = {package=toString (builtins.path {path=./bundle; name="panel";}); entry="index.html";
        permissions = if cfg.apps.web.demo.label == "revoke" then ["config:read"] else ["config:read" "config:patch"];
        appSettings = builtins.mapAttrs (_: projected) cfg.apps;
        appSchemas = builtins.mapAttrs (id: _: {
          type = "object"; additionalProperties = false;
          properties = {
            label.type = "string"; fixed.type = "string"; "with.dot".type = "string";
            retries.type = if id == "web" then builtins.readFile ./retry-type else "integer";
          };
        }) cfg.apps;
      };
    }];
  }; };
}`
	const config = `{
  modules.demo.settings.label = "global";
  apps.web.demo.label = "web";
  apps.web.demo.retries = 1;
  apps.web.demo.hidden = "PRIVATE";
  apps.web.other.label = "unrelated"; # preserve me
  apps.api.demo = { label = "api"; retries = 2; };
}
`
	for _, dir := range []string{root, other} {
		moduleFixtureFile(t, dir, "flake.nix", fixture)
		moduleFixtureFile(t, dir, ".stack/config.nix", config)
		moduleFixtureFile(t, dir, "bundle/index.html", "<title>scoped</title>")
		moduleFixtureFile(t, dir, "retry-type", "integer")
	}
	open := func(app, grant string) (*connect.Response[agentv1.OpenModuleUIResponse], error) {
		req := moduleFixtureRequest(
			"one",
			&agentv1.OpenModuleUIRequest{ModuleId: "demo", PanelId: "preview", AppId: app},
		)
		req.Header().Set("Origin", "https://stackpanel.com")
		if grant == "" {
			state, err := loadModuleState(t.Context(), &projectRuntime{root: root})
			require.NoError(t, err)
			req.Msg.ReviewRevision = testReviewRevision(t, root, moduleStoreRoot, state, "demo", "preview")
		}
		if grant != "" {
			req.Header().Set(moduleUIGrantHeader, grant)
		}
		return client.OpenModuleUI(t.Context(), req)
	}
	launch, err := open("web", "")
	require.NoError(t, err)
	grant := launch.Header().Get(moduleUIGrantHeader)
	require.NotEmpty(t, grant)
	require.Equal(t, "web", launch.Msg.GetSettings().AsMap()["label"])
	require.NotContains(t, launch.Msg.GetSettings().AsMap(), "hidden")
	patch := func(project, id, token string, data map[string]any) error {
		settings, err := structpb.NewStruct(data)
		require.NoError(t, err)
		req := moduleFixtureRequest(
			project,
			&agentv1.UpdateModuleConfigRequest{ModuleId: id, Settings: settings},
		)
		req.Header().Set(moduleUIGrantHeader, token)
		_, err = client.UpdateModuleConfig(t.Context(), req)
		return err
	}
	beforeOther := moduleFixtureSnapshot(t, other)
	value := "${literal}"
	require.NoError(
		t,
		patch(
			"one",
			"demo",
			grant,
			map[string]any{"label": "edited", "retries": 3, "with.dot": value},
		),
	)
	fresh, err := open("web", grant)
	require.NoError(t, err)
	require.Equal(
		t,
		map[string]any{
			"label":    "edited",
			"retries":  float64(3),
			"with.dot": value,
			"fixed":    "evaluated constant",
		},
		fresh.Msg.GetSettings().AsMap(),
	)
	second, err := open("api", "")
	require.NoError(t, err)
	require.Equal(t, "api", second.Msg.GetSettings().AsMap()["label"])
	_, err = open("api", grant)
	require.Equal(t, connect.CodePermissionDenied, connect.CodeOf(err))
	boundRead := moduleFixtureRequest("one", &agentv1.GetModuleRequest{ModuleId: "demo"})
	boundRead.Header().Set(moduleUIGrantHeader, grant)
	_, err = client.GetModule(t.Context(), boundRead)
	require.Equal(t, connect.CodePermissionDenied, connect.CodeOf(err))
	global, err := client.GetModule(
		t.Context(),
		moduleFixtureRequest("one", &agentv1.GetModuleRequest{ModuleId: "demo"}),
	)
	require.NoError(t, err)
	require.Equal(t, "global", global.Msg.Module.Settings.AsMap()["label"])
	before := moduleFixtureSnapshot(t, root)
	require.Contains(
		t,
		before[filepath.Join(root, ".stack/config.nix")],
		`apps.web.other.label = "unrelated"; # preserve me`,
	)
	for _, tc := range []struct {
		project, id, token, key, value string
		code                           connect.Code
	}{
		{"one", "demo", grant, "hidden", "overwrite", connect.CodePermissionDenied},
		{"one", "demo", grant, "apps.api.demo.label", "overwrite", connect.CodePermissionDenied},
		{"one", "demo", grant, "fixed", "ignored", connect.CodeFailedPrecondition},
		{"one", "demo", grant, "label", "revoke", connect.CodePermissionDenied},
		{"one", "other", grant, "label", "wrong-module", connect.CodePermissionDenied},
		{"two", "demo", grant, "label", "wrong-project", connect.CodePermissionDenied},
		{"one", "demo", "", "label", "empty-grant", connect.CodePermissionDenied},
	} {
		err := patch(tc.project, tc.id, tc.token, map[string]any{tc.key: tc.value})
		require.Equal(t, tc.code, connect.CodeOf(err), "%s=%s", tc.key, tc.value)
		require.Equal(t, before, moduleFixtureSnapshot(t, root))
		require.Equal(t, beforeOther, moduleFixtureSnapshot(t, other))
	}
	// Both schemas accept the existing value 3. Only the selected app's
	// declared type changed: rejecting the old grant must precede any write.
	moduleFixtureFile(t, root, "retry-type", "number")
	afterSchemaChange := moduleFixtureSnapshot(t, root)
	err = patch("one", "demo", grant, map[string]any{"label": "stale"})
	require.Equal(t, connect.CodePermissionDenied, connect.CodeOf(err))
	require.Equal(t, afterSchemaChange, moduleFixtureSnapshot(t, root))
	reopened, err := open("web", "")
	require.NoError(t, err)
	require.NoError(
		t,
		patch(
			"one",
			"demo",
			reopened.Header().Get(moduleUIGrantHeader),
			map[string]any{"label": "fresh"},
		),
	)
}

func TestModuleActivationCannotEditProtectedSettings(t *testing.T) {
	if _, err := exec.LookPath("nix"); err != nil {
		t.Skip("requires Nix flakes")
	}
	root := t.TempDir()
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
	t.Setenv("NIX_SYSTEM", "fixture")
	moduleFixtureFile(t, root, "flake.nix", `{ outputs = { self }: {
  legacyPackages.fixture.stackpanelSerializable.modulesListAll = map (id: {
    inherit id; enablePath = "secrets.enable"; configPath = "secrets";
    enabled = (import ./.stack/config.nix).secrets.enable;
  }) [ "secrets" "unrelated" ];
}; }`)
	moduleFixtureFile(
		t,
		root,
		".stack/config.nix",
		`{ secrets = { enable = true; marker = "untouched"; }; }`,
	)
	ctx, modules, err := NewLocalModules(t.Context(), root)
	require.NoError(t, err)
	before := moduleFixtureSnapshot(t, root)
	_, err = modules.DisableModule(
		ctx,
		connect.NewRequest(&agentv1.DisableModuleRequest{ModuleId: "unrelated"}),
	)
	require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))
	settings, err := structpb.NewStruct(map[string]any{"marker": "changed"})
	require.NoError(t, err)
	_, err = modules.UpdateModuleConfig(
		ctx,
		connect.NewRequest(
			&agentv1.UpdateModuleConfigRequest{ModuleId: "secrets", Settings: settings},
		),
	)
	require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))
	require.Equal(t, before, moduleFixtureSnapshot(t, root))
	_, err = modules.DisableModule(
		ctx,
		connect.NewRequest(&agentv1.DisableModuleRequest{ModuleId: "secrets"}),
	)
	require.NoError(t, err)
	module, err := modules.GetModule(
		ctx,
		connect.NewRequest(&agentv1.GetModuleRequest{ModuleId: "secrets"}),
	)
	require.NoError(t, err)
	require.False(t, module.Msg.Module.Enabled)
}
