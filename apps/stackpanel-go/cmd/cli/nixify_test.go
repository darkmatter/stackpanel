package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDetectFileTypeTreatsPackageJSONAsJsonOps(t *testing.T) {
	t.Parallel()

	if got := detectFileType("apps/web/package.json"); got != "json-ops" {
		t.Fatalf("detectFileType(package.json) = %q, want %q", got, "json-ops")
	}
}

func TestNixifyJSONOpsRendersSetOperationsForPackageJSON(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	packageJSONPath := filepath.Join(projectRoot, "apps", "web", "package.json")
	if err := os.MkdirAll(filepath.Dir(packageJSONPath), 0755); err != nil {
		t.Fatalf("mkdir package path: %v", err)
	}
	if err := os.WriteFile(packageJSONPath, []byte(`{
  "name": "web",
  "private": true,
  "scripts": {
    "dev": "bun run dev",
    "build": "bun run build"
  },
  "dependencies": {
    "@gen/env": "workspace:*",
    "react": "^19.0.0"
  }
}
`), 0644); err != nil {
		t.Fatalf("write package.json: %v", err)
	}

	output := captureStdout(t, func() {
		if err := nixifyJSONOps(packageJSONPath, "apps/web/package.json"); err != nil {
			t.Fatalf("nixifyJSONOps should succeed: %v", err)
		}
	})

	for _, want := range []string{
		`stackpanel.files.entries."apps/web/package.json" = {`,
		`type = "json-ops";`,
		`{ op = "set"; path = [ "name" ]; value = "web"; }`,
		`{ op = "set"; path = [ "private" ]; value = true; }`,
		`{ op = "set"; path = [ "scripts" "dev" ]; value = "bun run dev"; }`,
		`{ op = "set"; path = [ "dependencies" "@gen/env" ]; value = "workspace:*"; }`,
	} {
		if !strings.Contains(output, want) {
			t.Fatalf("expected nixifyJSONOps output to contain %q, got:\n%s", want, output)
		}
	}
}
