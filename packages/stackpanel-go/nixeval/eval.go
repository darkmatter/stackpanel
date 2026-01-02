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

//go:embed eval.nix
var evalNixContent []byte

// hasAbsoluteEnvPaths checks if the stackpanel env vars contain absolute paths,
// meaning we don't need projectRoot to construct valid paths
func hasAbsoluteEnvPaths() bool {
	// If any of these are set with absolute paths, eval.nix can find config
	nixConfig := os.Getenv("STACKPANEL_NIX_CONFIG")
	stateDir := os.Getenv("STACKPANEL_STATE_DIR")
	root := os.Getenv("STACKPANEL_ROOT")

	// Check if we have at least one absolute path that eval.nix can use
	if nixConfig != "" && strings.HasPrefix(nixConfig, "/") {
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

// EvalOnce performs a one-shot evaluation of the stackpanel config
// This is useful for CLI commands that just need the config once.
//
// projectRoot is optional if:
//   - STACKPANEL_NIX_CONFIG is set to an absolute path, or
//   - STACKPANEL_STATE_DIR is set to an absolute path, or
//   - STACKPANEL_ROOT is set to an absolute path
//
// If projectRoot is empty and no absolute env paths are set, it will
// attempt to find the project root by searching for devenv.nix
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

	// Build nix eval command - only pass projectRoot if we have it
	args := []string{"eval", "--impure", "--json", "-f", nixFile}
	if absRoot != "" {
		args = append(args, "--argstr", "root", absRoot)
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

type EvalOnceParams struct {
	Expression  string
	File        string
	Args        map[string]string
	ProjectRoot string
	Timeout     time.Duration
}

func EvalOnce(ctx context.Context, opts EvalOnceParams) ([]byte, error) {
	var absRoot string
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	// Build nix eval command - only pass projectRoot if we have it
	args := []string{"eval", "--impure", "--json"}
	if opts.Expression != "" {
		args = append(args, "--expr", opts.Expression)
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

	var config Config
	if err := json.Unmarshal(stdout.Bytes(), &config); err != nil {
		return nil, fmt.Errorf("failed to parse nix eval output: %w", err)
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

// loadFromStateFile loads config from the state.json file
func loadFromStateFile(projectRoot string) (*Config, error) {
	stateFile := filepath.Join(projectRoot, ".stackpanel", "state", "stackpanel.json")

	data, err := os.ReadFile(stateFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read state file: %w", err)
	}

	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse state file: %w", err)
	}

	if config.ProjectRoot == "" {
		config.ProjectRoot = projectRoot
	}

	return &config, nil
}

// findProjectRoot searches for the project root by looking for devenv.nix
func findProjectRoot() string {
	// 1. Check STACKPANEL_ROOT env var (preferred)
	if root := os.Getenv("STACKPANEL_ROOT"); root != "" && strings.HasPrefix(root, "/") {
		return root
	}

	// 3. Search up from current directory
	cwd, err := os.Getwd()
	if err != nil {
		return ""
	}

	dir := cwd
	for {
		if _, err := os.Stat(filepath.Join(dir, ".stackpanel-root")); err == nil {
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

// MustEvalOnce is like EvalOnce but panics on error
// Useful for initialization code
func MustEvalOnceConfig(ctx context.Context, projectRoot string) *Config {
	config, err := GetConfigWithEval(ctx, projectRoot)
	if err != nil {
		panic(fmt.Sprintf("failed to evaluate stackpanel config: %v", err))
	}
	return config
}

func MustEvalOnce(ctx context.Context, opts EvalOnceParams) []byte {
	result, err := EvalOnce(ctx, opts)
	if err != nil {
		panic(fmt.Sprintf("failed to evaluate stackpanel result: %v", err))
	}
	return result
}
