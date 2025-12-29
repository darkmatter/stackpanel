package cmd

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
)

var agentCmd = &cobra.Command{
	Use:   "agent",
	Short: "Run the local Stackpanel agent",
	Long: `Run the local Stackpanel agent (stackpanel-agent).

The agent runs on your machine and exposes a localhost API used by the Stackpanel web UI
to run commands, evaluate Nix, and read/write files in the project.

This command will:
  - Prefer an installed 'stackpanel-agent' binary in PATH
  - Otherwise fall back to 'go run .' from the repo's apps/agent/ directory (dev mode)`,
	RunE: func(cmd *cobra.Command, args []string) error {
		configPath, _ := cmd.Flags().GetString("config")
		debug, _ := cmd.Flags().GetBool("debug")
		projectRoot, _ := cmd.Flags().GetString("project-root")

		agentArgs := make([]string, 0, 4)
		if configPath != "" {
			agentArgs = append(agentArgs, "--config", configPath)
		}
		if debug {
			agentArgs = append(agentArgs, "--debug")
		}

		// Allow users to force the project root without relying on the CWD.
		agentEnv := os.Environ()
		if projectRoot != "" {
			agentEnv = append(agentEnv, "STACKPANEL_PROJECT_ROOT="+projectRoot)
		}

		// Prefer installed binary.
		if bin, err := exec.LookPath("stackpanel-agent"); err == nil {
			c := exec.Command(bin, agentArgs...)
			c.Stdout = os.Stdout
			c.Stderr = os.Stderr
			c.Stdin = os.Stdin
			c.Env = agentEnv
			return c.Run()
		}

		// Dev fallback: run from repo.
		repoRoot, err := findRepoRoot()
		if err != nil {
			return fmt.Errorf("stackpanel-agent not found in PATH and repo root not detected: %w", err)
		}

		agentDir := filepath.Join(repoRoot, "apps", "agent")
		if _, err := os.Stat(filepath.Join(agentDir, "main.go")); err != nil {
			return errors.New("stackpanel-agent not found in PATH and apps/agent is missing (cannot run fallback)")
		}

		goArgs := append([]string{"run", "."}, agentArgs...)
		c := exec.Command("go", goArgs...)
		c.Dir = agentDir
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		c.Stdin = os.Stdin
		c.Env = agentEnv
		return c.Run()
	},
}

func init() {
	agentCmd.Flags().String("config", "", "Path to agent config file")
	agentCmd.Flags().Bool("debug", false, "Enable debug logging")
	agentCmd.Flags().String("project-root", "", "Project root to run the agent in (defaults to current working directory)")
}

func findRepoRoot() (string, error) {
	// devenv sets DEVENV_ROOT, which is the repo root for stackpanel itself.
	if v := strings.TrimSpace(os.Getenv("DEVENV_ROOT")); v != "" {
		return v, nil
	}

	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}

	dir := cwd
	for {
		// Heuristic: stackpanel repo has apps/agent/main.go.
		if _, err := os.Stat(filepath.Join(dir, "apps", "agent", "main.go")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	return "", errors.New("could not locate repo root (apps/agent/main.go not found in parents)")
}
