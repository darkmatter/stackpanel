package nixeval

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// EvalOnce performs a one-shot evaluation of the stackpanel config
// This is useful for CLI commands that just need the config once
func EvalOnce(ctx context.Context, projectRoot string) (*Config, error) {
	if projectRoot == "" {
		// Try to find project root
		projectRoot = findProjectRoot()
		if projectRoot == "" {
			return nil, fmt.Errorf("could not find project root - are you in a stackpanel project?")
		}
	}

	absRoot, err := filepath.Abs(projectRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve project root: %w", err)
	}

	nixFile := filepath.Join(absRoot, "nix", "eval", "stackpanel-config.nix")

	// Check if nix file exists
	if _, err := os.Stat(nixFile); os.IsNotExist(err) {
		// Fall back to state file
		return loadFromStateFile(absRoot)
	}

	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "nix", "eval", "--impure", "--json", "-f", nixFile)
	cmd.Dir = absRoot

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		// Fall back to state file on nix eval failure
		if config, stateErr := loadFromStateFile(absRoot); stateErr == nil {
			return config, nil
		}
		return nil, fmt.Errorf("nix eval failed: %w\nstderr: %s", err, stderr.String())
	}

	var config Config
	if err := json.Unmarshal(stdout.Bytes(), &config); err != nil {
		return nil, fmt.Errorf("failed to parse nix eval output: %w", err)
	}

	if config.Error != "" {
		// Fall back to state file
		if stateConfig, stateErr := loadFromStateFile(absRoot); stateErr == nil {
			return stateConfig, nil
		}
		return nil, fmt.Errorf("%s: %s", config.Error, config.Hint)
	}

	if config.ProjectRoot == "" {
		config.ProjectRoot = absRoot
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
	// 1. Check DEVENV_ROOT env var
	if root := os.Getenv("DEVENV_ROOT"); root != "" {
		return root
	}

	// 2. Search up from current directory
	cwd, err := os.Getwd()
	if err != nil {
		return ""
	}

	dir := cwd
	for {
		if _, err := os.Stat(filepath.Join(dir, "devenv.nix")); err == nil {
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
func MustEvalOnce(ctx context.Context, projectRoot string) *Config {
	config, err := EvalOnce(ctx, projectRoot)
	if err != nil {
		panic(fmt.Sprintf("failed to evaluate stackpanel config: %v", err))
	}
	return config
}
