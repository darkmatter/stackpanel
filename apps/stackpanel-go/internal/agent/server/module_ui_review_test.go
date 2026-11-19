package server

import (
	"context"
	"encoding/json"
	"maps"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"connectrpc.com/connect"
	"github.com/stretchr/testify/require"

	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

// Exercise the actual cached RPC. In particular an ineligible entry with a
// project-provided marker must be stripped, not left alone on an early exit.
func TestGetNixConfigReviewsCopiesOfCachedPanels(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	t.Setenv("STACKPANEL_DISABLE_CUSTOM_UI", "0")
	root := t.TempDir()
	state, panel, mod := uiTestState()
	forged := map[string]any{"revision": strings.Repeat("f", 64), "devOrigin": "https://example.org"}
	panel["uiReview"] = forged
	list := []any{panel}
	add := func(id string, fields map[string]any) {
		p := maps.Clone(panel)
		p["id"] = id
		maps.Copy(p, fields)
		list = append(list, p)
	}
	add("disabled", map[string]any{"enabled": false})
	add("orphaned", map[string]any{"module": "unknown"})
	add("duplicate", nil)
	add("duplicate", map[string]any{"module": "other"})
	add("layout", map[string]any{"type": "PANEL_TYPE_SPEC", "uiBundle": nil, "spec": map[string]any{
		"root": "heading", "elements": map[string]any{"heading": map[string]any{"type": "Heading", "props": map[string]any{}}},
	}})
	add("builtin", map[string]any{"type": "PANEL_TYPE_TABS"})
	add("off", map[string]any{"module": "off"})
	state["modulesListAll"] = []any{mod, map[string]any{"id": "off", "enabled": false}}
	state["panelsList"] = list
	before, err := json.Marshal(state)
	require.NoError(t, err)

	s := newUITestServer(t)
	s.config.ProjectRoot = root
	s.projectMgr, err = project.NewManager(t.TempDir())
	require.NoError(t, err)
	s.runtimes, _ = newTestRegistry()
	s.runtimes.create = func(selected string) (*projectRuntime, error) {
		require.Equal(t, root, selected)
		return &projectRuntime{root: selected, flake: &FlakeWatcher{cachedConfig: state}, evalModuleState: func(context.Context, string) ([]byte, error) {
			t.Fatal("reviewing the cached config must not re-evaluate module state")
			return nil, nil
		}}, nil
	}
	res, err := NewAgentServiceServer(s).GetNixConfig(t.Context(), connect.NewRequest(&gopb.GetNixConfigRequest{}))
	require.NoError(t, err)
	require.True(t, res.Msg.Cached)
	var result map[string]any
	require.NoError(t, json.Unmarshal([]byte(res.Msg.ConfigJson), &result))
	rows := result["panelsList"].([]any)
	require.Len(t, rows, len(list))
	marker := rows[0].(map[string]any)["uiReview"].(map[string]any)
	require.Len(t, marker, 1)
	require.Regexp(t, "^[0-9a-f]{64}$", marker["revision"])
	for _, raw := range rows[1:] {
		require.NotContains(t, raw, "uiReview")
	}
	require.NotContains(t, res.Msg.ConfigJson, forged["revision"])
	after, err := json.Marshal(state)
	require.NoError(t, err)
	require.Equal(t, before, after, "the next cache reader must get the original maps AND list entries")
	delete(panel, "uiReview")
	revision, _ := newUIReviewSnapshot(root, moduleStoreRoot, state, s.config.Port).review(mod, panel)
	require.Equal(t, revision, marker["revision"], "an injected marker must not influence the agent's revision")
}

func TestUIReviewMatchesExecutionSnapshot(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	t.Setenv("STACKPANEL_DISABLE_CUSTOM_UI", "0")
	for _, change := range []string{"action script", "producer", "bare script target", "profile symlink", "panel", "module config", "proxy", "app visibility", "permissions"} {
		t.Run(change, func(t *testing.T) {
			f := newActionFixture(t, ":")
			_, p, _ := uiTestState()
			p["module"] = "sample"
			bundle := p["uiBundle"].(map[string]any)
			bundle["package"] = filepath.Join(f.store, testUIStoreName)
			bundle["permissions"] = []any{"actions:run", "service:proxy"}
			f.state["panelsList"] = []any{p}
			app := map[string]any{"enable": true}
			proxy := map[string]any{"enable": true, "port": float64(8111)}
			svc := map[string]any{"module": "sample", "enable": true, "proxy": proxy}
			f.state["services"], f.state["apps"] = map[string]any{"api": svc}, map[string]any{"web": app}
			// projectConfig contains editor-only service and app options;
			// neither a raw env nor another owner's outputs belong in this hash.
			full := maps.Clone(f.state)
			full["apps"] = map[string]any{"web": map[string]any{"enable": true, "env": "private"}}
			full["services"] = map[string]any{"api": map[string]any{"module": "sample", "enable": true, "command": "private", "proxy": proxy}}
			cfg := configWithUIReviews(f.root, f.store, full, 9876)
			marker := cfg["panelsList"].([]any)[0].(map[string]any)["uiReview"].(map[string]any)
			current := func() string {
				snapshot := newUIReviewSnapshot(f.root, f.store, f.state, 9876)
				rev, _ := snapshot.review(f.module, p)
				return rev
			}
			require.Equal(t, marker["revision"], current())
			switch change {
			case "action script":
				f.action["script"] = f.script
			case "producer":
				f.action["scriptDrvPath"] = f.script + ".drv"
			case "bare script target":
				owned := f.state["moduleOutputs"].(map[string]any)["sample"].(map[string]any)
				owned["scripts"].([]any)[0].(map[string]any)["binPath"] = f.script + "-other"
			case "profile symlink":
				other := f.profile + "-next"
				require.NoError(t, os.MkdirAll(filepath.Join(other, "bin"), 0o700))
				link := filepath.Join(f.root, ".stack", "profile", "profile")
				require.NoError(t, os.Remove(link))
				require.NoError(t, os.Symlink(other, link))
			case "panel":
				p["title"] = "Different document"
			case "module config":
				f.module["configPath"] = "other.settings"
			case "proxy":
				proxy["port"] = float64(8112)
			case "app visibility":
				app["enable"] = false
			case "permissions":
				bundle["permissions"] = []any{"actions:run"}
			}
			rev := current()
			require.NotEmpty(t, rev)
			require.NotEqual(t, marker["revision"], rev)
		})
	}
}

func TestUIReviewSpecRequiresExecutableProjection(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	f := newActionFixture(t, ":")
	p := map[string]any{
		"id": "status", "type": "PANEL_TYPE_SPEC", "module": "sample", "enabled": true,
		"spec": map[string]any{"root": "status", "elements": map[string]any{"status": map[string]any{
			"type": "StatusView", "props": map[string]any{"action": "run"},
		}}},
	}
	f.state["panelsList"] = []any{p}
	check := func() string {
		rev, origin := newUIReviewSnapshot(f.root, f.store, f.state, 9876).review(f.module, p)
		require.Empty(t, origin)
		return rev
	}
	rev := check()
	require.NotEmpty(t, rev)
	f.action["script"] = f.script
	changed := check()
	require.NotEmpty(t, changed)
	require.NotEqual(t, rev, changed)
	delete(f.action, "script") // public protobuf descriptor only
	require.Empty(t, check())
	f.action["script"] = "report"
	delete(f.state, "moduleOutputs") // bare name without an attributed binPath
	require.Empty(t, check())
	f.action["script"] = f.script
	f.action["confirm"] = "Mutate resources?"
	require.Empty(t, check())
	delete(f.action, "confirm")
	f.state["modulesListAll"] = []any{f.module, maps.Clone(f.module)}
	require.Empty(t, check())
}

func TestUIReviewPinsCustomLinkAndPhysicalRoot(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	t.Setenv("STACKPANEL_DISABLE_CUSTOM_UI", "0")
	state, p, mod := uiTestState()
	root, first, second, author := filepath.Join(t.TempDir(), "current"), t.TempDir(), t.TempDir(), t.TempDir()
	for _, dir := range []string{first, second, author} {
		moduleFixtureFile(t, dir, "flake.nix", "{}")
	}
	require.NoError(t, os.Symlink(first, root))
	check := func() (string, string) {
		return newUIReviewSnapshot(root, moduleStoreRoot, state, 9876).review(mod, p)
	}
	initial, origin := check()
	require.NotEmpty(t, initial)
	require.Empty(t, origin)
	require.NoError(t, os.Remove(root))
	require.NoError(t, os.Symlink(second, root))
	next, _ := check()
	require.NotEmpty(t, next)
	require.NotEqual(t, initial, next)

	mgr, err := userconfig.NewManager()
	require.NoError(t, err)
	set := func(url string) {
		require.NoError(t, mgr.SetLinkedModule(root, "demo", userconfig.LinkedModule{Path: author, UIDevURL: url}))
	}
	set("http://LOCALHOST:080/one")
	pinned := newUIReviewSnapshot(root, moduleStoreRoot, state, 9876)
	linked, origin := pinned.review(mod, p)
	require.NotEmpty(t, linked)
	require.NotEqual(t, next, linked)
	require.Equal(t, "http://localhost", origin)
	set("http://LOCALHOST:080/two")
	changed, sameOrigin := check()
	require.NotEmpty(t, changed)
	require.NotEqual(t, linked, changed)
	require.Equal(t, origin, sameOrigin)
	stillPinned, _ := pinned.review(mod, p)
	require.Equal(t, linked, stillPinned)
	set("http://127.0.0.1:9876/agent") // loopback alone does not make the agent a valid target
	invalid, origin := check()
	require.Empty(t, invalid)
	require.Empty(t, origin)
}

func TestUIReviewRequiresKnownCustomLinkState(t *testing.T) {
	path := filepath.Join(t.TempDir(), "user.yaml")
	t.Setenv("STACKPANEL_USER_CONFIG", path)
	t.Setenv("STACKPANEL_DISABLE_CUSTOM_UI", "0")
	root := t.TempDir()
	state, p, mod := uiTestState()
	snapshot := newUIReviewSnapshot(root, moduleStoreRoot, state, 9876)
	require.NotNil(t, snapshot.links)
	require.Empty(t, snapshot.links)
	require.NoError(t, os.WriteFile(path, []byte("projects: ["), 0o600))
	snapshot = newUIReviewSnapshot(root, moduleStoreRoot, state, 9876)
	require.Nil(t, snapshot.links)
	rev, origin := snapshot.review(mod, p)
	require.Empty(t, rev)
	require.Empty(t, origin)
}
