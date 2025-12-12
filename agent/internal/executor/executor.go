package executor

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"

	"github.com/rs/zerolog/log"
)

// Executor runs commands in the project context
type Executor struct {
	projectRoot     string
	allowedCommands map[string]bool
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

	return &Executor{
		projectRoot:     projectRoot,
		allowedCommands: allowed,
	}, nil
}

// Run executes a command and returns the result
func (e *Executor) Run(command string, args ...string) (*Result, error) {
	// Check if command is allowed (if allowlist is configured)
	if len(e.allowedCommands) > 0 {
		baseCmd := strings.Split(command, " ")[0]
		if !e.allowedCommands[baseCmd] {
			return nil, fmt.Errorf("command not allowed: %s", baseCmd)
		}
	}

	log.Debug().
		Str("command", command).
		Strs("args", args).
		Str("cwd", e.projectRoot).
		Msg("Executing command")

	cmd := exec.Command(command, args...)
	cmd.Dir = e.projectRoot

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

// RunNix runs a nix command
func (e *Executor) RunNix(args ...string) (*Result, error) {
	return e.Run("nix", args...)
}
