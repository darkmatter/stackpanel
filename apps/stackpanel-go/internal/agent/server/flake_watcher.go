package server

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/fsnotify/fsnotify"
	"github.com/rs/zerolog/log"
)

// FlakeWatcher watches for changes to Nix files and re-evaluates flake outputs
type FlakeWatcher struct {
	projectRoot string
	watcher     *fsnotify.Watcher
	server      *Server

	// Evaluators for different flake outputs
	configEvaluator   *nixeval.Evaluator
	packagesEvaluator *nixeval.Evaluator

	// Cached values
	mu             sync.RWMutex
	cachedConfig   map[string]any
	cachedPackages []nixeval.InstalledPackage
	configUpdated  time.Time
	pkgsUpdated    time.Time

	// Control
	stopCh chan struct{}
}

// FlakeWatcherConfig configures the FlakeWatcher
type FlakeWatcherConfig struct {
	ProjectRoot string
	Server      *Server
}

// NewFlakeWatcher creates a new FlakeWatcher for monitoring flake outputs
func NewFlakeWatcher(cfg FlakeWatcherConfig) (*FlakeWatcher, error) {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}

	// Create evaluator for stackpanelConfig
	// Try devshell passthru first (for user projects), then flake outputs (for stackpanel repo)
	configEval, err := nixeval.New(cfg.ProjectRoot,
		nixeval.WithFlakeAttrFallbacks([]string{
			".#devShells." + getCurrentSystem() + ".default.passthru.stackpanelSerializable",
			".#devShells." + getCurrentSystem() + ".default.passthru.stackpanelConfig",
			".#stackpanelConfig",
			// Note: Do NOT use stackpanelFullConfig - it contains non-serializable values
		}),
		nixeval.WithTimeout(30*time.Second),
		nixeval.WithCacheTTL(10*time.Second),
	)
	if err != nil {
		watcher.Close()
		return nil, err
	}

	// Create evaluator for stackpanelPackages
	// Try devshell passthru first (for user projects), then flake outputs (for stackpanel repo)
	packagesEval, err := nixeval.New(cfg.ProjectRoot,
		nixeval.WithFlakeAttrFallbacks([]string{
			".#devShells." + getCurrentSystem() + ".default.passthru.stackpanelPackages",
			".#stackpanelPackages",
		}),
		nixeval.WithTimeout(30*time.Second),
		nixeval.WithCacheTTL(10*time.Second),
	)
	if err != nil {
		watcher.Close()
		return nil, err
	}

	fw := &FlakeWatcher{
		projectRoot:       cfg.ProjectRoot,
		watcher:           watcher,
		server:            cfg.Server,
		configEvaluator:   configEval,
		packagesEvaluator: packagesEval,
		stopCh:            make(chan struct{}),
	}

	return fw, nil
}

// Start begins watching for file changes and evaluating flake outputs
func (fw *FlakeWatcher) Start() error {
	// Watch paths that affect flake evaluation
	watchPaths := []string{
		filepath.Join(fw.projectRoot, "flake.nix"),
		filepath.Join(fw.projectRoot, "flake.lock"),
		filepath.Join(fw.projectRoot, ".stackpanel"),
		filepath.Join(fw.projectRoot, "nix"),
	}

	for _, path := range watchPaths {
		if err := fw.addWatchRecursive(path); err != nil {
			log.Debug().Err(err).Str("path", path).Msg("Failed to watch path (may not exist)")
		}
	}

	// Do initial evaluation
	go fw.initialEvaluation()

	// Start the watch loop
	go fw.watchLoop()

	log.Info().Str("projectRoot", fw.projectRoot).Msg("FlakeWatcher started")
	return nil
}

// Stop stops the FlakeWatcher
func (fw *FlakeWatcher) Stop() error {
	close(fw.stopCh)
	if fw.watcher != nil {
		return fw.watcher.Close()
	}
	return nil
}

// GetConfig returns the cached config or evaluates if not cached
func (fw *FlakeWatcher) GetConfig(ctx context.Context) (map[string]any, error) {
	fw.mu.RLock()
	if fw.cachedConfig != nil {
		config := fw.cachedConfig
		fw.mu.RUnlock()
		return config, nil
	}
	fw.mu.RUnlock()

	return fw.evaluateConfig(ctx)
}

// GetPackages returns the cached packages or evaluates if not cached
func (fw *FlakeWatcher) GetPackages(ctx context.Context) ([]nixeval.InstalledPackage, error) {
	fw.mu.RLock()
	if fw.cachedPackages != nil {
		packages := fw.cachedPackages
		fw.mu.RUnlock()
		return packages, nil
	}
	fw.mu.RUnlock()

	return fw.evaluatePackages(ctx)
}

// initialEvaluation performs the initial evaluation of both config and packages
func (fw *FlakeWatcher) initialEvaluation() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Evaluate config first (usually faster)
	if _, err := fw.evaluateConfig(ctx); err != nil {
		log.Warn().Err(err).Msg("Initial config evaluation failed")
	} else {
		log.Debug().Msg("Initial config evaluation succeeded")
	}

	// Then evaluate packages
	if _, err := fw.evaluatePackages(ctx); err != nil {
		log.Warn().Err(err).Msg("Initial packages evaluation failed")
	} else {
		log.Debug().Msg("Initial packages evaluation succeeded")
	}
}

// evaluateConfig evaluates .#stackpanelConfig and caches the result
func (fw *FlakeWatcher) evaluateConfig(ctx context.Context) (map[string]any, error) {
	result, err := fw.configEvaluator.Eval(ctx)
	if err != nil {
		return nil, err
	}

	var config map[string]any
	if err := json.Unmarshal(result, &config); err != nil {
		return nil, err
	}

	fw.mu.Lock()
	fw.cachedConfig = config
	fw.configUpdated = time.Now()
	fw.mu.Unlock()

	return config, nil
}

// evaluatePackages evaluates .#stackpanelPackages and caches the result
func (fw *FlakeWatcher) evaluatePackages(ctx context.Context) ([]nixeval.InstalledPackage, error) {
	result, err := fw.packagesEvaluator.Eval(ctx)
	if err != nil {
		return nil, err
	}

	var packages []nixeval.InstalledPackage
	if err := json.Unmarshal(result, &packages); err != nil {
		return nil, err
	}

	fw.mu.Lock()
	fw.cachedPackages = packages
	fw.pkgsUpdated = time.Now()
	fw.mu.Unlock()

	return packages, nil
}

// addWatchRecursive adds a path and its subdirectories to the watcher
func (fw *FlakeWatcher) addWatchRecursive(path string) error {
	return filepath.Walk(path, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // Skip inaccessible paths
		}
		// Only watch directories
		if info.IsDir() {
			_ = fw.watcher.Add(p)
		}
		return nil
	})
}

// watchLoop handles file system events and triggers re-evaluation
func (fw *FlakeWatcher) watchLoop() {
	// Debounce settings
	var debounceTimer *time.Timer
	debounceDuration := 500 * time.Millisecond

	for {
		select {
		case <-fw.stopCh:
			if debounceTimer != nil {
				debounceTimer.Stop()
			}
			return

		case event, ok := <-fw.watcher.Events:
			if !ok {
				return
			}

			// Only react to write, create, or remove events
			if event.Op&(fsnotify.Write|fsnotify.Create|fsnotify.Remove) == 0 {
				continue
			}

			// Only care about relevant file types
			ext := filepath.Ext(event.Name)
			if ext != ".nix" && ext != ".json" && ext != ".lock" {
				continue
			}

			log.Debug().
				Str("file", event.Name).
				Str("op", event.Op.String()).
				Msg("Relevant file changed")

			// Debounce: reset timer on each event
			if debounceTimer != nil {
				debounceTimer.Stop()
			}

			debounceTimer = time.AfterFunc(debounceDuration, func() {
				fw.handleFileChange(event.Name)
			})

		case err, ok := <-fw.watcher.Errors:
			if !ok {
				return
			}
			log.Warn().Err(err).Msg("FlakeWatcher error")
		}
	}
}

// handleFileChange handles a file change event after debouncing
func (fw *FlakeWatcher) handleFileChange(changedFile string) {
	log.Info().Str("file", changedFile).Msg("Re-evaluating flake outputs due to file change")

	// Notify shell manager that nix files changed (shell may be stale)
	if fw.server != nil && fw.server.shellManager != nil {
		fw.server.shellManager.MarkNixFileChanged(changedFile)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Determine what needs to be re-evaluated based on the file that changed
	filename := filepath.Base(changedFile)

	// If packages.nix changed, definitely re-evaluate packages
	// If other .nix files changed, re-evaluate both
	reEvalConfig := true
	reEvalPackages := filename == "packages.nix" || filename == "flake.nix" || filename == "flake.lock"

	// For general .nix changes in .stackpanel, re-evaluate both
	if filepath.Dir(changedFile) == filepath.Join(fw.projectRoot, ".stackpanel", "data") {
		reEvalPackages = true
	}

	var configChanged, packagesChanged bool

	if reEvalConfig {
		// Invalidate and re-evaluate config
		fw.configEvaluator.Invalidate()
		oldConfig := fw.cachedConfig

		newConfig, err := fw.evaluateConfig(ctx)
		if err != nil {
			log.Warn().Err(err).Msg("Failed to re-evaluate config")
		} else {
			// Check if config actually changed
			configChanged = !configEqual(oldConfig, newConfig)
			if configChanged {
				log.Info().Msg("Config changed, broadcasting update")
			}
		}
	}

	if reEvalPackages {
		// Invalidate and re-evaluate packages
		fw.packagesEvaluator.Invalidate()
		oldPackages := fw.cachedPackages

		newPackages, err := fw.evaluatePackages(ctx)
		if err != nil {
			log.Warn().Err(err).Msg("Failed to re-evaluate packages")
		} else {
			// Check if packages actually changed
			packagesChanged = !packagesEqual(oldPackages, newPackages)
			if packagesChanged {
				log.Info().Int("count", len(newPackages)).Msg("Packages changed, broadcasting update")
			}
		}
	}

	// Broadcast SSE events if there were changes
	if fw.server != nil {
		if configChanged {
			fw.server.broadcastSSE(SSEEvent{
				Event: "flake.config.updated",
				Data: map[string]any{
					"timestamp": time.Now().Format(time.RFC3339),
					"trigger":   changedFile,
				},
			})
		}

		if packagesChanged {
			fw.mu.RLock()
			packages := fw.cachedPackages
			fw.mu.RUnlock()

			fw.server.broadcastSSE(SSEEvent{
				Event: "flake.packages.updated",
				Data: map[string]any{
					"timestamp": time.Now().Format(time.RFC3339),
					"trigger":   changedFile,
					"count":     len(packages),
				},
			})
		}
	}
}

// InvalidateAll invalidates both caches
func (fw *FlakeWatcher) InvalidateAll() {
	fw.mu.Lock()
	fw.cachedConfig = nil
	fw.cachedPackages = nil
	fw.mu.Unlock()

	if fw.configEvaluator != nil {
		fw.configEvaluator.Invalidate()
	}
	if fw.packagesEvaluator != nil {
		fw.packagesEvaluator.Invalidate()
	}
}

// InvalidatePackages invalidates only the packages cache
func (fw *FlakeWatcher) InvalidatePackages() {
	fw.mu.Lock()
	fw.cachedPackages = nil
	fw.mu.Unlock()

	if fw.packagesEvaluator != nil {
		fw.packagesEvaluator.Invalidate()
	}
}

// InvalidateConfig invalidates only the config cache
func (fw *FlakeWatcher) InvalidateConfig() {
	fw.mu.Lock()
	fw.cachedConfig = nil
	fw.mu.Unlock()

	if fw.configEvaluator != nil {
		fw.configEvaluator.Invalidate()
	}
}

// configEqual compares two config maps for equality
func configEqual(a, b map[string]any) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}

	aJSON, err := json.Marshal(a)
	if err != nil {
		return false
	}

	bJSON, err := json.Marshal(b)
	if err != nil {
		return false
	}

	return string(aJSON) == string(bJSON)
}

// packagesEqual compares two package lists for equality
func packagesEqual(a, b []nixeval.InstalledPackage) bool {
	if len(a) != len(b) {
		return false
	}

	// Create a set of package signatures for comparison
	aSet := make(map[string]bool, len(a))
	for _, pkg := range a {
		sig := pkg.Name + "@" + pkg.Version + ":" + pkg.AttrPath + ":" + pkg.Source
		aSet[sig] = true
	}

	for _, pkg := range b {
		sig := pkg.Name + "@" + pkg.Version + ":" + pkg.AttrPath + ":" + pkg.Source
		if !aSet[sig] {
			return false
		}
	}

	return true
}

// ConfigStatus returns the status of the cached config
func (fw *FlakeWatcher) ConfigStatus() (updated time.Time, cached bool) {
	fw.mu.RLock()
	defer fw.mu.RUnlock()
	return fw.configUpdated, fw.cachedConfig != nil
}

// PackagesStatus returns the status of the cached packages
func (fw *FlakeWatcher) PackagesStatus() (updated time.Time, count int, cached bool) {
	fw.mu.RLock()
	defer fw.mu.RUnlock()
	return fw.pkgsUpdated, len(fw.cachedPackages), fw.cachedPackages != nil
}

// ForceRefresh forces a refresh of both config and packages
func (fw *FlakeWatcher) ForceRefresh(ctx context.Context) error {
	fw.InvalidateAll()

	if _, err := fw.evaluateConfig(ctx); err != nil {
		return err
	}

	if _, err := fw.evaluatePackages(ctx); err != nil {
		return err
	}

	return nil
}
