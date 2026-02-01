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

// Executor runs commands in the project context
type Executor struct {
	projectRoot     string
	allowedCommands map[string]bool

	// Devshell environment support
	devshellEnv []string // Cached devshell environment variables
	inDevshell  bool     // Whether the agent was started inside a devshell
}

// Result of command execution
type Result struct {
	ExitCode int    `json:"exit_code"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
}

// New creates a new executor
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

// NewWithoutDevshell creates a new executor without attempting to load the devshell environment.
// Useful for testing or when you know you don't need devshell support.
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

// HasDevshellEnv returns whether devshell environment variables are loaded
func (e *Executor) HasDevshellEnv() bool {
	return e.inDevshell || len(e.devshellEnv) > 0
}

// LoadDevshellEnv loads the devshell environment for the project using `nix print-dev-env`.
// This is called automatically by New() if not already in a devshell.
// Can be called manually to refresh the cached environment.
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

// parseDevEnvOutput parses the output of `nix print-dev-env` and extracts
// environment variable assignments.
//
// The output format is a bash script with export statements like:
//
//	export PATH="/nix/store/xxx:$PATH"
//	export FOO="bar"
//
// We extract these and return them as KEY=value strings.
func parseDevEnvOutput(output string) []string {
	var envVars []string

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)

		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Look for export statements
		if strings.HasPrefix(line, "export ") {
			// Remove "export " prefix
			assignment := strings.TrimPrefix(line, "export ")

			// Find the = sign
			eqIdx := strings.Index(assignment, "=")
			if eqIdx == -1 {
				continue
			}

			key := assignment[:eqIdx]
			value := assignment[eqIdx+1:]

			// Remove surrounding quotes if present
			if len(value) >= 2 {
				if (value[0] == '"' && value[len(value)-1] == '"') ||
					(value[0] == '\'' && value[len(value)-1] == '\'') {
					value = value[1 : len(value)-1]
				}
			}

			// Skip certain variables that shouldn't be overridden
			if shouldSkipEnvVar(key) {
				continue
			}

			envVars = append(envVars, key+"="+value)
		}
	}

	return envVars
}

// shouldSkipEnvVar returns true for environment variables that shouldn't be
// inherited from the devshell (e.g., they're process-specific)
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

// Run executes a command and returns the result
func (e *Executor) Run(command string, args ...string) (*Result, error) {
	return e.RunWithOptions(command, e.projectRoot, nil, args...)
}

// RunNix runs a nix command
func (e *Executor) RunNix(args ...string) (*Result, error) {
	return e.Run("nix", args...)
}

// RunWithOptions executes a command in a specific directory and optional environment overrides.
//
// - cwd: if empty, uses the project root.
// - env: list of "KEY=value" strings appended to the environment.
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

// mergeEnv merges two environment variable slices.
// Variables in `overrides` take precedence over `base`.
// Both slices should contain strings in "KEY=value" format.
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

// GetEnv retrieves an environment variable value from the devshell environment.
// It first checks the cached devshell env, then falls back to os.Getenv.
// Returns empty string if the variable is not found.
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

// SetProjectRoot updates the project root and optionally reloads the devshell environment.
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
