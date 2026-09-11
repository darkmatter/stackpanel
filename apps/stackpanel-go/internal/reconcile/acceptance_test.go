package reconcile

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestAcceptanceChecksActualFilesAndCommands(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "main.go"), []byte("package main"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(t.TempDir(), filepath.Join(root, "outside")); err != nil {
		t.Fatal(err)
	}
	ctx := &Context{Ctx: context.Background(), ProjectRoot: root, Build: true, Config: &ProjectConfig{}, CheckScopes: []string{"repo", "build"}, Getenv: func(string) string { return "1" }}
	expected := Expectations{Files: []string{"main.go", "missing.go", "outside"}, Commands: []AcceptanceCommand{
		{ID: "pass", Scope: "build", Dir: ".", Argv: []string{"/bin/sh", "-c", "test -f main.go"}},
		{ID: "fail", Scope: "build", Dir: ".", Argv: []string{"/bin/sh", "-c", "exit 7"}},
	}}
	results := CheckAcceptance(ctx, expected)
	for i, want := range []string{"pass", "fail", "fail", "pass", "fail"} {
		if results[i].Status != want {
			t.Fatalf("check %d: %+v", i, results[i])
		}
	}
	ctx.Build = false
	if got := CheckAcceptance(ctx, expected)[3].Status; got != "skipped" {
		t.Fatal(got)
	}
	for _, path := range []string{"../outside", "/absolute", ""} {
		if err := validateAcceptance(Expectations{Files: []string{path}}); err == nil {
			t.Fatalf("accepted %q", path)
		}
	}
}
