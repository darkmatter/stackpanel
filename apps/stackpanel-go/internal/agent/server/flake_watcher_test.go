package server

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/fsnotify/fsnotify"
)

type watchTestEval func(context.Context) ([]byte, error)

func (f watchTestEval) Eval(ctx context.Context) ([]byte, error) { return f(ctx) }
func (watchTestEval) Invalidate()                                {}

func flakeTestRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	atomicWatchFile(t, filepath.Join(root, "flake.nix"), "{}")
	return root
}

func atomicWatchFile(t *testing.T, path, value string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path+".tmp", []byte(value), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(path+".tmp", path); err != nil {
		t.Fatal(err)
	}
}

func startTestFlakeWatcher(
	t *testing.T,
	root string,
	eval watchTestEval,
) (*FlakeWatcher, <-chan SSEEvent) {
	t.Helper()
	s := &Server{sseSubscribers: make(map[chan SSEEvent]sseScope)}
	stream := s.subscribeSSE(sseScope{root: root, diagnostics: true}, nil)
	fw, err := NewFlakeWatcher(FlakeWatcherConfig{ProjectRoot: root, Server: s})
	if err != nil {
		t.Fatal(err)
	}
	fw.configEvaluator = eval
	fw.packagesEvaluator = watchTestEval(
		func(context.Context) ([]byte, error) { return []byte(`[]`), nil },
	)
	if err := fw.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = fw.Stop() })
	return fw, stream
}

func nextWatchEval(
	t *testing.T,
	stream <-chan SSEEvent,
	root string,
) ModuleDevDiagnostics {
	t.Helper()
	deadline := time.After(5 * time.Second)
	for {
		select {
		case e := <-stream:
			if e.ProjectRoot != root {
				t.Fatalf("event for %q reached %q", e.ProjectRoot, root)
			}
			if e.Event != moduleDevDiagnosticsEvent {
				continue
			}
			d := e.Data.(ModuleDevDiagnostics)
			if d.EvaluatedAt == "" { // subscription or link transition before eval
				continue
			}
			if _, err := time.Parse(
				time.RFC3339Nano,
				d.EvaluatedAt,
			); err != nil || d.DurationMs == nil || *d.DurationMs < 0 ||
				d.ProjectID != userconfig.GenerateProjectID(root) {
				t.Fatalf("invalid diagnostics: %+v", d)
			}
			return d
		case <-deadline:
			t.Fatal("no completed flake evaluation on the project stream")
		}
	}
}

func TestFlakeWatcherProjectConfigRoots(t *testing.T) {
	root := flakeTestRoot(t)
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatal(err)
	}
	defer watcher.Close()
	paths := flakeWatchPaths{
		project: root,
		config:  filepath.Join(t.TempDir(), "config.yaml"),
		watcher: watcher,
	}
	dirs := []string{".stack", ".stackpanel", "unrelated"}
	for _, dir := range dirs {
		atomicWatchFile(t, filepath.Join(root, dir, "data", "modules.nix"), "{}")
	}
	paths.reconcile(nil)
	for _, dir := range dirs {
		data := filepath.Join(root, dir, "data")
		change, reload := paths.event(fsnotify.Event{Name: filepath.Join(data, "modules.nix"), Op: fsnotify.Write})
		want := dir == ".stack"
		if paths.dirs[data] != want || (change.trigger != "") != want || change.packages != want || reload {
			t.Errorf("%s: watched=%v change=%+v reload=%v", dir, paths.dirs[data], change, reload)
		}
	}
}

// Exercise directory watches on the native backend, not just synthetic suffix
// matching. Keep the evaluated config constant: diagnostics must be sent even
// if an edit changes no serialized panel metadata.
func TestFlakeWatcherLinkedSourcesAndDiagnostics(t *testing.T) {
	root, other := flakeTestRoot(t), flakeTestRoot(t)
	linked, foreign := flakeTestRoot(t), flakeTestRoot(t)
	readme := filepath.Join(linked, "panels", "nested", "README.md")
	atomicWatchFile(t, readme, "old")
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
	m, err := userconfig.NewManager()
	if err != nil {
		t.Fatal(err)
	}
	const origin = "http://127.0.0.1:5174"
	if err := m.SetLinkedModule(
		root,
		"author",
		userconfig.LinkedModule{Path: linked, UIDevURL: origin + "/private-author-path"},
	); err != nil {
		t.Fatal(err)
	}
	if err := m.SetLinkedModule(
		other,
		"foreign",
		userconfig.LinkedModule{Path: foreign},
	); err != nil {
		t.Fatal(err)
	}
	var fail atomic.Bool
	fail.Store(true)
	fw, stream := startTestFlakeWatcher(t, root, func(context.Context) ([]byte, error) {
		if fail.Load() {
			return nil, errors.New(
				"\x1b[31merror: syntax error at " + linked + "/flake.nix:17:4\n17 | apiKey = \"secret-on-source-line\";\ntrace: /home/private/unrelated.nix\x1b[0m",
			)
		}
		return []byte(`{"variables":{"private":"never-send-config"}}`), nil
	})
	d := nextWatchEval(t, stream, root)
	if len(d.LinkedModules) != 1 || d.LinkedModules["author"].UIDevURL != origin ||
		d.Error != "Nix syntax error." {
		t.Fatalf("initial eval failure lost authorized link status: %+v", d)
	}
	encoded, err := json.Marshal(d)
	if err != nil {
		t.Fatal(err)
	}
	for _, private := range []string{linked, "foreign", "private-author-path", "secret-on-source-line", "/home/private/", "flake.nix", "apiKey"} {
		if strings.Contains(string(encoded), private) {
			t.Errorf("private diagnostic content reached SSE: %q", private)
		}
	}
	// A late subscriber must see the initial failure without waiting for a save.
	replay := nextWatchEval(
		t,
		fw.server.subscribeSSE(sseScope{root: root, diagnostics: true}, fw),
		root,
	)
	if replay.EvaluatedAt != d.EvaluatedAt || replay.Error != d.Error {
		t.Fatalf("failed to replay current diagnostic: %+v", replay)
	}
	if ch := fw.server.subscribeSSE(sseScope{root: root}, fw); len(ch) != 0 {
		t.Fatal("replayed sensitive diagnostics to an unqualified current-project stream")
	}
	if slices.Contains(fw.watcher.WatchList(), foreign) {
		t.Fatal("an unrelated project's linked directory was watched")
	}
	fail.Store(false)
	atomicWatchFile(t, readme, "fixed")
	if d := nextWatchEval(t, stream, root); d.Error != "" {
		t.Fatalf("successful README save retained the old error: %+v", d)
	}
	// Move an already-populated tree into the module; then save beneath it.
	staging := t.TempDir()
	atomicWatchFile(t, filepath.Join(staging, "sub", "data.json"), "{}")
	bundle := filepath.Join(linked, "bundle")
	if err := os.Rename(staging, bundle); err != nil {
		t.Fatal(err)
	}
	nextWatchEval(t, stream, root)
	if !slices.Contains(fw.watcher.WatchList(), filepath.Join(bundle, "sub")) {
		t.Fatal("did not watch descendants of moved-in directory")
	}
	atomicWatchFile(t, filepath.Join(bundle, "sub", "data.json"), "[]")
	nextWatchEval(t, stream, root)
	// Full config stayed identical. Module readers still need an invalidation
	// to re-evaluate their separate serializable projection, never its contents.
	select {
	case e := <-stream:
		data, ok := e.Data.(map[string]any)
		if e.Event != "flake.config.updated" || !ok || len(data) != 3 ||
			data["projectId"] != d.ProjectID ||
			data["trigger"] != "linked:author" ||
			data["timestamp"] == nil {
			t.Fatalf("expected metadata-only linked edit invalidation, got %+v", e)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("unchanged full config suppressed linked module invalidation")
	}
	fail.Store(true)
	atomicWatchFile(t, filepath.Join(bundle, "sub", "module.nix"), "broken")
	if d := nextWatchEval(
		t,
		stream,
		root,
	); d.Error != "Nix syntax error." ||
		len(d.LinkedModules) != 1 {
		t.Fatalf("new eval error was not exposed on subsequent save: %+v", d)
	}
	if _, cached := fw.ConfigStatus(); cached {
		t.Fatal("failed config eval left an apparently successful cached config")
	}
	// The consumer flake itself is watched by directory, not by inode.
	fail.Store(false)
	atomicWatchFile(t, filepath.Join(root, "flake.nix"), "{} # saved")
	if d := nextWatchEval(t, stream, root); d.Error != "" {
		t.Fatalf("consumer flake save did not refresh: %+v", d)
	}
}

func TestFlakeWatcherReloadsLinksWithoutRestart(t *testing.T) {
	root, first, second := flakeTestRoot(t), flakeTestRoot(t), flakeTestRoot(t)
	config := filepath.Join(t.TempDir(), "not-created-yet", "config.yaml")
	t.Setenv("STACKPANEL_USER_CONFIG", config)
	fw, stream := startTestFlakeWatcher(
		t,
		root,
		func(context.Context) ([]byte, error) { return []byte(`{}`), nil },
	)
	if d := nextWatchEval(
		t,
		stream,
		root,
	); d.LinkedModules == nil || len(d.LinkedModules) != 0 ||
		d.Error != "" {
		t.Fatalf("bad initial snapshot without user config: %+v", d)
	}
	m, err := userconfig.NewManager()
	if err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{first, second} {
		if err := m.SetLinkedModule(
			root,
			"module",
			userconfig.LinkedModule{Path: dir},
		); err != nil {
			t.Fatal(err)
		}
		d := nextWatchEval(t, stream, root)
		if _, ok := d.LinkedModules["module"]; !ok || d.Error != "" ||
			!slices.Contains(fw.watcher.WatchList(), dir) {
			t.Fatalf("link to %s did not become active: %+v", dir, d)
		}
	}
	if slices.Contains(fw.watcher.WatchList(), first) {
		t.Fatal("relink retained the previous input's watch")
	}
	if err := m.UnlinkModule(root, "module"); err != nil {
		t.Fatal(err)
	}
	d := nextWatchEval(t, stream, root)
	if len(d.LinkedModules) != 0 || slices.Contains(fw.watcher.WatchList(), second) {
		t.Fatalf("unlink didn't retire status and watches: %+v", d)
	}
	// A hand-edited config can bypass the CLI setter, but must not mint
	// display authority or echo the credential in a validation error.
	badConfig, err := json.Marshal(map[string]any{"projects": []any{map[string]any{
		"path": root, "linkedModules": map[string]any{"module": map[string]string{
			"path":     second,
			"uiDevUrl": "http://localhost:5174/preview?token=private-query#private-fragment",
		}},
	}}})
	if err != nil {
		t.Fatal(err)
	}
	atomicWatchFile(t, config, string(badConfig))
	if d := nextWatchEval(
		t,
		stream,
		root,
	); d.Error != "Invalid project link configuration." ||
		len(d.LinkedModules) != 0 {
		t.Fatal("invalid launch URL did not fail closed with a fixed public summary")
	}
}

func TestFlakeWatcherRelinkDuringColdEvaluation(t *testing.T) {
	root, module := flakeTestRoot(t), flakeTestRoot(t)
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
	started, resume := make(chan struct{}), make(chan struct{})
	var cold atomic.Bool
	_, stream := startTestFlakeWatcher(
		t,
		root,
		func(ctx context.Context) ([]byte, error) {
			if cold.CompareAndSwap(false, true) {
				close(started)
				select {
				case <-resume:
					return nil, errors.New("obsolete initial evaluation error")
				case <-ctx.Done():
					return nil, ctx.Err()
				}
			}
			return []byte(`{}`), nil
		},
	)
	select {
	case <-started:
	case <-time.After(5 * time.Second):
		t.Fatal("cold eval did not start")
	}
	m, err := userconfig.NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := m.SetLinkedModule(
		root,
		"live",
		userconfig.LinkedModule{Path: module},
	); err != nil {
		t.Fatal(err)
	}
	select {
	case event := <-stream:
		d, ok := event.Data.(ModuleDevDiagnostics)
		if _, linked := d.LinkedModules["live"]; !ok || !linked || d.EvaluatedAt != "" {
			t.Fatalf("expected new pending snapshot: %+v", event)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("cold eval blocked config-file watcher")
	}
	close(resume)
	if d := nextWatchEval(t, stream, root); d.Error != "" || len(d.LinkedModules) != 1 {
		t.Fatalf("superseded eval published a stale result: %+v", d)
	}
}

func TestFlakeWatcherSSEProjectIsolation(t *testing.T) {
	s := &Server{sseSubscribers: make(map[chan SSEEvent]sseScope)}
	a := s.subscribeSSE(sseScope{root: "/a", diagnostics: true}, nil)
	b := s.subscribeSSE(sseScope{root: "/b", diagnostics: true}, nil)
	legacy := s.subscribeSSE(sseScope{root: "/a"}, nil)
	headless := s.subscribeSSE(sseScope{}, nil)
	s.broadcastSSE(
		SSEEvent{
			Event:       moduleDevDiagnosticsEvent,
			Data:        ModuleDevDiagnostics{Error: "private"},
			ProjectRoot: "/a",
		},
	)
	// An unscoped marker is delivered after any preceding diagnostics to all
	// streams. This asserts isolation deterministically without a sleep.
	s.broadcastSSE(SSEEvent{Event: "marker"})
	if len(a) != 2 || len(b) != 1 || len(headless) != 1 || len(legacy) != 1 {
		t.Fatalf(
			"unexpected event counts: a=%d, b=%d, headless=%d, legacy=%d",
			len(a),
			len(b),
			len(headless),
			len(legacy),
		)
	}
	if (<-a).Event != moduleDevDiagnosticsEvent || (<-a).Event != "marker" ||
		(<-b).Event != "marker" ||
		(<-headless).Event != "marker" ||
		(<-legacy).Event != "marker" {
		t.Fatal("SSE delivered a project diagnostic to the wrong subscriber")
	}
}
