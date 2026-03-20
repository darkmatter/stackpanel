package codegen

import (
	"context"
	"os"
)

// Module represents a reusable code generation unit.
type Module interface {
	Name() string
	Description() string
	Build(ctx context.Context, req BuildRequest) (*BuildOutput, error)
}

// ModuleInfo is serialized into manifests and summaries.
type ModuleInfo struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

// BuildRequest contains shared context for module builds.
type BuildRequest struct {
	ProjectRoot string
	Force       bool
	Verbose     bool
	Modules     []ModuleInfo
}

// ArtifactKind describes how an artifact should be interpreted.
type ArtifactKind string

const (
	ArtifactKindText ArtifactKind = "text"
	ArtifactKindJSON ArtifactKind = "json"
)

// Artifact is a neutral generated file payload that can be written directly or
// adapted into other backends such as stackpanel.files.entries.
type Artifact struct {
	Path    string
	Kind    ArtifactKind
	Mode    os.FileMode
	Content []byte
}

// BuildOutput is the raw output of a module before any backend writes files.
type BuildOutput struct {
	Artifacts []Artifact
	Removals  []string
	Warnings  []string
	Notes     []string
}

// PlannedModule captures a module's raw artifacts before they are written.
type PlannedModule struct {
	Module string
	Output *BuildOutput
}

// BuildPlan aggregates raw module outputs.
type BuildPlan struct {
	ProjectRoot string
	Modules     []PlannedModule
}

// BuildResult describes the files a module wrote, skipped, or removed.
type BuildResult struct {
	Module   string   `json:"module"`
	Files    []string `json:"files,omitempty"`
	Skipped  []string `json:"skipped,omitempty"`
	Removed  []string `json:"removed,omitempty"`
	Warnings []string `json:"warnings,omitempty"`
	Notes    []string `json:"notes,omitempty"`
}

// BuildSummary aggregates the results of a codegen build.
type BuildSummary struct {
	ProjectRoot string        `json:"projectRoot"`
	Results     []BuildResult `json:"results"`
}

// FilesEntry mirrors the subset of stackpanel.files.entries used by artifact adapters.
type FilesEntry struct {
	Type string `json:"type"`
	Text string `json:"text,omitempty"`
	Mode string `json:"mode,omitempty"`
}
