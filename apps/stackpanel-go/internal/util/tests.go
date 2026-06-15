package util

import (
	"os"
	"path/filepath"
	"testing"
)

const (
	plainFlakeContent = `{
  description = "plain test repo";

  outputs = { self }: {};
}
`

	stackpanelFlakeContent = `{
  description = "stackpanel test repo";

  inputs.stackpanel.url = "github:darkmatter/stackpanel";

  outputs = { self, stackpanel }: {};
}
`

	stackpanelConfigContent = `{ ... }: {
  stackpanel = {
    enable = true;
    name = "test-project";
  };
}
`
)

// TestRepo describes a temporary repository scaffold created for tests.
type TestRepo struct {
	Root       string
	GitDir     string
	FlakePath  string
	StackDir   string
	ConfigPath string
}

// Path returns an absolute path under the test repository root.
func (r TestRepo) Path(elem ...string) string {
	parts := append([]string{r.Root}, elem...)
	return filepath.Join(parts...)
}

// ScaffoldRepo creates a minimal non-Stackpanel git repository fixture.
func ScaffoldRepo(t testing.TB) TestRepo {
	t.Helper()

	root := makeTestRepoRoot(t)
	repo := TestRepo{
		Root:       root,
		GitDir:     filepath.Join(root, ".git"),
		FlakePath:  filepath.Join(root, "flake.nix"),
		StackDir:   filepath.Join(root, ".stack"),
		ConfigPath: filepath.Join(root, ".stack", "config.nix"),
	}

	mkdirTestDir(t, repo.GitDir)
	writeTestFile(t, repo.FlakePath, plainFlakeContent)

	return repo
}

// ScaffoldStackpanelRepo creates a minimal Stackpanel git repository fixture.
func ScaffoldStackpanelRepo(t testing.TB) TestRepo {
	t.Helper()

	repo := ScaffoldRepo(t)
	mkdirTestDir(t, repo.StackDir)
	writeTestFile(t, repo.FlakePath, stackpanelFlakeContent)
	writeTestFile(t, repo.ConfigPath, stackpanelConfigContent)

	return repo
}

func makeTestRepoRoot(t testing.TB) string {
	t.Helper()

	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get working directory: %v", err)
	}

	root, err := os.MkdirTemp(cwd, ".stackpanel-test-repo-*")
	if err != nil {
		t.Fatalf("failed to create test repo: %v", err)
	}
	t.Cleanup(func() {
		_ = os.RemoveAll(root)
	})

	return root
}

func mkdirTestDir(t testing.TB, path string) {
	t.Helper()

	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("failed to create directory %s: %v", path, err)
	}
}

func writeTestFile(t testing.TB, path string, content string) {
	t.Helper()

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("failed to create parent directory for %s: %v", path, err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("failed to write %s: %v", path, err)
	}
}
