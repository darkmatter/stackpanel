package server

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"maps"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/fsnotify/fsnotify"
	"github.com/rs/zerolog/log"
)

type flakeEvaluator interface {
	Eval(context.Context) ([]byte, error)
	Invalidate()
}

// FlakeWatcher caches flake outputs for one project. A separate worker runs
// Nix so even cold evaluations don't block fsnotify or lose newly created dirs.
type FlakeWatcher struct {
	projectRoot string
	watcher     *fsnotify.Watcher
	server      *Server
	shell       *ShellManager
	ctx         context.Context
	cancel      context.CancelFunc
	wg          sync.WaitGroup

	configEvaluator   flakeEvaluator
	packagesEvaluator flakeEvaluator
	configEvalMu      sync.Mutex
	packagesEvalMu    sync.Mutex

	mu             sync.RWMutex
	cachedConfig   map[string]any
	cachedPackages []nixeval.InstalledPackage
	configUpdated  time.Time
	pkgsUpdated    time.Time
	links          map[string]userconfig.LinkedModule // replaced, never mutated
	linkVersion    uint64
	linkErr        error
	diagnostics    ModuleDevDiagnostics
}

type FlakeWatcherConfig struct {
	ProjectRoot string
	Server      *Server
	Shell       *ShellManager
}

func NewFlakeWatcher(cfg FlakeWatcherConfig) (*FlakeWatcher, error) {
	if cfg.ProjectRoot == "" {
		return nil, errors.New("flake watcher requires a project root")
	}
	root, err := filepath.Abs(cfg.ProjectRoot)
	if err != nil {
		return nil, err
	}
	// The editor reads full configuration; module RPCs use a restricted output.
	configEval, err := nixeval.New(root, "stackpanelConfig", nixeval.WithTimeout(30*time.Second))
	if err != nil {
		return nil, err
	}
	packagesEval, err := nixeval.New(root, "stackpanelPackages", nixeval.WithTimeout(30*time.Second))
	if err != nil {
		return nil, err
	}
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithCancel(context.Background())
	return &FlakeWatcher{
		projectRoot:       root,
		watcher:           watcher,
		server:            cfg.Server,
		shell:             cfg.Shell,
		ctx:               ctx,
		cancel:            cancel,
		configEvaluator:   configEval,
		packagesEvaluator: packagesEval,
		diagnostics: ModuleDevDiagnostics{
			ProjectID: userconfig.GenerateProjectID(
				root,
			),
			LinkedModules: map[string]LinkedModuleStatus{},
		},
	}, nil
}

func (fw *FlakeWatcher) Start() error {
	configPath, err := filepath.Abs(userconfig.GetConfigPath())
	if err != nil {
		_ = fw.Stop()
		return err
	}
	paths := flakeWatchPaths{
		watcher: fw.watcher,
		project: fw.projectRoot,
		config:  configPath,
		dirs:    make(map[string]bool),
	}
	// Arm the config parent before reading links: a link/unlink during startup
	// must either be seen by LoadLinkedModules or queued as an event.
	paths.watchParent(configPath, paths.dirs)
	links, _ := fw.reloadLinks()
	paths.reconcile(links)
	jobs := make(chan flakeChange)
	fw.wg.Go(func() { fw.watchLoop(&paths, jobs) })
	fw.wg.Go(func() {
		fw.refresh(flakeChange{packages: true}) // initial eval also publishes diagnostics
		for change := range jobs {
			fw.refresh(change)
		}
	})
	return nil
}

func (fw *FlakeWatcher) Stop() error {
	fw.cancel()
	err := fw.watcher.Close()
	fw.wg.Wait()
	return err
}

// DevDiagnostics does not depend on the evaluated config: the toolbar still
// sees which inputs are linked and why evaluation failed with a broken flake.
func (fw *FlakeWatcher) DevDiagnostics() ModuleDevDiagnostics {
	fw.mu.RLock()
	defer fw.mu.RUnlock()
	snapshot := fw.diagnostics
	snapshot.LinkedModules = maps.Clone(snapshot.LinkedModules)
	if snapshot.DurationMs != nil {
		d := *snapshot.DurationMs
		snapshot.DurationMs = &d
	}
	return snapshot
}

const invalidLinksSummary = "Invalid project link configuration."

var (
	errInvalidLinks = errors.New(invalidLinksSummary)
	errLinksChanged = errors.New("project links changed during evaluation")
)

func (fw *FlakeWatcher) reloadLinks() (map[string]userconfig.LinkedModule, bool) {
	links, err := userconfig.LoadLinkedModules(fw.projectRoot)
	if err != nil {
		log.Warn().Msg("Failed to read project links")
		// Validation errors may quote arbitrary YAML, including values from
		// other projects. Do not forward them or retain stale HMR authority.
		links, err = nil, errInvalidLinks
	}
	fw.mu.Lock()
	defer fw.mu.Unlock()
	if fw.linkErr == err && maps.Equal(fw.links, links) {
		return links, false
	}
	fw.links, fw.linkErr = links, err
	fw.linkVersion++
	fw.cachedConfig, fw.cachedPackages = nil, nil
	status := make(map[string]LinkedModuleStatus, len(links))
	for id, link := range links {
		// Only the validated origin is display metadata. OpenModuleUI reads
		// the full author-specified target separately, from machine config.
		origin, _ := normalizeOrigin(link.UIDevURL)
		status[id] = LinkedModuleStatus{UIDevURL: origin}
	}
	fw.diagnostics = ModuleDevDiagnostics{
		ProjectID:     fw.diagnostics.ProjectID,
		LinkedModules: status,
	}
	fw.diagnostics.Error = devEvalSummary(err)
	fw.publish(moduleDevDiagnosticsEvent, fw.diagnostics)
	return links, true
}

func (fw *FlakeWatcher) publish(event string, data any) {
	if fw.server != nil && fw.ctx.Err() == nil {
		fw.server.broadcastSSE(
			SSEEvent{ProjectRoot: fw.projectRoot, Event: event, Data: data},
		)
	}
}

// Always invalidate the evaluator's own TTL cache on a real evaluation. A
// README save within a few ms of the last eval still needs fresh Nix output.
func evalFlakeJSON(ctx context.Context, ev flakeEvaluator, dest any) error {
	ev.Invalidate()
	b, err := ev.Eval(ctx)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, dest)
}

func (fw *FlakeWatcher) GetConfig(ctx context.Context) (map[string]any, error) {
	fw.mu.RLock()
	cached := fw.cachedConfig
	fw.mu.RUnlock()
	if cached != nil {
		return cached, nil
	}
	return fw.evaluateConfig(ctx, false)
}

func (fw *FlakeWatcher) evaluateConfig(
	ctx context.Context,
	force bool,
) (map[string]any, error) {
	fw.configEvalMu.Lock()
	defer fw.configEvalMu.Unlock()
	fw.mu.RLock()
	cached, version, err := fw.cachedConfig, fw.linkVersion, fw.linkErr
	fw.mu.RUnlock()
	if !force && cached != nil {
		return cached, nil
	}
	start := time.Now()
	var config map[string]any
	if err == nil {
		err = evalFlakeJSON(ctx, fw.configEvaluator, &config)
		if err == nil && config == nil {
			err = errors.New("expected evaluated flake config to be an object, got null")
		}
	}
	end := time.Now()
	duration := end.Sub(start).Milliseconds()
	msg := devEvalSummary(err)
	fw.mu.Lock()
	defer fw.mu.Unlock()
	if fw.linkVersion != version {
		// An unlink or relink supersedes even an in-flight initial evaluation.
		return nil, errLinksChanged
	}
	if errors.Is(ctx.Err(), context.Canceled) {
		return nil, ctx.Err()
	}
	fw.diagnostics.EvaluatedAt = end.UTC().Format(time.RFC3339Nano)
	fw.diagnostics.DurationMs, fw.diagnostics.Error = &duration, msg
	if err == nil {
		fw.cachedConfig, fw.configUpdated = config, end
	} else {
		fw.cachedConfig, config = nil, nil
	}
	fw.publish(moduleDevDiagnosticsEvent, fw.diagnostics)
	return config, err
}

// Return only fixed public messages. Nix can quote an entire expression,
// environment value, or arbitrary author-supplied throw string in stderr;
// redacting paths or truncating source lines cannot make that safe for SSE.
func devEvalSummary(err error) string {
	switch {
	case err == nil:
		return ""
	case errors.Is(err, errInvalidLinks):
		return invalidLinksSummary
	case errors.Is(err, context.DeadlineExceeded):
		return "Nix evaluation timed out."
	}
	text := err.Error()
	switch {
	case strings.Contains(text, "timed out"),
		strings.Contains(text, "context deadline exceeded"):
		return "Nix evaluation timed out."
	case strings.Contains(text, "syntax error"):
		return "Nix syntax error."
	case strings.Contains(text, "infinite recursion"):
		return "Nix evaluation encountered infinite recursion."
	case strings.Contains(text, "type error"),
		strings.Contains(text, "not of type"),
		strings.Contains(text, "cannot coerce"):
		return "Nix type error."
	default:
		return "Nix evaluation failed."
	}
}

func (fw *FlakeWatcher) GetPackages(
	ctx context.Context,
) ([]nixeval.InstalledPackage, error) {
	fw.mu.RLock()
	cached := fw.cachedPackages
	fw.mu.RUnlock()
	if cached != nil {
		return cached, nil
	}
	return fw.evaluatePackages(ctx, false)
}

func (fw *FlakeWatcher) evaluatePackages(
	ctx context.Context,
	force bool,
) ([]nixeval.InstalledPackage, error) {
	fw.packagesEvalMu.Lock()
	defer fw.packagesEvalMu.Unlock()
	fw.mu.RLock()
	cached, version, err := fw.cachedPackages, fw.linkVersion, fw.linkErr
	fw.mu.RUnlock()
	if !force && cached != nil {
		return cached, nil
	}
	var pkgs []nixeval.InstalledPackage
	if err == nil {
		err = evalFlakeJSON(ctx, fw.packagesEvaluator, &pkgs)
	}
	fw.mu.Lock()
	defer fw.mu.Unlock()
	if fw.linkVersion != version {
		return nil, errLinksChanged
	}
	if err != nil {
		fw.cachedPackages = nil
		return nil, err
	}
	fw.cachedPackages, fw.pkgsUpdated = pkgs, time.Now()
	return pkgs, nil
}

type flakeChange struct {
	trigger  string // project-relative path, or a symbolic reason for external changes
	packages bool
	linked   bool // module-safe output can change without changing the full config
}

func (fw *FlakeWatcher) refresh(change flakeChange) {
	if fw.ctx.Err() != nil {
		return
	}
	if change.trigger != "" && fw.shell != nil {
		fw.shell.MarkNixFileChanged(filepath.Join(fw.projectRoot, change.trigger))
	}
	fw.mu.RLock()
	oldConfig, oldPackages := fw.cachedConfig, fw.cachedPackages
	id := fw.diagnostics.ProjectID
	fw.mu.RUnlock()
	config, err := fw.evaluateConfig(fw.ctx, true)
	if err != nil {
		log.Warn().
			Str("error", devEvalSummary(err)).
			Str("projectId", id).
			Msg("Flake config evaluation failed")

	} else if change.trigger != "" && (change.linked || !reflect.DeepEqual(oldConfig, config)) {
		fw.publish("flake.config.updated", map[string]any{
			"projectId": id,
			"timestamp": time.Now().UTC().Format(time.RFC3339Nano),
			"trigger":   change.trigger,
		})
	}
	if !change.packages || fw.ctx.Err() != nil {
		return
	}
	pkgs, err := fw.evaluatePackages(fw.ctx, true)
	if err != nil {
		log.Warn().
			Str("error", devEvalSummary(err)).
			Str("projectId", id).
			Msg("Flake packages evaluation failed")
	} else if change.trigger != "" && !reflect.DeepEqual(oldPackages, pkgs) {
		fw.publish("flake.packages.updated", map[string]any{
			"projectId": id,
			"timestamp": time.Now().UTC().Format(time.RFC3339Nano),
			"trigger":   change.trigger,
			"count":     len(pkgs),
		})
	}
}

// The watch loop alone owns these maps. Directory watches survive atomic saves;
// anchor parents let us notice when even a source root is created or replaced.
type flakeWatchPaths struct {
	watcher      *fsnotify.Watcher
	project      string
	config       string
	links        map[string]userconfig.LinkedModule
	roots        map[string]string // recursive source dir -> input id (empty for project sources)
	dirs         map[string]bool
}

func (p *flakeWatchPaths) watchDir(dir string, wanted map[string]bool) {
	if wanted[dir] {
		return
	}
	if err := p.watcher.Add(dir); err != nil {
		if !os.IsNotExist(err) {
			log.Warn().Err(err).Str("dir", dir).Msg("Cannot watch flake source directory")
		}
		return
	}
	wanted[dir] = true
}

func (p *flakeWatchPaths) watchParent(target string, wanted map[string]bool) {
	for dir := filepath.Dir(target); ; dir = filepath.Dir(dir) {
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			p.watchDir(dir, wanted)
			if wanted[dir] {
				return
			}
		}
		if filepath.Dir(dir) == dir {
			return
		}
	}
}

func skipSourceDir(name string) bool {
	switch name {
	case ".git", ".direnv", "node_modules":
		return true
	}
	return false
}

func (p *flakeWatchPaths) watchTree(root string, wanted map[string]bool) {
	// WalkDir doesn't follow symlinks to unrelated trees (or cycles). Install
	// each watch before reading its children, including a populated moved-in dir.
	_ = filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			if !errors.Is(err, fs.ErrNotExist) {
				log.Warn().Err(err).Str("dir", path).Msg("Cannot scan flake source directory")
			}
			return nil
		}
		if entry.IsDir() {
			if path != root && skipSourceDir(entry.Name()) {
				return filepath.SkipDir
			}
			p.watchDir(path, wanted)
		}
		return nil
	})
}

func (p *flakeWatchPaths) reconcile(links map[string]userconfig.LinkedModule) {
	p.links = links
	p.roots = map[string]string{
		filepath.Join(p.project, ".stack"): "",
		filepath.Join(p.project, "nix"):    "",
	}
	for id, link := range links {
		root := filepath.Clean(link.Path)
		p.roots[root] = id
		// The CLI canonicalizes linked paths. Also support a hand-written link
		// whose root is a symlink; watch both the alias parent and the target
		// tree without following arbitrary symlinks inside an extension.
		if info, err := os.Lstat(root); err == nil && info.Mode()&fs.ModeSymlink != 0 {
			if target, err := filepath.EvalSymlinks(root); err == nil {
				p.roots[target] = id
			}
		}
	}
	wanted := make(map[string]bool)
	p.watchParent(p.config, wanted)
	for root := range p.roots {
		p.watchParent(root, wanted)
		p.watchTree(root, wanted)
	}
	for dir := range p.dirs {
		if !wanted[dir] {
			_ = p.watcher.Remove(dir) // backend may already have removed it
		}
	}
	p.dirs = wanted
}

func pathWithin(root, path string) bool {
	return path == root || (strings.HasPrefix(path, root) && len(root) > 0 &&
		(os.IsPathSeparator(root[len(root)-1]) || os.IsPathSeparator(path[len(root)])))
}

func createdWatchDir(event fsnotify.Event) bool {
	if !event.Has(fsnotify.Create) {
		return false
	}
	info, err := os.Lstat(event.Name)
	return err == nil && info.IsDir()
}

func (p *flakeWatchPaths) event(
	event fsnotify.Event,
) (change flakeChange, reload bool) {
	if event.Op&(fsnotify.Create|fsnotify.Write|fsnotify.Rename|fsnotify.Remove) == 0 {
		return
	}
	path := event.Name
	if path == p.config {
		return flakeChange{}, true
	}
	structure := event.Op&(fsnotify.Create|fsnotify.Rename|fsnotify.Remove) != 0
	// A parent of the config path appeared, disappeared or was replaced.
	if structure && pathWithin(path, p.config) {
		p.reconcile(p.links)
		return flakeChange{}, true
	}
	var source, ancestor bool
	var linkedID string
	for root, id := range p.roots {
		inside, above := pathWithin(root, path), pathWithin(path, root)
		source, ancestor = source || inside, ancestor || above
		if id != "" && (inside || above) {
			linkedID = id
		}
	}
	if !source && !ancestor && (filepath.Dir(path) != p.project ||
		(filepath.Base(path) != "flake.nix" && filepath.Base(path) != "flake.lock")) {
		return
	}
	if structure && (ancestor || p.dirs[path]) {
		// Remove stale sub-watches after a rename and rediscover roots when
		// any missing ancestor appears.
		p.reconcile(p.links)
	} else if createdWatchDir(event) {
		if skipSourceDir(filepath.Base(path)) {
			return
		}
		p.watchTree(path, p.dirs)
	} else {
		switch strings.ToLower(filepath.Ext(path)) {
		case ".nix", ".json", ".md", ".markdown", ".lock":
		default:
			return
		}
	}
	if linkedID != "" {
		return flakeChange{
			trigger:  "linked:" + linkedID,
			packages: true,
			linked:   true,
		}, false
	}
	rel, err := filepath.Rel(p.project, path)
	if err != nil || !filepath.IsLocal(rel) {
		return flakeChange{}, false
	}
	name := filepath.Base(path)
	packages := name == "packages.nix" || name == "flake.nix" || name == "flake.lock" ||
		ancestor ||
		pathWithin(filepath.Join(p.project, ".stack", "data"), path)
	return flakeChange{trigger: rel, packages: packages}, false
}

func (fw *FlakeWatcher) watchLoop(paths *flakeWatchPaths, jobs chan flakeChange) {
	defer close(jobs)
	const debounce = 500 * time.Millisecond
	timer := time.NewTimer(debounce)
	timer.Stop()
	defer timer.Stop()
	var tick <-chan time.Time
	var ready chan flakeChange
	var pending flakeChange
	var reload bool
	for {
		select {
		case <-fw.ctx.Done():
			return
		case e, ok := <-fw.watcher.Events:
			if !ok {
				return
			}
			change, config := paths.event(e)
			if change.trigger == "" && !config {
				continue
			}
			if change.trigger != "" {
				pending.trigger = change.trigger
			}
			pending.packages = pending.packages || change.packages
			pending.linked = pending.linked || change.linked
			reload = reload || config
		case err, ok := <-fw.watcher.Errors:
			if !ok {
				return
			}
			log.Warn().Err(err).Msg("Flake watcher error")
			if !errors.Is(err, fsnotify.ErrEventOverflow) {
				continue
			}
			paths.reconcile(paths.links)
			pending, reload = flakeChange{
				trigger:  "rescan",
				packages: true,
				linked:   true,
			}, true
		case <-tick:
			tick = nil
			if reload {
				reload = false
				if links, changed := fw.reloadLinks(); changed {
					paths.reconcile(links)
					pending = flakeChange{trigger: "linkedModules", packages: true, linked: true}
				}
			}
			if pending.trigger != "" {
				ready = jobs
			}
			continue
		case ready <- pending:
			ready, pending = nil, flakeChange{}
			continue
		}
		// Re-arm even when the previous batch was ready but Nix was busy: the
		// next job covers all writes (including whether any affected packages).
		ready, tick = nil, timer.C
		timer.Reset(debounce)
	}
}

func (fw *FlakeWatcher) InvalidateAll() {
	fw.InvalidateConfig()
	fw.InvalidatePackages()
}

func (fw *FlakeWatcher) InvalidateConfig() {
	fw.configEvalMu.Lock()
	defer fw.configEvalMu.Unlock()
	fw.mu.Lock()
	defer fw.mu.Unlock()
	fw.cachedConfig = nil
}

func (fw *FlakeWatcher) InvalidatePackages() {
	fw.packagesEvalMu.Lock()
	defer fw.packagesEvalMu.Unlock()
	fw.mu.Lock()
	defer fw.mu.Unlock()
	fw.cachedPackages = nil
}

func (fw *FlakeWatcher) ConfigStatus() (updated time.Time, cached bool) {
	fw.mu.RLock()
	defer fw.mu.RUnlock()
	return fw.configUpdated, fw.cachedConfig != nil
}

func (fw *FlakeWatcher) PackagesStatus() (updated time.Time, count int, cached bool) {
	fw.mu.RLock()
	defer fw.mu.RUnlock()
	return fw.pkgsUpdated, len(fw.cachedPackages), fw.cachedPackages != nil
}

func (fw *FlakeWatcher) ForceRefresh(ctx context.Context) error {
	if _, err := fw.evaluateConfig(ctx, true); err != nil {
		fw.InvalidatePackages()
		return err
	}
	_, err := fw.evaluatePackages(ctx, true)
	return err
}
