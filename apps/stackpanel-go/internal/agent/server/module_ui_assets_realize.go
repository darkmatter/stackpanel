package server

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

// A pure eval instantiates a derivation, not necessarily its outputs. On an
// authenticated open/run only, realize the derivation for that exact output.
// No flake input, shell command, ambient PATH, or mutable profile is accepted.
func ensureModuleOutput(ctx context.Context, projectRoot, output, drv string) error {
	if !validModulePackage(output, moduleStoreRoot) ||
		!validModulePackage(drv, moduleStoreRoot) ||
		!strings.HasSuffix(drv, ".drv") {
		return errors.New("invalid module derivation declaration")
	}
	if _, err := os.Lstat(output); err == nil {
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	var nixStore string
	for _, bin := range []string{"/nix/var/nix/profiles/default/bin/nix-store", "/run/current-system/sw/bin/nix-store"} {
		if _, err := os.Stat(bin); err == nil {
			nixStore = bin
			break
		}
	}
	if nixStore == "" {
		return errors.New("cannot realize module output: system nix-store not installed")
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	command := func(args ...string) *exec.Cmd {
		cmd := exec.CommandContext(ctx, nixStore, args...)
		cmd.Dir = projectRoot
		cmd.Env = []string{
			"PATH=" + filepath.Dir(nixStore) + ":/usr/bin:/bin",
			"HOME=" + os.Getenv("HOME"),
		}
		return cmd
	}
	outs, err := command("--query", "--outputs", drv).Output()
	if err != nil || !slices.Contains(strings.Fields(string(outs)), output) {
		return errors.New("module output does not belong to its declared derivation")
	}
	if err := command("--realise", "--no-build-output", drv).Run(); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return errors.New("could not realize evaluated module output")
	}
	_, err = os.Lstat(output)
	return err
}
