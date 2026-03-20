package codegen

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestBuilderBuildsManifestModule(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	builder := NewBuilder(DefaultRegistry())

	summary, err := builder.Build(context.Background(), projectRoot, []string{manifestModuleName}, false, false)
	if err != nil {
		t.Fatalf("build should succeed: %v", err)
	}

	if len(summary.Results) != 1 {
		t.Fatalf("expected 1 build result, got %d", len(summary.Results))
	}

	manifestPath := filepath.Join(projectRoot, ".stack", "gen", "codegen", "modules.json")
	data, err := os.ReadFile(manifestPath)
	if err != nil {
		t.Fatalf("expected manifest to be written: %v", err)
	}

	var payload manifestPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		t.Fatalf("manifest should be valid json: %v", err)
	}

	if payload.SchemaVersion != 1 {
		t.Fatalf("expected schema version 1, got %d", payload.SchemaVersion)
	}
	if len(payload.Modules) != 2 {
		t.Fatalf("expected 2 registered modules, got %#v", payload.Modules)
	}
	if len(summary.Results[0].Files) != 1 || summary.Results[0].Files[0] != manifestPath {
		t.Fatalf("expected manifest path in build result, got %#v", summary.Results[0])
	}
}

func TestBuilderSkipsUnchangedManifest(t *testing.T) {
	t.Parallel()

	projectRoot := t.TempDir()
	builder := NewBuilder(DefaultRegistry())

	if _, err := builder.Build(context.Background(), projectRoot, []string{manifestModuleName}, false, false); err != nil {
		t.Fatalf("initial build should succeed: %v", err)
	}

	summary, err := builder.Build(context.Background(), projectRoot, []string{manifestModuleName}, false, false)
	if err != nil {
		t.Fatalf("second build should succeed: %v", err)
	}

	if len(summary.Results) != 1 {
		t.Fatalf("expected 1 build result, got %d", len(summary.Results))
	}
	if len(summary.Results[0].Skipped) != 1 {
		t.Fatalf("expected unchanged manifest to be skipped, got %#v", summary.Results[0])
	}
}

func TestBuilderRejectsUnknownModule(t *testing.T) {
	t.Parallel()

	builder := NewBuilder(DefaultRegistry())
	_, err := builder.Build(context.Background(), t.TempDir(), []string{"missing"}, false, false)
	if err == nil {
		t.Fatal("expected unknown module error")
	}
}

func TestArtifactsToFilesEntries(t *testing.T) {
	t.Parallel()

	entries, err := ArtifactsToFilesEntries([]Artifact{
		{
			Path:    "foo.txt",
			Kind:    ArtifactKindText,
			Mode:    0644,
			Content: []byte("hello\n"),
		},
		{
			Path:    "bar.json",
			Kind:    ArtifactKindJSON,
			Mode:    0644,
			Content: []byte(`{"b":2,"a":1}`),
		},
	})
	if err != nil {
		t.Fatalf("artifact conversion should succeed: %v", err)
	}

	if entries["foo.txt"].Type != "text" || entries["foo.txt"].Text != "hello\n" {
		t.Fatalf("unexpected text entry: %#v", entries["foo.txt"])
	}
	if entries["bar.json"].Type != "text" || entries["bar.json"].Text == "" {
		t.Fatalf("unexpected json entry: %#v", entries["bar.json"])
	}
}
