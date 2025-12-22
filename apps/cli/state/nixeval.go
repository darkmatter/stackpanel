package state

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
)

// evalNixConfig runs nix eval and parses the result
func evalNixConfig(ctx context.Context, projectRoot, nixFile string) (*State, error) {
	cmd := exec.CommandContext(ctx, "nix", "eval", "--impure", "--json", "-f", nixFile)
	cmd.Dir = projectRoot

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return nil, fmt.Errorf("nix eval timed out")
		}
		return nil, fmt.Errorf("nix eval failed: %w", err)
	}

	var state State
	if err := json.Unmarshal(stdout.Bytes(), &state); err != nil {
		return nil, fmt.Errorf("failed to parse nix eval output: %w", err)
	}

	// Check for error field in response
	type errorCheck struct {
		Error string `json:"error"`
	}
	var errCheck errorCheck
	json.Unmarshal(stdout.Bytes(), &errCheck)
	if errCheck.Error != "" {
		return nil, fmt.Errorf("nix eval returned error: %s", errCheck.Error)
	}

	if state.ProjectRoot == "" {
		state.ProjectRoot = projectRoot
	}

	return &state, nil
}
