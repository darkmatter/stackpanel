package fileops

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestApplyManifestBacksUpExistingJSONFileOnFirstMutation(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	stateDir := filepath.Join(projectRoot, ".stack", "profile")
	targetPath := filepath.Join(projectRoot, "apps", "web", "package.json")
	original := map[string]any{
		"name": "web",
		"scripts": map[string]any{
			"dev": "vite dev",
		},
		"dependencies": map[string]any{
			"react": "^19.0.0",
		},
	}
	writeJSONFixture(t, targetPath, original)

	manifest := Manifest{
		Version: 1,
		Files: []Entry{
			{
				Path:  "apps/web/package.json",
				Type:  "json-ops",
				Adopt: "backup",
				Ops: []JSONOp{
					{
						Op:    "set",
						Path:  []string{"scripts", "dev"},
						Value: "portless stackpanel-web --app-port 3000 bun run --hot dev",
					},
				},
			},
		},
	}

	summary, err := ApplyManifest(projectRoot, stateDir, manifest)
	if err != nil {
		t.Fatalf("apply manifest should succeed: %v", err)
	}

	backupPath := targetPath + ".backup"
	if !slices.Contains(summary.Backups, backupPath) {
		t.Fatalf("expected backup summary for %s, got %#v", backupPath, summary)
	}

	backup := readJSONFixture(t, backupPath)
	if got := backup["name"]; got != "web" {
		t.Fatalf("backup should preserve original file, got %#v", backup)
	}
	if got := nestedMapValue(t, backup, "scripts", "dev"); got != "vite dev" {
		t.Fatalf("expected original dev script in backup, got %#v", got)
	}

	current := readJSONFixture(t, targetPath)
	if got := nestedMapValue(t, current, "scripts", "dev"); got != "portless stackpanel-web --app-port 3000 bun run --hot dev" {
		t.Fatalf("expected managed dev script, got %#v", current)
	}
	if got := nestedMapValue(t, current, "dependencies", "react"); got != "^19.0.0" {
		t.Fatalf("expected unrelated dependency to be preserved, got %#v", current)
	}

	secondSummary, err := ApplyManifest(projectRoot, stateDir, manifest)
	if err != nil {
		t.Fatalf("second apply should succeed: %v", err)
	}
	if len(secondSummary.Backups) != 0 {
		t.Fatalf("expected second apply to avoid creating a new backup, got %#v", secondSummary)
	}
}

func TestApplyManifestSupportsAllJSONOpTypesWithoutDroppingUnrelatedKeys(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	stateDir := filepath.Join(projectRoot, ".stack", "profile")
	targetPath := filepath.Join(projectRoot, "apps", "web", "package.json")
	writeJSONFixture(t, targetPath, map[string]any{
		"name": "web",
		"scripts": map[string]any{
			"dev":     "vite dev",
			"old-dev": "vite old",
		},
		"dependencies": map[string]any{
			"react": "^19.0.0",
		},
		"keywords": []any{"existing"},
		"custom": map[string]any{
			"keep": true,
		},
	})

	manifest := Manifest{
		Version: 1,
		Files: []Entry{
			{
				Path: "apps/web/package.json",
				Type: "json-ops",
				Ops: []JSONOp{
					{Op: "set", Path: []string{"scripts", "dev"}, Value: "bun run dev"},
					{Op: "merge", Path: []string{"dependencies"}, Value: map[string]any{"@gen/env": "workspace:*"}},
					{Op: "remove", Path: []string{"scripts", "old-dev"}},
					{Op: "append", Path: []string{"keywords"}, Value: "stackpanel"},
					{Op: "appendUnique", Path: []string{"keywords"}, Value: "stackpanel"},
				},
			},
		},
	}

	if _, err := ApplyManifest(projectRoot, stateDir, manifest); err != nil {
		t.Fatalf("apply manifest should succeed: %v", err)
	}

	current := readJSONFixture(t, targetPath)
	if got := nestedMapValue(t, current, "scripts", "dev"); got != "bun run dev" {
		t.Fatalf("expected dev script to be replaced, got %#v", current)
	}
	if got := nestedMapValue(t, current, "scripts", "old-dev"); got != nil {
		t.Fatalf("expected old-dev script to be removed, got %#v", current)
	}
	if got := nestedMapValue(t, current, "dependencies", "react"); got != "^19.0.0" {
		t.Fatalf("expected existing dependency to remain, got %#v", current)
	}
	if got := nestedMapValue(t, current, "dependencies", "@gen/env"); got != "workspace:*" {
		t.Fatalf("expected merged dependency to be added, got %#v", current)
	}
	keywords, ok := current["keywords"].([]any)
	if !ok {
		t.Fatalf("expected keywords array, got %#v", current["keywords"])
	}
	if !slices.Equal(keywords, []any{"existing", "stackpanel"}) {
		t.Fatalf("expected appendUnique to avoid duplicates, got %#v", keywords)
	}
	if got := nestedMapValue(t, current, "custom", "keep"); got != true {
		t.Fatalf("expected unrelated custom field to survive, got %#v", current)
	}
}

func TestApplyManifestUsesBackupAsBaselineWhenTrackedJSONFileIsMissing(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	stateDir := filepath.Join(projectRoot, ".stack", "profile")
	targetPath := filepath.Join(projectRoot, "apps", "web", "package.json")
	backupPath := targetPath + ".backup"

	writeJSONFixture(t, backupPath, map[string]any{
		"name": "web",
		"private": true,
		"scripts": map[string]any{
			"build:ec2": "vite build",
			"dev":       "vite dev",
		},
	})

	manifest := Manifest{
		Version: 1,
		Files: []Entry{
			{
				Path:  "apps/web/package.json",
				Type:  "json-ops",
				Adopt: "backup",
				Ops: []JSONOp{
					{Op: "set", Path: []string{"scripts", "dev"}, Value: "portless stackpanel.stackpanel --app-port 5775 bun run dev"},
				},
			},
		},
	}

	if _, err := ApplyManifest(projectRoot, stateDir, manifest); err != nil {
		t.Fatalf("apply manifest should succeed: %v", err)
	}

	current := readJSONFixture(t, targetPath)
	if got := current["name"]; got != "web" {
		t.Fatalf("expected name to be restored from backup, got %#v", current)
	}
	if got := current["private"]; got != true {
		t.Fatalf("expected private flag to be restored from backup, got %#v", current)
	}
	if got := nestedMapValue(t, current, "scripts", "build:ec2"); got != "vite build" {
		t.Fatalf("expected build:ec2 to be restored from backup, got %#v", current)
	}
	if got := nestedMapValue(t, current, "scripts", "dev"); got != "portless stackpanel.stackpanel --app-port 5775 bun run dev" {
		t.Fatalf("expected dev script to be updated, got %#v", current)
	}
}

func TestApplyManifestRepairsManagedOnlyJSONFromBackup(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	stateDir := filepath.Join(projectRoot, ".stack", "profile")
	targetPath := filepath.Join(projectRoot, "apps", "web", "package.json")
	backupPath := targetPath + ".backup"

	writeJSONFixture(t, targetPath, map[string]any{
		"scripts": map[string]any{
			"dev": "portless stackpanel.stackpanel --app-port 5775 bun run dev",
		},
	})
	writeJSONFixture(t, backupPath, map[string]any{
		"name": "web",
		"private": true,
		"scripts": map[string]any{
			"build:ec2": "vite build",
			"dev":       "vite dev",
		},
	})

	if err := saveState(stateDir, stateFile{
		Version: 1,
		Files: map[string]stateEntry{
			"apps/web/package.json": {
				Type:         "json-ops",
				BackupPath:   backupPath,
				OriginalJSON: map[string]any{},
				ManagedPaths: [][]string{{"scripts", "dev"}},
			},
		},
	}); err != nil {
		t.Fatalf("seed state: %v", err)
	}

	manifest := Manifest{
		Version: 1,
		Files: []Entry{
			{
				Path:  "apps/web/package.json",
				Type:  "json-ops",
				Adopt: "backup",
				Ops: []JSONOp{
					{Op: "set", Path: []string{"scripts", "dev"}, Value: "portless stackpanel.stackpanel --app-port 5775 bun run dev"},
				},
			},
		},
	}

	if _, err := ApplyManifest(projectRoot, stateDir, manifest); err != nil {
		t.Fatalf("apply manifest should succeed: %v", err)
	}

	current := readJSONFixture(t, targetPath)
	if got := current["name"]; got != "web" {
		t.Fatalf("expected name to be repaired from backup, got %#v", current)
	}
	if got := nestedMapValue(t, current, "scripts", "build:ec2"); got != "vite build" {
		t.Fatalf("expected build:ec2 to be repaired from backup, got %#v", current)
	}
}

func TestApplyManifestRepairsManagedOnlyJSONFromGitWhenBackupIsAlsoCorrupted(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	stateDir := filepath.Join(projectRoot, ".stack", "profile")
	targetPath := filepath.Join(projectRoot, "apps", "web", "package.json")
	backupPath := targetPath + ".backup"

	initGitRepoWithCommittedJSON(t, projectRoot, "apps/web/package.json", map[string]any{
		"name": "web",
		"private": true,
		"scripts": map[string]any{
			"build:ec2": "vite build",
			"dev":       "vite dev",
		},
	})

	managedOnly := map[string]any{
		"scripts": map[string]any{
			"dev": "portless stackpanel.stackpanel --app-port 5775 bun run dev",
		},
	}
	writeJSONFixture(t, targetPath, managedOnly)
	writeJSONFixture(t, backupPath, managedOnly)

	if err := saveState(stateDir, stateFile{
		Version: 1,
		Files: map[string]stateEntry{
			"apps/web/package.json": {
				Type:         "json-ops",
				BackupPath:   backupPath,
				OriginalJSON: map[string]any{"scripts": map[string]any{"dev": managedOnly["scripts"].(map[string]any)["dev"]}},
				ManagedPaths: [][]string{{"scripts", "dev"}},
			},
		},
	}); err != nil {
		t.Fatalf("seed state: %v", err)
	}

	manifest := Manifest{
		Version: 1,
		Files: []Entry{
			{
				Path:  "apps/web/package.json",
				Type:  "json-ops",
				Adopt: "backup",
				Ops: []JSONOp{
					{Op: "set", Path: []string{"scripts", "dev"}, Value: "portless stackpanel.stackpanel --app-port 5775 bun run dev"},
				},
			},
		},
	}

	if _, err := ApplyManifest(projectRoot, stateDir, manifest); err != nil {
		t.Fatalf("apply manifest should succeed: %v", err)
	}

	current := readJSONFixture(t, targetPath)
	if got := current["name"]; got != "web" {
		t.Fatalf("expected name to be repaired from git, got %#v", current)
	}
	if got := nestedMapValue(t, current, "scripts", "build:ec2"); got != "vite build" {
		t.Fatalf("expected build:ec2 to be repaired from git, got %#v", current)
	}
}

func TestApplyManifestRestoresOriginalValueWhenManagedJSONPathBecomesStale(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	stateDir := filepath.Join(projectRoot, ".stack", "profile")
	targetPath := filepath.Join(projectRoot, "apps", "web", "package.json")
	original := map[string]any{
		"name": "web",
		"scripts": map[string]any{
			"dev": "vite dev",
		},
	}
	writeJSONFixture(t, targetPath, original)

	first := Manifest{
		Version: 1,
		Files: []Entry{
			{
				Path: "apps/web/package.json",
				Type: "json-ops",
				Ops: []JSONOp{
					{Op: "set", Path: []string{"scripts", "dev"}, Value: "bun run dev"},
				},
			},
		},
	}
	if _, err := ApplyManifest(projectRoot, stateDir, first); err != nil {
		t.Fatalf("first apply should succeed: %v", err)
	}

	second := Manifest{Version: 1}
	if _, err := ApplyManifest(projectRoot, stateDir, second); err != nil {
		t.Fatalf("second apply should succeed: %v", err)
	}

	current := readJSONFixture(t, targetPath)
	if got := nestedMapValue(t, current, "scripts", "dev"); got != "vite dev" {
		t.Fatalf("expected stale managed path to restore original value, got %#v", current)
	}
}

func TestApplyManifestAppendsAndRemovesManagedBlocks(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	stateDir := filepath.Join(projectRoot, ".stack", "profile")
	targetPath := filepath.Join(projectRoot, ".gitignore")
	if err := os.WriteFile(targetPath, []byte("dist\n"), 0644); err != nil {
		t.Fatalf("write original gitignore: %v", err)
	}

	blockContentPath := filepath.Join(projectRoot, "managed-block.txt")
	if err := os.WriteFile(blockContentPath, []byte(".env\nnode_modules\n"), 0644); err != nil {
		t.Fatalf("write block content: %v", err)
	}

	first := Manifest{
		Version: 1,
		Files: []Entry{
			{
				Path:          ".gitignore",
				Type:          "block",
				StorePath:     blockContentPath,
				BlockLabel:    "stackpanel",
				CommentPrefix: "#",
			},
		},
	}
	if _, err := ApplyManifest(projectRoot, stateDir, first); err != nil {
		t.Fatalf("first apply should succeed: %v", err)
	}

	data, err := os.ReadFile(targetPath)
	if err != nil {
		t.Fatalf("read gitignore: %v", err)
	}
	content := string(data)
	for _, want := range []string{
		"dist\n",
		"# ── BEGIN stackpanel ──",
		".env",
		"node_modules",
		"# ── END stackpanel ──",
	} {
		if !strings.Contains(content, want) {
			t.Fatalf("expected gitignore to contain %q, got:\n%s", want, content)
		}
	}

	second := Manifest{Version: 1}
	if _, err := ApplyManifest(projectRoot, stateDir, second); err != nil {
		t.Fatalf("second apply should succeed: %v", err)
	}

	cleaned, err := os.ReadFile(targetPath)
	if err != nil {
		t.Fatalf("read cleaned gitignore: %v", err)
	}
	if got := string(cleaned); got != "dist\n" {
		t.Fatalf("expected stale managed block to be removed, got:\n%s", got)
	}
}

func writeJSONFixture(t *testing.T, path string, value any) {
	t.Helper()

	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}

	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		t.Fatalf("marshal fixture: %v", err)
	}
	data = append(data, '\n')

	if err := os.WriteFile(path, data, 0644); err != nil {
		t.Fatalf("write fixture %s: %v", path, err)
	}
}

func initGitRepoWithCommittedJSON(t *testing.T, root, relPath string, value any) {
	t.Helper()

	runGit(t, root, "init")
	writeJSONFixture(t, filepath.Join(root, relPath), value)
	runGit(t, root, "add", relPath)
	runGit(t, root, "commit", "-m", "seed")
}

func runGit(t *testing.T, root string, args ...string) {
	t.Helper()

	cmd := exec.Command("git", args...)
	cmd.Dir = root
	cmd.Env = append(os.Environ(),
		"GIT_AUTHOR_NAME=Test",
		"GIT_AUTHOR_EMAIL=test@example.com",
		"GIT_COMMITTER_NAME=Test",
		"GIT_COMMITTER_EMAIL=test@example.com",
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v failed: %v\n%s", args, err, output)
	}
}

func readJSONFixture(t *testing.T, path string) map[string]any {
	t.Helper()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal %s: %v", path, err)
	}

	return decoded
}

func nestedMapValue(t *testing.T, root map[string]any, path ...string) any {
	t.Helper()

	var current any = root
	for _, segment := range path {
		object, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current, ok = object[segment]
		if !ok {
			return nil
		}
	}
	return current
}
