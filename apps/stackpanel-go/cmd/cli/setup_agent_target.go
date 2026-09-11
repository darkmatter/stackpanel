package cmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func prepareAgentSetupTarget(ctx context.Context, opts setupFlags) (string, error) {
	if opts.newDir == "" {
		return setupTargetDir(ctx, opts.tmp, false)
	}
	root, err := filepath.Abs(opts.newDir)
	if err != nil {
		return "", err
	}
	entries, err := os.ReadDir(root)
	if err != nil && !os.IsNotExist(err) {
		return "", err
	}
	if len(entries) != 0 {
		return "", fmt.Errorf("--new requires an absent or empty directory: %s", root)
	}
	if err := os.MkdirAll(root, 0o755); err != nil {
		return "", err
	}
	cmd := exec.CommandContext(ctx, "git", "init", root)
	if out, err := cmd.CombinedOutput(); err != nil {
		return "", fmt.Errorf("initialize repository: %w: %s", err, out)
	}
	return filepath.EvalSymlinks(root)
}
