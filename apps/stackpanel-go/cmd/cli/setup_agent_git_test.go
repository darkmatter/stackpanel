package cmd

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestSetupGitPreservesExistingEditsAndCleansVisibility(t *testing.T) {
	root := setupGitFixture(t)
	ctx := context.Background()
	guard, err := captureSetupGit(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	originalIndex := guard.index
	writeSetupGitFile(t, root, "clean.txt", "onboarding may edit clean tracked files\n")
	for _, path := range []string{"flake.lock", ".stack/new.nix", ".stack/title.txt", ":[literal].nix", "unrelated-new.txt", ".stack/gen/generated.nix", ".stack/keys/new.nix"} {
		writeSetupGitFile(t, root, path, "new onboarding content\n")
	}
	if err := guard.AddNixInputs(ctx); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"flake.lock", ".stack/new.nix", ".stack/title.txt", ":[literal].nix"} {
		if len(guard.owned[path]) != 1 || guard.owned[path][0].Flags&setupIntentToAdd == 0 {
			t.Fatalf("%q was not exposed with intent-to-add: %+v", path, guard.owned)
		}
	}
	if len(guard.owned) != 4 {
		t.Fatalf("unexpected files added to index: %+v", guard.owned)
	}
	writeSetupGitFile(t, root, ".stack/new.nix", "agent may revise its own new inputs\n")
	writeSetupGitFile(t, root, ".stack/second.nix", "second attempt\n")
	if err := guard.AddNixInputs(ctx); err != nil {
		t.Fatal(err)
	}
	if err := guard.Check(ctx); err != nil {
		t.Fatal(err)
	}
	if err := guard.Close(ctx); err != nil {
		t.Fatal(err)
	}
	finalIndex, err := setupReadIndex(ctx, root)
	if err != nil || !reflect.DeepEqual(originalIndex, finalIndex) {
		t.Fatalf("original index changed: %v\n%+v\n%+v", err, originalIndex, finalIndex)
	}
	if err := guard.Check(ctx); err != nil {
		t.Fatal(err)
	}
	if content, err := os.ReadFile(filepath.Join(root, ".stack/new.nix")); err != nil || string(content) != "agent may revise its own new inputs\n" {
		t.Fatalf("cleanup must retain worktree files: %q, %v", content, err)
	}
}

func TestSetupGitRejectsChangesToUserState(t *testing.T) {
	for _, test := range []struct {
		name string
		edit func(*testing.T, string)
		want string
	}{
		{"working edits", func(t *testing.T, root string) { writeSetupGitFile(t, root, "unstaged.txt", "overwritten") }, "preexisting user edits"},
		{"staged working file", func(t *testing.T, root string) { writeSetupGitFile(t, root, "staged.txt", "overwritten") }, "preexisting user edits"},
		{"untracked file", func(t *testing.T, root string) { writeSetupGitFile(t, root, "notes [do not touch].txt", "overwritten") }, "preexisting user edits"},
		{"deletion", func(t *testing.T, root string) {
			if err := os.Remove(filepath.Join(root, "unstaged.txt")); err != nil {
				t.Fatal(err)
			}
		}, "preexisting user edits"},
		{"mode change", func(t *testing.T, root string) {
			if err := os.Chmod(filepath.Join(root, "unstaged.txt"), 0o755); err != nil {
				t.Fatal(err)
			}
		}, "preexisting user edits"},
		{"stage user edits", func(t *testing.T, root string) { setupGitTestRun(t, root, "add", "unstaged.txt") }, "Git staging"},
		{"unstage user edits", func(t *testing.T, root string) { setupGitTestRun(t, root, "reset", "HEAD", "--", "staged.txt") }, "Git staging"},
		{"agent adds a new file", func(t *testing.T, root string) {
			writeSetupGitFile(t, root, ".stack/model.nix", "{}")
			setupGitTestRun(t, root, "add", "--intent-to-add", ".stack/model.nix")
		}, "Git staging"},
		{"commit", func(t *testing.T, root string) { setupGitTestRun(t, root, "commit", "-qm", "unexpected commit") }, "Git HEAD"},
	} {
		t.Run(test.name, func(t *testing.T) {
			root := setupGitFixture(t)
			guard, err := captureSetupGit(context.Background(), root)
			if err != nil {
				t.Fatal(err)
			}
			test.edit(t, root)
			if err := guard.Check(context.Background()); err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("expected %s rejection, got %v", test.want, err)
			}
			if err := guard.AddNixInputs(context.Background()); err == nil {
				t.Fatal("visibility staging should refuse an already altered baseline")
			}
		})
	}
}

func TestSetupGitCleanupDoesNotUnstageNewUserContent(t *testing.T) {
	root := setupGitFixture(t)
	ctx := context.Background()
	guard, err := captureSetupGit(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	writeSetupGitFile(t, root, "new.nix", "{}")
	if err := guard.AddNixInputs(ctx); err != nil {
		t.Fatal(err)
	}
	setupGitTestRun(t, root, "add", "new.nix")
	if err := guard.Check(ctx); err == nil {
		t.Fatal("accepted new staging")
	}
	before, err := setupReadIndex(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	if err := guard.Close(ctx); err != nil {
		t.Fatal(err)
	}
	after, err := setupReadIndex(ctx, root)
	if err != nil || !reflect.DeepEqual(before, after) {
		t.Fatalf("cleanup undid new user staging: %v", err)
	}
}

func TestSetupGitPreservesUserIntentAndUnusualPaths(t *testing.T) {
	root := setupGitFixture(t)
	ctx := context.Background()
	path := "user\tfile\n.nix"
	writeSetupGitFile(t, root, path, "{}")
	setupGitTestRun(t, root, "add", "--intent-to-add", "--", path)
	guard, err := captureSetupGit(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	if err := guard.AddNixInputs(ctx); err != nil {
		t.Fatal(err)
	}
	if len(guard.owned) != 0 {
		t.Fatal("claimed an existing user intent entry")
	}
	if err := guard.Close(ctx); err != nil {
		t.Fatal(err)
	}
	index, err := setupReadIndex(ctx, root)
	if err != nil || !reflect.DeepEqual(guard.index, index) {
		t.Fatalf("lost user's intent entry: %v", err)
	}
}

func TestSetupGitPreservesSymlinkTargets(t *testing.T) {
	root := setupGitFixture(t)
	link := filepath.Join(root, "user-link")
	if err := os.Symlink("first-missing-target", link); err != nil {
		t.Fatal(err)
	}
	guard, err := captureSetupGit(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(link); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("different-missing-target", link); err != nil {
		t.Fatal(err)
	}
	if err := guard.Check(context.Background()); err == nil {
		t.Fatal("accepted rewritten symlink")
	}
}

func TestSetupGitUnbornAndGitlessRepositories(t *testing.T) {
	ctx := context.Background()
	for _, withGit := range []bool{false, true} {
		root := t.TempDir()
		if withGit {
			setupGitTestRun(t, root, "init", "-q")
		}
		guard, err := captureSetupGit(ctx, root)
		if err != nil {
			t.Fatal(err)
		}
		writeSetupGitFile(t, root, "flake.nix", "{}")
		if err := guard.AddNixInputs(ctx); err != nil {
			t.Fatal(err)
		}
		if err := guard.Check(ctx); err != nil {
			t.Fatal(err)
		}
		if err := guard.Close(ctx); err != nil {
			t.Fatal(err)
		}
		if !withGit {
			if _, err := os.Stat(filepath.Join(root, ".git")); !os.IsNotExist(err) {
				t.Fatal("created a Git repo")
			}
		}
	}
}

func TestSetupGitExposesAcceptedNewSourcesWithoutTouchingUserInputs(t *testing.T) {
	root := setupGitFixture(t)
	ctx := context.Background()
	guard, err := captureSetupGit(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"apps/web/package.json", "apps/web/src/index.ts", "unrelated.txt", "packages/gen/env/src/index.ts"} {
		writeSetupGitFile(t, root, path, "new content")
	}
	if err := guard.AddNixInputs(ctx, "apps/web/package.json", "apps/web/src/index.ts", "notes [do not touch].txt", "packages/gen/env/src/index.ts"); err != nil {
		t.Fatal(err)
	}
	if len(guard.owned) != 2 {
		t.Fatalf("included user files, generated output, or unaccepted files: %+v", guard.owned)
	}
	for _, path := range []string{"apps/web/package.json", "apps/web/src/index.ts"} {
		if len(guard.owned[path]) != 1 || guard.owned[path][0].Flags&setupIntentToAdd == 0 {
			t.Fatalf("source unavailable to Git-backed Nix: %s", path)
		}
	}
	if err := guard.Close(ctx); err != nil {
		t.Fatal(err)
	}
	after, err := setupReadIndex(ctx, root)
	if err != nil || !reflect.DeepEqual(guard.index, after) {
		t.Fatalf("cleanup changed the user's index: %v", err)
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
	writeSetupGitFile(t, root, ".gitignore", ".stack/gen/\n.stack/profile/\n.stack/state/\n.stack/keys/\n")
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
