package cmd

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Flakes in a Git repository only see files Git knows about, so setup adds the
// files it creates to the index with --intent-to-add before Nix evaluates
// them. That records the paths without staging their contents; review and
// commit stay with the user.
type setupNewFiles struct {
	root   string          // setup directory; empty outside a Git repository
	before map[string]bool // untracked files that predate the setup
}

// newSetupFiles records, once per manifest, which untracked files predate the
// setup, so files any run of it creates are recognized as new.
func newSetupFiles(ctx context.Context, state *setupManifest) (*setupNewFiles, error) {
	if _, err := setupGitCommand(ctx, state.Root, "rev-parse", "--git-dir"); err != nil {
		if strings.Contains(err.Error(), "not a git repository") {
			return &setupNewFiles{}, nil
		}
		return nil, err
	}
	if state.UntrackedAtStart == nil {
		paths, err := setupUntrackedFiles(ctx, state.Root)
		if err != nil {
			return nil, err
		}
		state.UntrackedAtStart = paths
		if err := state.save(); err != nil {
			return nil, err
		}
	}
	files := &setupNewFiles{root: state.Root, before: map[string]bool{}}
	for _, path := range state.UntrackedAtStart {
		files.before[path] = true
	}
	return files, nil
}

// expose adds untracked files to the index with --intent-to-add when the setup
// created them, the plan lists them, or Nix reads them (*.nix, flake.lock and
// .stack/). Generated output and private state are never added.
func (f *setupNewFiles) expose(ctx context.Context, planned []string) error {
	if f.root == "" {
		return nil
	}
	paths, err := setupUntrackedFiles(ctx, f.root)
	if err != nil {
		return err
	}
	listed := map[string]bool{}
	for _, path := range planned {
		listed[filepath.ToSlash(filepath.Clean(path))] = true
	}
	var add []string
	for _, path := range paths {
		if !setupGeneratedPath(path) && (!f.before[path] || listed[path] || setupNixInput(path)) {
			add = append(add, path)
		}
	}
	if len(add) == 0 {
		return nil
	}
	_, err = setupGitCommand(ctx, f.root, append([]string{"add", "--intent-to-add", "--"}, add...)...)
	return err
}

// setupUntrackedFiles lists untracked, unignored files under root, relative to
// it. The result is never nil, so an empty list can be told from none recorded.
func setupUntrackedFiles(ctx context.Context, root string) ([]string, error) {
	data, err := setupGitCommand(ctx, root, "ls-files", "--others", "--exclude-standard", "-z")
	if err != nil {
		return nil, err
	}
	paths := []string{}
	for _, path := range bytes.Split(data, []byte{0}) {
		if len(path) > 0 {
			paths = append(paths, string(path))
		}
	}
	return paths, nil
}

func setupNixInput(path string) bool {
	return strings.HasSuffix(path, ".nix") || filepath.Base(path) == "flake.lock" || strings.HasPrefix(path, ".stack/")
}

func setupGeneratedPath(path string) bool {
	for _, generated := range []string{".stack/gen/", ".stack/profile/", ".stack/state/", ".stack/keys/", "packages/gen/env/"} {
		if strings.HasPrefix(path, generated) {
			return true
		}
	}
	return false
}

func setupGitCommand(ctx context.Context, root string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "git", append([]string{"--literal-pathspecs", "-C", root}, args...)...)
	for _, value := range os.Environ() {
		key, _, _ := strings.Cut(value, "=")
		switch key {
		case "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR":
			continue
		}
		cmd.Env = append(cmd.Env, value)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	data, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("git %s: %w\n%s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return data, nil
}
