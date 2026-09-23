package server

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"
)

// fakeRuntimes records lifecycle calls so registry behavior can be tested
// without real executors, flake evaluation or file watchers.
type fakeRuntimes struct {
	created   map[string]int
	watched   map[string]int
	unwatched map[string]int
	clock     time.Time
}

func newTestRegistry() (*runtimeRegistry, *fakeRuntimes) {
	f := &fakeRuntimes{
		created:   map[string]int{},
		watched:   map[string]int{},
		unwatched: map[string]int{},
		clock:     time.Unix(1_700_000_000, 0),
	}
	r := &runtimeRegistry{
		runtimes: map[string]*projectRuntime{},
		create: func(root string) (*projectRuntime, error) {
			f.created[root]++
			return &projectRuntime{root: root}, nil
		},
		watch:   func(rt *projectRuntime) error { f.watched[rt.root]++; return nil },
		unwatch: func(rt *projectRuntime) { f.unwatched[rt.root]++ },
		now:     func() time.Time { return f.clock },
	}
	return r, f
}

func mustGet(t *testing.T, r *runtimeRegistry, root string) *projectRuntime {
	t.Helper()
	rt, err := r.get(root)
	if err != nil {
		t.Fatalf("get(%q): %v", root, err)
	}
	return rt
}

func TestRuntimeRegistryReusesOneRuntimePerProject(t *testing.T) {
	r, f := newTestRegistry()

	a1 := mustGet(t, r, "/p/a")
	a2 := mustGet(t, r, "/p/a")
	b := mustGet(t, r, "/p/b")

	if a1 != a2 {
		t.Error("the same project returned different runtimes")
	}
	if a1 == b {
		t.Error("different projects shared a runtime")
	}
	if f.created["/p/a"] != 1 || f.created["/p/b"] != 1 {
		t.Errorf("created = %v, want one per project", f.created)
	}
}

func TestRuntimeRegistryStartsWatchersOnceAndOnlyWhileServing(t *testing.T) {
	r, f := newTestRegistry()

	mustGet(t, r, "/p/a")
	if f.watched["/p/a"] != 0 {
		t.Fatal("watchers started before the server was serving")
	}

	r.startWatching()
	r.startWatching()
	mustGet(t, r, "/p/a") // switching back to a known project
	mustGet(t, r, "/p/b") // a project first used while serving

	if f.watched["/p/a"] != 1 || f.watched["/p/b"] != 1 {
		t.Errorf("watched = %v, want exactly once per project", f.watched)
	}
}

func TestRuntimeRegistryEvictsIdleRuntimesExceptCurrent(t *testing.T) {
	r, f := newTestRegistry()
	r.startWatching()

	mustGet(t, r, "/p/current")
	mustGet(t, r, "/p/idle")
	f.clock = f.clock.Add(runtimeIdleTimeout + time.Second)
	mustGet(t, r, "/p/recent")

	r.evictIdle(runtimeIdleTimeout, "/p/current")

	if f.unwatched["/p/idle"] != 1 {
		t.Errorf("idle runtime not stopped: unwatched = %v", f.unwatched)
	}
	if f.unwatched["/p/current"] != 0 || f.unwatched["/p/recent"] != 0 {
		t.Errorf("stopped a runtime that should stay: unwatched = %v", f.unwatched)
	}

	// An evicted project gets a fresh runtime (and watchers) when used again.
	mustGet(t, r, "/p/idle")
	if f.created["/p/idle"] != 2 || f.watched["/p/idle"] != 2 {
		t.Errorf("re-used evicted project: created=%d watched=%d, want 2 and 2",
			f.created["/p/idle"], f.watched["/p/idle"])
	}
}

func TestRuntimeRegistryStopAllStopsEveryRuntime(t *testing.T) {
	r, f := newTestRegistry()
	r.startWatching()
	mustGet(t, r, "/p/a")
	mustGet(t, r, "/p/b")

	r.stopAll()

	if f.unwatched["/p/a"] != 1 || f.unwatched["/p/b"] != 1 {
		t.Errorf("unwatched = %v, want every runtime stopped", f.unwatched)
	}
	if len(r.runtimes) != 0 {
		t.Errorf("%d runtimes left after stopAll", len(r.runtimes))
	}
}

func TestWatchConfigFilesBroadcastsChangesUnderProjectRoot(t *testing.T) {
	root := t.TempDir()
	dataDir := filepath.Join(root, ".stack", "data")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}

	w, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatal(err)
	}
	events := make(chan SSEEvent, 4)
	done := make(chan struct{})
	go func() {
		watchConfigFiles(w, root, func(e SSEEvent) { events <- e })
		close(done)
	}()

	// Let the watcher register its directories before writing.
	time.Sleep(50 * time.Millisecond)
	changed := filepath.Join(dataDir, "packages.json")
	if err := os.WriteFile(changed, []byte("[]"), 0o644); err != nil {
		t.Fatal(err)
	}

	select {
	case e := <-events:
		if e.Event != "config.changed" {
			t.Errorf("event = %q, want config.changed", e.Event)
		}
		data, _ := e.Data.(map[string]string)
		if got := data["file"]; filepath.Base(got) != "packages.json" {
			t.Errorf("file = %q, want the changed file", got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("no config.changed event for a write under .stack/data")
	}

	_ = w.Close()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("watchConfigFiles did not return after the watcher was closed")
	}
}
