// Package nixeval bridges the Go agent/CLI with the Nix module system by
// shelling out to `nix eval`. It provides two main paths for reading config:
//
//   - One-shot evaluation ([GetConfigWithEval], [EvalExpr]) for CLI commands
//     that need the config once and exit.
//   - Cached evaluation ([Evaluator]) for the long-running agent, which
//     re-evaluates only when its cache expires or is invalidated.
//
// Both paths prefer live Nix evaluation over state files to eliminate drift,
// but fall back gracefully when Nix is unavailable.
package nixeval

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

// Config is the JSON shape returned by eval.nix (and the state file fallback).
// It mirrors the Nix module's output schema -- changes here must stay in sync
// with nix/stack/core/state.nix.
type Config struct {
	Version            int                `json:"version"`
	ProjectName        string             `json:"projectName"`
	ProjectRoot        string             `json:"projectRoot,omitempty"`
	BasePort           int                `json:"basePort"`
	ProcessComposePort int                `json:"processComposePort"`
	Paths              Paths              `json:"paths"`
	Apps               map[string]App     `json:"apps"`
	Services           map[string]Service `json:"services"`
	Network            Network            `json:"network"`

	// Error fields (only present if evaluation failed)
	Error string `json:"error,omitempty"`
	Hint  string `json:"hint,omitempty"`
}

// Paths contains directory paths (relative to project root).
// State is the profile dir (ephemeral); Keys is for persistent credentials.
type Paths struct {
	State string `json:"state"` // profile dir: stackpanel.json, shell.log
	Keys  string `json:"keys"`  // persistent: AGE keys, AWS config, step
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

// Evaluator provides cached Nix evaluation. It is the core mechanism the
// agent uses to keep its in-memory config in sync with the Nix source tree.
// Callers use [Evaluator.Eval] to get the latest result; the evaluator returns
// a cached copy unless the cache TTL has expired or [Evaluator.Invalidate] was
// called (the agent's FlakeWatcher does so when Nix sources change).
//
// The locking strategy uses a double-checked read pattern: a fast RLock path
// for cache hits and a full Lock only when re-evaluation is needed.
type Evaluator struct {
	projectRoot string
	flakeAttrs  []string // Ordered fallback installables; first success wins
	timeout     time.Duration

	mu       sync.RWMutex
	cached   []byte
	cachedAt time.Time
	cacheTTL time.Duration

	invalidated bool // set by Invalidate; cleared after successful re-eval
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

// WithFlakeAttrFallbacks sets multiple flake attributes to try in order
// The first one that succeeds will be used. This is useful for supporting
// both user projects (devshell passthru) and the stackpanel repo itself.
func WithFlakeAttrFallbacks(attrs []string) Option {
	return func(e *Evaluator) {
		e.flakeAttrs = attrs
	}
}

// New creates a new Evaluator for the given project root
func New(projectRoot string, opts ...Option) (*Evaluator, error) {
	absRoot, err := filepath.Abs(projectRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve project root: %w", err)
	}

	e := &Evaluator{
		projectRoot: absRoot,
		timeout:     10 * time.Second,
		cacheTTL:    5 * time.Second,
	}

	for _, opt := range opts {
		opt(e)
	}

	return e, nil
}

// Eval returns the latest nix eval result, using the cache when valid.
// This is the primary method the agent calls on every API request. It uses a
// double-checked locking pattern: the fast path (RLock) serves cached data,
// and only acquires a write lock when re-evaluation is actually needed.
func (e *Evaluator) Eval(ctx context.Context) ([]byte, error) {
	e.mu.RLock()
	if e.cached != nil && !e.invalidated && time.Since(e.cachedAt) < e.cacheTTL {
		defer e.mu.RUnlock()
		return e.cached, nil
	}
	e.mu.RUnlock()

	e.mu.Lock()
	defer e.mu.Unlock()

	// Re-check after lock promotion -- another goroutine may have refreshed.
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

// evalNix shells out to `nix eval` and returns raw JSON bytes, trying the
// configured flake attributes in order.
func (e *Evaluator) evalNix(ctx context.Context) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, e.timeout)
	defer cancel()

	if len(e.flakeAttrs) > 0 {
		return e.evalNixWithFallbacks(ctx, e.flakeAttrs)
	}

	args := []string{"eval", "--impure", "--json"}

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

// evalNixWithFallbacks tries multiple flake attributes in order, returning the
// first success. This supports both user projects (which expose config via
// devshell passthru) and the stackpanel repo itself (which uses a top-level
// flake output). If the context deadline fires, it aborts immediately rather
// than trying the remaining fallbacks.
func (e *Evaluator) evalNixWithFallbacks(
	ctx context.Context,
	attrs []string,
) ([]byte, error) {
	var lastErr error

	for _, attr := range attrs {
		args := []string{"eval", "--impure", "--json", attr}

		cmd := exec.CommandContext(ctx, "nix", args...)
		cmd.Dir = e.projectRoot

		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr

		if err := cmd.Run(); err != nil {
			if ctx.Err() == context.DeadlineExceeded {
				return nil, fmt.Errorf("nix eval timed out after %v", e.timeout)
			}
			lastErr = fmt.Errorf(
				"nix eval %s failed: %w\nstderr: %s",
				attr,
				err,
				stderr.String(),
			)
			continue // Try next fallback
		}

		// Success!
		return stdout.Bytes(), nil
	}

	return nil, fmt.Errorf("all flake attribute paths failed, last error: %w", lastErr)
}

// Invalidate manually invalidates the cache
func (e *Evaluator) Invalidate() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.invalidated = true
}

// GetAppPort returns the port for an app, or 0 if the app is not configured.
func (c *Config) GetAppPort(name string) int {
	if app, ok := c.Apps[name]; ok {
		return app.Port
	}
	return 0
}

// GetServicePort returns the port for a service, or 0 if the service is not configured.
func (c *Config) GetServicePort(name string) int {
	if svc, ok := c.Services[name]; ok {
		return svc.Port
	}
	return 0
}
