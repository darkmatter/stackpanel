package nixeval

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// evalNixContent holds the embedded eval.nix evaluator script. This script is
// written to a temp file and passed to `nix eval -f` so the Go binary is
// fully self-contained -- it doesn't need the stackpanel source tree at runtime.
//
//go:embed eval.nix
var evalNixContent []byte

// hasAbsoluteEnvPaths checks if the stackpanel env vars contain absolute paths,
// meaning we don't need projectRoot to construct valid paths
func hasAbsoluteEnvPaths() bool {
	// If any of these are set with absolute paths, eval.nix can find config
	configJson := os.Getenv("STACKPANEL_CONFIG_JSON")
	stateDir := os.Getenv("STACKPANEL_STATE_DIR")
	root := os.Getenv("STACKPANEL_ROOT")

	// Check if we have at least one absolute path that eval.nix can use
	if configJson != "" && strings.HasPrefix(configJson, "/") {
		return true
	}
	if stateDir != "" && strings.HasPrefix(stateDir, "/") {
		return true
	}
	if root != "" && strings.HasPrefix(root, "/") {
		return true
	}

	return false
}

// GetConfigWithEval performs a one-shot evaluation of the stackpanel config by
// shelling out to `nix eval` with the embedded eval.nix. This is the primary
// config-loading path for CLI commands.
//
// The function has an aggressive fallback chain: nix eval -> state file -> env vars.
// This means CLI commands work both inside and outside a devshell, and degrade
// gracefully when Nix is slow or unavailable.
//
// projectRoot is optional when any of STACKPANEL_CONFIG_JSON, STACKPANEL_STATE_DIR,
// or STACKPANEL_ROOT are set to absolute paths. Otherwise, it walks up from cwd
// looking for flake.nix or a .stack/ directory.
func GetConfigWithEval(ctx context.Context, projectRoot string) (*Config, error) {
	var absRoot string
	var needsProjectRoot bool

	// Check if we can proceed without projectRoot
	if projectRoot == "" && !hasAbsoluteEnvPaths() {
		// No absolute env paths, we need to find projectRoot
		projectRoot = findProjectRoot()
		if projectRoot == "" {
			needsProjectRoot = true
		}
	}

	// Resolve to absolute path if provided
	if projectRoot != "" {
		var err error
		absRoot, err = filepath.Abs(projectRoot)
		if err != nil {
			return nil, fmt.Errorf("failed to resolve project root: %w", err)
		}
	}

	// Write embedded eval.nix to a temp file for nix eval
	tmpFile, err := os.CreateTemp("", "stackpanel-eval-*.nix")
	if err != nil {
		// Fall back to state file if we have enough info
		if absRoot != "" {
			return loadFromStateFile(absRoot)
		}
		if stateDir := os.Getenv("STACKPANEL_STATE_DIR"); stateDir != "" && strings.HasPrefix(stateDir, "/") {
			return loadFromStateDirEnv(stateDir)
		}
		return nil, fmt.Errorf("failed to create temp file and no fallback available: %w", err)
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.Write(evalNixContent); err != nil {
		tmpFile.Close()
		if absRoot != "" {
			return loadFromStateFile(absRoot)
		}
		return nil, fmt.Errorf("failed to write temp file: %w", err)
	}
	tmpFile.Close()

	nixFile := tmpFile.Name()

	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	// Build nix eval command. We pass values as --argstr rather than relying on
	// builtins.getEnv in eval.nix. This makes evaluation effectively pure (faster,
	// more cacheable) while --impure is kept as a safety net for edge cases where
	// root is unknown and eval.nix must fall back to reading env vars.
	args := []string{"eval", "--impure", "--json", "-f", nixFile}
	if absRoot != "" {
		args = append(args, "--argstr", "root", absRoot)
	}
	if v := os.Getenv("STACKPANEL_CONFIG_JSON"); v != "" {
		args = append(args, "--argstr", "configJson", v)
	}
	if v := os.Getenv("STACKPANEL_STATE_DIR"); v != "" {
		args = append(args, "--argstr", "stateDir", v)
	}

	cmd := exec.CommandContext(ctx, "nix", args...)
	if absRoot != "" {
		cmd.Dir = absRoot
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		// Fall back to state file on nix eval failure
		if absRoot != "" {
			if config, stateErr := loadFromStateFile(absRoot); stateErr == nil {
				return config, nil
			}
		}
		if stateDir := os.Getenv("STACKPANEL_STATE_DIR"); stateDir != "" && strings.HasPrefix(stateDir, "/") {
			if config, stateErr := loadFromStateDirEnv(stateDir); stateErr == nil {
				return config, nil
			}
		}
		if needsProjectRoot {
			return nil, fmt.Errorf("could not find project root and nix eval failed - are you in a stackpanel project?\nstderr: %s", stderr.String())
		}
		return nil, fmt.Errorf("nix eval failed: %w\nstderr: %s", err, stderr.String())
	}

	var config Config
	if err := json.Unmarshal(stdout.Bytes(), &config); err != nil {
		return nil, fmt.Errorf("failed to parse nix eval output: %w", err)
	}

	if config.Error != "" {
		// Fall back to state file
		if absRoot != "" {
			if stateConfig, stateErr := loadFromStateFile(absRoot); stateErr == nil {
				return stateConfig, nil
			}
		}
		if stateDir := os.Getenv("STACKPANEL_STATE_DIR"); stateDir != "" && strings.HasPrefix(stateDir, "/") {
			if stateConfig, stateErr := loadFromStateDirEnv(stateDir); stateErr == nil {
				return stateConfig, nil
			}
		}
		return nil, fmt.Errorf("%s: %s", config.Error, config.Hint)
	}

	// Fill in projectRoot from env if not set in config
	if config.ProjectRoot == "" {
		if absRoot != "" {
			config.ProjectRoot = absRoot
		} else if envRoot := os.Getenv("STACKPANEL_ROOT"); envRoot != "" {
			config.ProjectRoot = envRoot
		}
	}

	return &config, nil
}

// EvalOnceParams configures a generic one-shot nix eval invocation.
type EvalOnceParams struct {
	Expression  string            // Nix expression or flake installable (e.g. ".#foo")
	File        string            // Path to a .nix file (mutually exclusive with Expression)
	Args        map[string]string // Passed as --argstr key value pairs
	ProjectRoot string
	Timeout     time.Duration
}

// EvalOnce runs a single `nix eval` invocation and returns raw JSON bytes.
// It auto-detects whether Expression is a flake installable (starts with ".#",
// "github:", etc.) or a plain Nix expression, and uses the appropriate CLI form.
func EvalOnce(ctx context.Context, opts EvalOnceParams) ([]byte, error) {
	var absRoot string
	if opts.ProjectRoot != "" {
		var err error
		absRoot, err = filepath.Abs(opts.ProjectRoot)
		if err != nil {
			return nil, fmt.Errorf("invalid project root %q: %w", opts.ProjectRoot, err)
		}
	}
	timeout := opts.Timeout
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	// Build nix eval command; cwd matters for expressions that use ./. or relative paths.
	args := []string{"eval", "--impure", "--json"}
	if opts.Expression != "" {
		// Check if expression is an installable (flake reference) vs a Nix expression
		// Installables start with .# (current flake), path# or flake:
		isInstallable := strings.HasPrefix(opts.Expression, ".#") ||
			strings.HasPrefix(opts.Expression, "path:") ||
			strings.HasPrefix(opts.Expression, "git+") ||
			strings.HasPrefix(opts.Expression, "github:") ||
			strings.HasPrefix(opts.Expression, "nixpkgs#")

		if isInstallable {
			// Pass installable directly without --expr
			args = append(args, opts.Expression)
		} else {
			// It's a Nix expression, use --expr
			args = append(args, "--expr", opts.Expression)
		}
	} else if opts.File != "" {
		args = append(args, "-f", opts.File)
	}
	for k, v := range opts.Args {
		args = append(args, "--argstr", k, v)
	}

	cmd := exec.CommandContext(ctx, "nix", args...)
	if absRoot != "" {
		cmd.Dir = absRoot
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("nix eval failed: %w\nstderr: %s", err, stderr.String())
	}

	return stdout.Bytes(), nil
}

// loadFromStateDirEnv loads config from STACKPANEL_STATE_DIR env var
func loadFromStateDirEnv(stateDir string) (*Config, error) {
	stateFile := filepath.Join(stateDir, "stackpanel.json")

	data, err := os.ReadFile(stateFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read state file: %w", err)
	}

	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse state file: %w", err)
	}

	// Try to get projectRoot from env if not in config
	if config.ProjectRoot == "" {
		if envRoot := os.Getenv("STACKPANEL_ROOT"); envRoot != "" {
			config.ProjectRoot = envRoot
		}
	}

	return &config, nil
}

// loadFromStateFile loads config from a pre-generated state file on disk.
// Tries the newer .stack/profile path first, then the legacy .stackpanel/state path.
// This is the fast fallback when nix eval is unavailable or too slow.
func loadFromStateFile(projectRoot string) (*Config, error) {
	for _, subpath := range []string{".stack/profile/stackpanel.json", ".stackpanel/state/stackpanel.json"} {
		stateFile := filepath.Join(projectRoot, subpath)
		if data, err := os.ReadFile(stateFile); err == nil {
			var cfg Config
			if err := json.Unmarshal(data, &cfg); err != nil {
				continue
			}
			cfg.ProjectRoot = projectRoot
			return &cfg, nil
		}
	}
	return nil, fmt.Errorf("no stackpanel state file found under .stack/profile or .stackpanel/state")
}

// findProjectRoot walks up from cwd looking for a flake.nix or .stack/ directory.
// Returns "" if no root is found (e.g. running outside any project).
func findProjectRoot() string {
	// 1. Check STACKPANEL_ROOT env var (preferred)
	if root := os.Getenv("STACKPANEL_ROOT"); root != "" && strings.HasPrefix(root, "/") {
		return root
	}

	// 2. Search up from current directory
	cwd, err := os.Getwd()
	if err != nil {
		return ""
	}

	dir := cwd
	for {
		if _, err := os.Stat(filepath.Join(dir, "flake.nix")); err == nil {
			return dir
		}
		if _, err := os.Stat(filepath.Join(dir, ".stack")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	return ""
}

// MustEvalOnceConfig is like GetConfigWithEval but panics on error.
// Only appropriate for program init where failure is unrecoverable.
func MustEvalOnceConfig(ctx context.Context, projectRoot string) *Config {
	config, err := GetConfigWithEval(ctx, projectRoot)
	if err != nil {
		panic(fmt.Sprintf("failed to evaluate stackpanel config: %v", err))
	}
	return config
}

// MustEvalOnce is like EvalOnce but panics on error.
func MustEvalOnce(ctx context.Context, opts EvalOnceParams) []byte {
	result, err := EvalOnce(ctx, opts)
	if err != nil {
		panic(fmt.Sprintf("failed to evaluate stackpanel result: %v", err))
	}
	return result
}
