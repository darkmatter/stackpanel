package util

import (
	"os"
	"strings"
	"testing"
)

func TestScaffoldRepoCreatesPlainGitRepo(t *testing.T) {
	t.Parallel()

	repo := ScaffoldRepo(t)

	assertDirExists(t, repo.Path(".git"))
	assertFileExists(t, repo.FlakePath)
	assertFileMissing(t, repo.ConfigPath)

	flake := readTestFile(t, repo.FlakePath)
	if strings.Contains(flake, "stackpanel") {
		t.Fatalf("plain repo flake should not reference stackpanel: %s", flake)
	}
}

func TestScaffoldStackpanelRepoCreatesStackpanelConfig(t *testing.T) {
	t.Parallel()

	repo := ScaffoldStackpanelRepo(t)

	assertDirExists(t, repo.Path(".git"))
	assertFileExists(t, repo.FlakePath)
	assertFileExists(t, repo.ConfigPath)

	config := readTestFile(t, repo.ConfigPath)
	if !strings.Contains(config, "enable = true;") {
		t.Fatalf("stackpanel config should enable stackpanel: %s", config)
	}
	if !strings.Contains(config, `name = "test-project";`) {
		t.Fatalf("stackpanel config should set project name: %s", config)
	}
}

func assertDirExists(t *testing.T, path string) {
	t.Helper()

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("expected directory %s to exist: %v", path, err)
	}
	if !info.IsDir() {
		t.Fatalf("expected %s to be a directory", path)
	}
}

func assertFileExists(t *testing.T, path string) {
	t.Helper()

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("expected file %s to exist: %v", path, err)
	}
	if info.IsDir() {
		t.Fatalf("expected %s to be a file", path)
	}
}

func assertFileMissing(t *testing.T, path string) {
	t.Helper()

	if _, err := os.Stat(path); err == nil {
		t.Fatalf("expected %s to be missing", path)
	} else if !os.IsNotExist(err) {
		t.Fatalf("expected %s to be missing, got error: %v", path, err)
	}
}

func readTestFile(t *testing.T, path string) string {
	t.Helper()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read %s: %v", path, err)
	}
	return string(data)
}
