// Package executor wraps os/exec with Nix devshell awareness.
//
// The core problem: when the agent starts outside a Nix devshell (e.g. as a
// systemd service or launched from the web UI), commands like "nix", "caddy",
// or project-specific tools aren't on PATH. This package solves that by
// running `nix print-dev-env` once, caching the resulting environment, and
// injecting it into all spawned commands.
//
// If the agent is already inside a devshell (detected via STACKPANEL_ROOT,
// IN_NIX_SHELL, or DEVENV_ROOT env vars), the cached env is skipped and
// the process's own environment is used directly.
package executor

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
)

// Executor runs commands in the project context. It optionally maintains a
// cached copy of the Nix devshell environment so commands spawned outside
// a devshell still have access to Nix-provided packages and env vars.
//
// Thread-safe for reads; callers should not call SetProjectRoot or
// LoadDevshellEnv concurrently with command execution.
type Executor struct {
	projectRoot     string
	allowedCommands map[string]bool // empty map means allow all

	devshellEnv []string // cached `nix print-dev-env` output, nil if not loaded
	inDevshell  bool     // true if the current process is already in a devshell
}

// Result of command execution
type Result struct {
	ExitCode int    `json:"exit_code"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
}

// New creates a new executor. If not already in a devshell, it eagerly loads
// the devshell environment via `nix print-dev-env` (which may take several
// minutes on first run while Nix downloads packages). Failure to load is
// non-fatal — the executor falls back to the process environment, but
// commands requiring Nix-provided tools will likely fail.
func New(projectRoot string, allowedCommands []string) (*Executor, error) {
	allowed := make(map[string]bool)
	for _, cmd := range allowedCommands {
		allowed[cmd] = true
	}

	e := &Executor{
		projectRoot:     projectRoot,
		allowedCommands: allowed,
		inDevshell:      isInDevshell(),
	}

	// If not already in a devshell and we have a project root, try to load the devshell env
	if !e.inDevshell && projectRoot != "" {
		if err := e.LoadDevshellEnv(context.Background()); err != nil {
			// Log but don't fail - commands may still work without devshell env
			log.Warn().
				Err(err).
				Str("project_root", projectRoot).
				Msg("Failed to load devshell environment, commands may not have access to Nix packages")
		}
	}

	return e, nil
}

// NewWithoutDevshell creates an executor that skips the expensive
// `nix print-dev-env` call. Use this in tests or when you know the process
// is already in a devshell (where os.Environ() has everything needed).
func NewWithoutDevshell(projectRoot string, allowedCommands []string) (*Executor, error) {
	allowed := make(map[string]bool)
	for _, cmd := range allowedCommands {
		allowed[cmd] = true
	}

	return &Executor{
		projectRoot:     projectRoot,
		allowedCommands: allowed,
		inDevshell:      isInDevshell(),
	}, nil
}

// isInDevshell checks if the current process is running inside a Nix devshell
// by probing well-known environment variables. Checked once at construction
// time — the result won't change during the process lifetime.
func isInDevshell() bool {
	// STACKPANEL_ROOT is set by stackpanel devshell (most reliable indicator)
	if os.Getenv("STACKPANEL_ROOT") != "" {
		return true
	}
	// IN_NIX_SHELL is set by nix-shell and nix develop
	if os.Getenv("IN_NIX_SHELL") != "" {
		return true
	}
	// DEVENV_ROOT is set by devenv
	if os.Getenv("DEVENV_ROOT") != "" {
		return true
	}
	return false
}

// InDevshell returns whether the executor detected it's running in a devshell
func (e *Executor) InDevshell() bool {
	return e.inDevshell
}

// HasDevshellEnv returns whether devshell environment variables are available,
// either because we're inside a devshell (inherited) or because we loaded
// them via nix print-dev-env (cached).
func (e *Executor) HasDevshellEnv() bool {
	return e.inDevshell || len(e.devshellEnv) > 0
}

// LoadDevshellEnv loads the devshell environment via `nix print-dev-env`.
// Called automatically by New() if not already in a devshell. Can be called
// manually to refresh after flake.nix changes. The 5-minute timeout allows
// for Nix binary cache downloads on first run.
func (e *Executor) LoadDevshellEnv(ctx context.Context) error {
	if e.projectRoot == "" {
		return fmt.Errorf("no project root set")
	}

	log.Debug().
		Str("project_root", e.projectRoot).
		Msg("Loading devshell environment via nix print-dev-env")

	// Use a timeout context to avoid hanging indefinitely
	// 5 minutes allows time for Nix to download packages from caches
	timeoutCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	cmd := exec.CommandContext(timeoutCtx, "nix", "print-dev-env", "--impure")
	cmd.Dir = e.projectRoot
	cmd.Env = append(os.Environ(),
		"NIX_CONFIG=experimental-features = nix-command flakes",
	)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	startTime := time.Now()
	err := cmd.Run()
	duration := time.Since(startTime)

	if err != nil {
		log.Error().
			Err(err).
			Str("stderr", stderr.String()).
			Dur("duration", duration).
			Msg("nix print-dev-env failed")
		return fmt.Errorf("nix print-dev-env failed: %w\nstderr: %s", err, stderr.String())
	}

	log.Debug().
		Dur("duration", duration).
		Msg("nix print-dev-env completed")

	// Parse the output and extract environment variables
	e.devshellEnv = parseDevEnvOutput(stdout.String())

	log.Info().
		Int("env_vars", len(e.devshellEnv)).
		Dur("duration", duration).
		Msg("Loaded devshell environment")

	return nil
}

// parseDevEnvOutput parses the bash script output of `nix print-dev-env`
// and extracts KEY=value pairs from export and declare statements.
// Both `export FOO="bar"` and `declare -x FOO="bar"` forms are supported
// because different Nix versions emit different formats.
func parseDevEnvOutput(output string) []string {
	var envVars []string

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)

		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		var assignment string
		switch {
		case strings.HasPrefix(line, "export "):
			assignment = strings.TrimPrefix(line, "export ")
		case strings.HasPrefix(line, "declare -x "):
			assignment = strings.TrimPrefix(line, "declare -x ")
		default:
			continue
		}

		eqIdx := strings.Index(assignment, "=")
		if eqIdx == -1 {
			continue
		}

		key := assignment[:eqIdx]
		value := assignment[eqIdx+1:]

		if len(value) >= 2 {
			if (value[0] == '"' && value[len(value)-1] == '"') ||
				(value[0] == '\'' && value[len(value)-1] == '\'') {
				value = value[1 : len(value)-1]
			}
		}

		if shouldSkipEnvVar(key) {
			continue
		}

		envVars = append(envVars, key+"="+value)
	}

	return envVars
}

// shouldSkipEnvVar returns true for environment variables that shouldn't be
// inherited from the devshell output. These are process-local (PWD, SHLVL),
// user-session-specific (HOME, TMPDIR with /run/user/ paths), or terminal-
// specific (TERM, SHELL) and would cause subtle bugs if propagated.
func shouldSkipEnvVar(key string) bool {
	skip := map[string]bool{
		"PWD":             true, // Will be set by the command's working directory
		"OLDPWD":          true,
		"SHLVL":           true,
		"_":               true,
		"TERM":            true,
		"SHELL":           true,
		"HOME":            true,
		"USER":            true,
		"LOGNAME":         true,
		"TMPDIR":          true, // Often contains session-specific paths
		"XDG_RUNTIME_DIR": true,
	}
	return skip[key]
}

// Run executes a command in the project root directory with the full
// environment stack. This is the most common entry point — use
// RunWithOptions when you need a different working directory or extra env vars.
func (e *Executor) Run(command string, args ...string) (*Result, error) {
	return e.RunWithOptions(command, e.projectRoot, nil, args...)
}

// RunNix is a convenience wrapper for running nix subcommands.
// Satisfies the nixdata.NixRunner interface.
func (e *Executor) RunNix(args ...string) (*Result, error) {
	return e.Run("nix", args...)
}

// RunWithOptions executes a command with full control over working directory
// and environment. Non-zero exit codes are returned in Result.ExitCode
// (not as an error) so callers can inspect stdout/stderr. Only true exec
// failures (binary not found, permission denied) return an error.
//
// Environment precedence (later overrides earlier):
//  1. Current process environment (os.Environ())
//  2. Cached devshell environment (if loaded and not already in devshell)
//  3. Explicitly passed env parameter
func (e *Executor) RunWithOptions(
	command string,
	cwd string,
	env []string,
	args ...string,
) (*Result, error) {
	// Check if command is allowed (if allowlist is configured)
	if len(e.allowedCommands) > 0 {
		baseCmd := strings.Split(command, " ")[0]
		if !e.allowedCommands[baseCmd] {
			return nil, fmt.Errorf("command not allowed: %s", baseCmd)
		}
	}

	if cwd == "" {
		cwd = e.projectRoot
	}

	log.Debug().
		Str("command", command).
		Strs("args", args).
		Str("cwd", cwd).
		Bool("in_devshell", e.inDevshell).
		Bool("has_devshell_env", len(e.devshellEnv) > 0).
		Msg("Executing command")

	cmd := exec.Command(command, args...)
	cmd.Dir = cwd

	// Build environment: base -> devshell -> explicit overrides
	cmdEnv := os.Environ()

	// Add devshell env if we have it and aren't already in a devshell
	if !e.inDevshell && len(e.devshellEnv) > 0 {
		cmdEnv = mergeEnv(cmdEnv, e.devshellEnv)
	}

	// Add explicit overrides
	if len(env) > 0 {
		cmdEnv = mergeEnv(cmdEnv, env)
	}

	cmd.Env = cmdEnv

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()

	result := &Result{
		Stdout: stdout.String(),
		Stderr: stderr.String(),
	}

	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			// Non-zero exit: return the result with exit code so callers can
			// inspect stdout/stderr. Only return an error for exec failures
			// (binary not found, permission denied, etc.).
			result.ExitCode = exitErr.ExitCode()
		} else {
			return nil, fmt.Errorf("failed to execute command: %w", err)
		}
	}

	log.Debug().
		Int("exit_code", result.ExitCode).
		Int("stdout_len", len(result.Stdout)).
		Int("stderr_len", len(result.Stderr)).
		Msg("Command completed")

	return result, nil
}

// mergeEnv merges two environment variable slices. Variables in overrides
// take precedence over base. Note: the returned slice order is
// non-deterministic (map iteration) — this is fine since exec.Cmd.Env
// doesn't depend on ordering.
func mergeEnv(base, overrides []string) []string {
	// Build a map from base
	envMap := make(map[string]string)
	for _, e := range base {
		if idx := strings.Index(e, "="); idx != -1 {
			envMap[e[:idx]] = e[idx+1:]
		}
	}

	// Apply overrides
	for _, e := range overrides {
		if idx := strings.Index(e, "="); idx != -1 {
			envMap[e[:idx]] = e[idx+1:]
		}
	}

	// Convert back to slice
	result := make([]string, 0, len(envMap))
	for k, v := range envMap {
		result = append(result, k+"="+v)
	}

	return result
}

// ClearDevshellEnv clears the cached devshell environment.
// Useful if you want to force a reload.
func (e *Executor) ClearDevshellEnv() {
	e.devshellEnv = nil
}

// BuildEnv returns a merged environment suitable for passing to exec.Cmd.Env
// directly. Uses the same precedence as RunWithOptions: process env → devshell
// env → extra overrides. Useful when callers need to construct their own
// exec.Cmd (e.g. for process-compose with custom stdio).
func (e *Executor) BuildEnv(extra []string) []string {
	env := os.Environ()
	if !e.inDevshell && len(e.devshellEnv) > 0 {
		env = mergeEnv(env, e.devshellEnv)
	}
	if len(extra) > 0 {
		env = mergeEnv(env, extra)
	}
	return env
}

// GetEnv retrieves an environment variable, checking the cached devshell
// env first and falling back to os.Getenv. This means devshell values take
// precedence over the process environment, matching RunWithOptions behavior.
func (e *Executor) GetEnv(key string) string {
	// Check devshell env first
	prefix := key + "="
	for _, env := range e.devshellEnv {
		if strings.HasPrefix(env, prefix) {
			return env[len(prefix):]
		}
	}
	// Fall back to process environment
	return os.Getenv(key)
}

// SetProjectRoot updates the project root and optionally reloads the devshell
// environment. Clears the cached devshell env even if reloadDevshell is false,
// since the old env was for a different project.
func (e *Executor) SetProjectRoot(projectRoot string, reloadDevshell bool) error {
	e.projectRoot = projectRoot
	e.devshellEnv = nil

	if reloadDevshell && !e.inDevshell && projectRoot != "" {
		return e.LoadDevshellEnv(context.Background())
	}

	return nil
}

// ProjectRoot returns the current project root
func (e *Executor) ProjectRoot() string {
	return e.projectRoot
}
