package server

import (
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/rs/zerolog/log"

	sharedexec "github.com/darkmatter/stackpanel/stackpanel-go/pkg/exec"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
)

// runtimeIdleTimeout is how long a project's runtime is kept after its last
// use before its watchers are stopped. The agent's current project is never
// evicted.
const runtimeIdleTimeout = 10 * time.Minute

// projectRuntime owns everything bound to one project: the command executor,
// the config store, the shell manager and the file watchers.
//
// The registry creates one per project root, so the legacy current-project
// handlers and the v1 per-request handlers share the same instances instead
// of racing each other with duplicates (ADR 0005).
type projectRuntime struct {
	root  string
	exec  *sharedexec.Executor
	store *nixdata.Store
	shell *ShellManager

	// Watchers run only while the server is serving; see startWatching.
	flake *FlakeWatcher
	files *fsnotify.Watcher

	lastUsed time.Time // guarded by runtimeRegistry.mu
}

// runtimeRegistry owns the per-project runtimes.
type runtimeRegistry struct {
	mu       sync.Mutex
	runtimes map[string]*projectRuntime
	watching bool // set once the server starts serving

	// Lifecycle hooks, replaced in tests so they need no executor or Nix.
	create  func(root string) (*projectRuntime, error)
	watch   func(rt *projectRuntime) error
	unwatch func(rt *projectRuntime)
	now     func() time.Time
}

func newRuntimeRegistry(s *Server) *runtimeRegistry {
	return &runtimeRegistry{
		runtimes: map[string]*projectRuntime{},
		create:   s.createRuntime,
		watch:    s.watchRuntime,
		unwatch:  unwatchRuntime,
		now:      time.Now,
	}
}

// get returns the runtime for root, creating it on first use. Runtimes created
// while the server is serving start their watchers immediately.
func (r *runtimeRegistry) get(root string) (*projectRuntime, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if rt, ok := r.runtimes[root]; ok {
		rt.lastUsed = r.now()
		return rt, nil
	}
	rt, err := r.create(root)
	if err != nil {
		return nil, err
	}
	if r.watching {
		r.startWatchers(rt)
	}
	rt.lastUsed = r.now()
	r.runtimes[root] = rt
	return rt, nil
}

// startWatching starts the watchers of existing runtimes and makes get start
// them for runtimes created later. It runs once, when the server starts.
func (r *runtimeRegistry) startWatching() {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.watching {
		return
	}
	r.watching = true
	for _, rt := range r.runtimes {
		r.startWatchers(rt)
	}
}

func (r *runtimeRegistry) startWatchers(rt *projectRuntime) {
	if err := r.watch(rt); err != nil {
		// The runtime stays usable; only live config updates are lost.
		log.Warn().Err(err).Str("project_root", rt.root).Msg("project watchers not started")
	}
}

// evictIdle stops and forgets runtimes unused for longer than idle, except the
// one for keep (the agent's current project).
func (r *runtimeRegistry) evictIdle(idle time.Duration, keep string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	cutoff := r.now().Add(-idle)
	for root, rt := range r.runtimes {
		if root == keep || rt.lastUsed.After(cutoff) {
			continue
		}
		r.unwatch(rt)
		delete(r.runtimes, root)
		log.Info().Str("project_root", root).Msg("evicted idle project runtime")
	}
}

// stopAll stops every runtime's watchers at shutdown.
func (r *runtimeRegistry) stopAll() {
	r.mu.Lock()
	defer r.mu.Unlock()

	for root, rt := range r.runtimes {
		r.unwatch(rt)
		delete(r.runtimes, root)
	}
	r.watching = false
}

func (s *Server) createRuntime(root string) (*projectRuntime, error) {
	exec, err := sharedexec.New(root, s.config.AllowedCommands)
	if err != nil {
		return nil, fmt.Errorf("failed to create executor: %w", err)
	}
	log.Info().
		Str("project_root", root).
		Bool("in_devshell", exec.InDevshell()).
		Bool("has_devshell_env", exec.HasDevshellEnv()).
		Msg("Executor initialized with devshell support")

	return &projectRuntime{
		root:  root,
		exec:  exec,
		store: nixdata.NewStore(root, exec),
		shell: NewShellManager(root, s),
	}, nil
}

// watchRuntime starts live evaluation of the project's flake and the
// config-file watcher that drives config.changed events.
func (s *Server) watchRuntime(rt *projectRuntime) error {
	fw, err := NewFlakeWatcher(FlakeWatcherConfig{ProjectRoot: rt.root, Server: s})
	if err != nil {
		return fmt.Errorf("create flake watcher: %w", err)
	}
	if err := fw.Start(); err != nil {
		return fmt.Errorf("start flake watcher: %w", err)
	}
	rt.flake = fw

	files, err := fsnotify.NewWatcher()
	if err != nil {
		return fmt.Errorf("create config file watcher: %w", err)
	}
	rt.files = files
	go watchConfigFiles(files, rt.root, s.broadcastSSE)
	return nil
}

func unwatchRuntime(rt *projectRuntime) {
	if rt.flake != nil {
		_ = rt.flake.Stop()
		rt.flake = nil
	}
	if rt.files != nil {
		_ = rt.files.Close()
		rt.files = nil
	}
}

// watchConfigFiles broadcasts config.changed when files are written in the
// project's .stack state, generated or data directories. Paths derive from
// the project root rather than the agent's environment, which only describes
// the project the agent was started in. It returns when w is closed.
func watchConfigFiles(w *fsnotify.Watcher, root string, broadcast func(SSEEvent)) {
	// Runtime state is split between profile/ and state/ until the .stack
	// layout is consolidated (ADR 0006); watch whichever exists.
	for _, dir := range []string{"profile", "state", "gen", "data"} {
		path := filepath.Join(root, ".stack", dir)
		if err := w.Add(path); err != nil {
			log.Debug().Err(err).Str("path", path).Msg("not watching config directory (may not exist yet)")
		}
	}

	const debounce = 100 * time.Millisecond
	var timer *time.Timer
	for {
		select {
		case event, ok := <-w.Events:
			if !ok {
				return
			}
			if event.Op&(fsnotify.Write|fsnotify.Create) == 0 {
				continue
			}
			name := event.Name
			if timer != nil {
				timer.Stop()
			}
			timer = time.AfterFunc(debounce, func() {
				log.Debug().Str("file", name).Msg("config file changed, broadcasting")
				broadcast(SSEEvent{
					Event: "config.changed",
					Data:  map[string]string{"file": name},
				})
			})
		case err, ok := <-w.Errors:
			if !ok {
				return
			}
			log.Warn().Err(err).Msg("file watcher error")
		}
	}
}
