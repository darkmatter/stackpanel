// Package nixeval provides utilities for evaluating Nix expressions
// and getting the stackpanel configuration without relying on state files.
//
// This eliminates state drift by always getting live configuration
// directly from Nix evaluation.
package nixeval

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// Config represents the stackpanel configuration from Nix
type Config struct {
	Version     int                `json:"version"`
	ProjectName string             `json:"projectName"`
	ProjectRoot string             `json:"projectRoot,omitempty"`
	BasePort    int                `json:"basePort"`
	Paths       Paths              `json:"paths"`
	Apps        map[string]App     `json:"apps"`
	Services    map[string]Service `json:"services"`
	Network     Network            `json:"network"`

	// Error fields (only present if evaluation failed)
	Error string `json:"error,omitempty"`
	Hint  string `json:"hint,omitempty"`
}

// Paths contains directory paths (relative to project root)
type Paths struct {
	State string `json:"state"`
	Gen   string `json:"gen"`
	Data  string `json:"data"`
}

// App represents an application with its port and domain configuration
type App struct {
	Port   int     `json:"port"`
	Domain *string `json:"domain,omitempty"`
	URL    *string `json:"url,omitempty"`
	TLS    bool    `json:"tls"`
}

// Service represents an infrastructure service
type Service struct {
	Key    string `json:"key"`
	Name   string `json:"name"`
	Port   int    `json:"port"`
	EnvVar string `json:"envVar"`
}

// Network contains network configuration
type Network struct {
	Step StepConfig `json:"step"`
}

// StepConfig contains Step CA configuration
type StepConfig struct {
	Enable bool    `json:"enable"`
	CAUrl  *string `json:"caUrl,omitempty"`
}

// Evaluator provides cached Nix evaluation with file watching
type Evaluator struct {
	projectRoot string
	nixFile     string            // Path to nix eval file - unused if expression is set
	nixExpr     string            // Nix expression to evaluate
	nixArgs     map[string]string // Additional Nix arguments
	timeout     time.Duration

	mu       sync.RWMutex
	cached   []byte
	cachedAt time.Time
	cacheTTL time.Duration

	watcher     *fsnotify.Watcher
	watchPaths  []string
	invalidated bool
}

// Option configures an Evaluator
type Option func(*Evaluator)

// WithTimeout sets the timeout for nix eval commands
func WithTimeout(d time.Duration) Option {
	return func(e *Evaluator) {
		e.timeout = d
	}
}

// WithCacheTTL sets how long to cache results before re-evaluating
func WithCacheTTL(d time.Duration) Option {
	return func(e *Evaluator) {
		e.cacheTTL = d
	}
}

// WithWatchPaths sets additional paths to watch for changes
func WithWatchPaths(paths []string) Option {
	return func(e *Evaluator) {
		e.watchPaths = append(e.watchPaths, paths...)
	}
}

func WithNixFile(nixFile string) Option {
	return func(e *Evaluator) {
		e.nixFile = nixFile
	}
}

func WithArgs(args map[string]string) Option {
	return func(e *Evaluator) {
		e.nixArgs = args
	}
}

func WithExpression(expr string) Option {
	return func(e *Evaluator) {
		e.nixExpr = expr
	}
}

// New creates a new Evaluator for the given project root
func New(projectRoot string, opts ...Option) (*Evaluator, error) {
	absRoot, err := filepath.Abs(projectRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve project root: %w", err)
	}

	// nixFile := filepath.Join(absRoot, "nix", "eval", "stackpanel-config.nix")
	// if _, err := os.Stat(nixFile); os.IsNotExist(err) {
	// 	return nil, fmt.Errorf("nix eval file not found: %s", nixFile)
	// }
	defaultWatchPaths := []string{
		filepath.Join(absRoot, "flake.nix"),
		filepath.Join(absRoot, ".stackpanel"),
	}
	if os.Getenv("STACKPANEL_CONFIG_JSON") != "" {
		defaultWatchPaths = append(defaultWatchPaths, os.Getenv("STACKPANEL_CONFIG_JSON"))
	}

	e := &Evaluator{
		projectRoot: absRoot,
		// nixFile:     nixFile,
		timeout:    10 * time.Second,
		cacheTTL:   5 * time.Second,
		watchPaths: defaultWatchPaths,
	}

	for _, opt := range opts {
		opt(e)
	}

	return e, nil
}

// NewWatchConfig is a helper to create an Evaluator to watch the standard
// config
func NewWatchConfig(projectRoot string, opts ...Option) (*Evaluator, error) {
	nixFile := filepath.Join(projectRoot, "nix", "eval", "stackpanel-config.nix")
	if _, err := os.Stat(nixFile); os.IsNotExist(err) {
		return nil, fmt.Errorf("nix eval file not found: %s", nixFile)
	}
	defaultOpts := []Option{
		WithWatchPaths([]string{
			filepath.Join(projectRoot, "flake.nix"),
			filepath.Join(projectRoot, ".stackpanel"),
		}),
		WithNixFile(nixFile),
	}
	opts = append(opts, defaultOpts...)
	return New(projectRoot, opts...)
}

// Eval lets you subscribe to a nix evaluation. It's essentially a wrapper around
// `nix eval` that caches results and watches for file changes. It will re-evaluate
// the expression when the files change and provide the updated result in
// realtime. It is the core function of the agent.
func (e *Evaluator) Eval(ctx context.Context) ([]byte, error) {
	e.mu.RLock()
	if e.cached != nil && !e.invalidated && time.Since(e.cachedAt) < e.cacheTTL {
		defer e.mu.RUnlock()
		return e.cached, nil
	}
	e.mu.RUnlock()

	// Need to re-evaluate
	e.mu.Lock()
	defer e.mu.Unlock()

	// Double-check after acquiring write lock
	if e.cached != nil && !e.invalidated && time.Since(e.cachedAt) < e.cacheTTL {
		return e.cached, nil
	}

	result, err := e.evalNix(ctx)
	if err != nil {
		return nil, err
	}

	e.cached = result
	e.cachedAt = time.Now()
	e.invalidated = false

	return result, nil
}

// evalNix runs the actual nix eval command
func (e *Evaluator) evalNixConfig(ctx context.Context) (*Config, error) {
	result, err := e.evalNix(ctx)
	if err != nil {
		return nil, err
	}

	var config Config
	if err := json.Unmarshal(result, &config); err != nil {
		return nil, fmt.Errorf("failed to parse nix eval output: %w", err)
	}

	// Check for error in the config itself
	if config.Error != "" {
		return nil, fmt.Errorf("%s: %s", config.Error, config.Hint)
	}

	// Set project root if not in config
	if config.ProjectRoot == "" {
		config.ProjectRoot = e.projectRoot
	}

	return &config, nil
}

// evalNix runs the actual nix eval command
func (e *Evaluator) evalNix(ctx context.Context) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, e.timeout)
	defer cancel()

	args := []string{"eval", "--impure", "--json"}
	if e.nixExpr != "" {
		args = append(args, "--expr", e.nixExpr)
	} else if e.nixFile != "" {
		args = append(args, "-f", e.nixFile)
	}
	for k, v := range e.nixArgs {
		args = append(args, "--argstr", k, v)
	}

	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Dir = e.projectRoot

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return nil, fmt.Errorf("nix eval timed out after %v", e.timeout)
		}
		return nil, fmt.Errorf("nix eval failed: %w\nstderr: %s", err, stderr.String())
	}

	return stdout.Bytes(), nil
}

// StartWatching begins watching files for changes
// When a change is detected, the cache is invalidated
func (e *Evaluator) StartWatching() error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return fmt.Errorf("failed to create file watcher: %w", err)
	}

	e.mu.Lock()
	e.watcher = watcher
	e.mu.Unlock()

	// Add watch paths
	for _, path := range e.watchPaths {
		if err := e.addWatchRecursive(path); err != nil {
			// Log but don't fail - some paths may not exist
			continue
		}
	}

	// Start watching goroutine
	go e.watchLoop()

	return nil
}

// addWatchRecursive adds a path and all subdirectories to the watcher
func (e *Evaluator) addWatchRecursive(path string) error {
	return filepath.Walk(path, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // Skip inaccessible paths
		}
		if info.IsDir() {
			if err := e.watcher.Add(p); err != nil {
				return nil // Skip unwatchable dirs
			}
		}
		return nil
	})
}

// watchLoop handles file system events
func (e *Evaluator) watchLoop() {
	for {
		select {
		case event, ok := <-e.watcher.Events:
			if !ok {
				return
			}
			// Invalidate cache on any write or create
			if event.Op&(fsnotify.Write|fsnotify.Create|fsnotify.Remove) != 0 {
				// Only care about .nix, .yaml, .json files
				ext := filepath.Ext(event.Name)
				if ext == ".nix" || ext == ".yaml" || ext == ".json" {
					e.mu.Lock()
					e.invalidated = true
					e.mu.Unlock()
				}
			}
		case _, ok := <-e.watcher.Errors:
			if !ok {
				return
			}
			// Log error but continue watching
		}
	}
}

// StopWatching stops the file watcher
func (e *Evaluator) StopWatching() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if e.watcher != nil {
		return e.watcher.Close()
	}
	return nil
}

// Invalidate manually invalidates the cache
func (e *Evaluator) Invalidate() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.invalidated = true
}

// GetAppPort returns the port for an app
func (c *Config) GetAppPort(name string) int {
	if app, ok := c.Apps[name]; ok {
		return app.Port
	}
	return 0
}

// GetServicePort returns the port for a service
func (c *Config) GetServicePort(name string) int {
	if svc, ok := c.Services[name]; ok {
		return svc.Port
	}
	return 0
}
