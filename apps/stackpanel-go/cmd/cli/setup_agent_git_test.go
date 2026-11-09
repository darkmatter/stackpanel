package cmd

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestSetupExposesNewFilesAndNixInputsToGit(t *testing.T) {
	setupStateTestEnvironment(t)
	root := setupGitFixture(t)
	ctx := context.Background()
	// Earlier non-agent runs can leave Stackpanel's own config untracked.
	writeSetupGitFile(t, root, ".stack/config.nix", "{ }\n")
	state := &setupManifest{Version: 1, Root: root, Stage: stageInspection, path: setupStatePath(root)}
	files, err := newSetupFiles(ctx, state)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(state.UntrackedAtStart, []string{".stack/config.nix", "notes [do not touch].txt"}) {
		t.Fatalf("untracked files before setup = %q", state.UntrackedAtStart)
	}
	for _, path := range []string{"flake.lock", "apps/web/src/index.ts", ":[literal].nix", ".stack/gen/generated.nix", ".stack/keys/new.nix", "packages/gen/env/src/index.ts"} {
		writeSetupGitFile(t, root, path, "new setup output\n")
	}
	if err := files.expose(ctx, nil); err != nil {
		t.Fatal(err)
	}
	// A rerun knows which files predate the setup, so the earlier run's
	// output is still new.
	writeSetupGitFile(t, root, "apps/web/package.json", "{}\n")
	if files, err = newSetupFiles(ctx, state); err != nil {
		t.Fatal(err)
	}
	if err := files.expose(ctx, nil); err != nil {
		t.Fatal(err)
	}
	tracked := strings.Split(strings.TrimSpace(string(setupGitTestRun(t, root, "ls-files"))), "\n")
	for _, path := range []string{"flake.lock", "apps/web/src/index.ts", "apps/web/package.json", ":[literal].nix", ".stack/config.nix"} {
		if !slices.Contains(tracked, path) {
			t.Errorf("%s is not visible to Nix: %q", path, tracked)
		}
	}
	for _, path := range []string{"notes [do not touch].txt", ".stack/gen/generated.nix", ".stack/keys/new.nix", "packages/gen/env/src/index.ts"} {
		if slices.Contains(tracked, path) {
			t.Errorf("%s was added to Git", path)
		}
	}
	if staged := strings.TrimSpace(string(setupGitTestRun(t, root, "diff", "--cached", "--name-only"))); staged != "staged.txt" {
		t.Fatalf("setup staged content: %q", staged)
	}
}

func TestSetupFilesOutsideGit(t *testing.T) {
	setupStateTestEnvironment(t)
	root := t.TempDir()
	state := &setupManifest{Version: 1, Root: root, Stage: stageInspection, path: setupStatePath(root)}
	files, err := newSetupFiles(context.Background(), state)
	if err != nil {
		t.Fatal(err)
	}
	if err := files.expose(context.Background(), []string{"main.go"}); err != nil {
		t.Fatal(err)
	}
}

func setupGitFixture(t *testing.T) string {
	t.Helper()
	t.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	root := t.TempDir()
	setupGitTestRun(t, root, "init", "-q")
	setupGitTestRun(t, root, "config", "user.name", "Stackpanel Test")
	setupGitTestRun(t, root, "config", "user.email", "test@example.invalid")
	for _, path := range []string{"clean.txt", "staged.txt", "unstaged.txt"} {
		writeSetupGitFile(t, root, path, "committed\n")
	}
	writeSetupGitFile(t, root, ".gitignore", ".stack/profile/\n.stack/state/\n")
	setupGitTestRun(t, root, "add", ".")
	setupGitTestRun(t, root, "commit", "-qm", "fixture")
	writeSetupGitFile(t, root, "staged.txt", "staged user edit\n")
	setupGitTestRun(t, root, "add", "staged.txt")
	writeSetupGitFile(t, root, "staged.txt", "staged user edit\nadditional unstaged edit\n")
	writeSetupGitFile(t, root, "unstaged.txt", "unstaged user edit\n")
	writeSetupGitFile(t, root, "notes [do not touch].txt", "existing untracked content\n")
	return root
}

func setupGitTestRun(t *testing.T, root string, args ...string) []byte {
	t.Helper()
	data, err := setupGitCommand(context.Background(), root, args...)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func writeSetupGitFile(t *testing.T, root, path, content string) {
	t.Helper()
	file := filepath.Join(root, path)
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
