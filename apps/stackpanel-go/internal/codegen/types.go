// Package codegen generates type-safe environment variable access code from
// SOPS-encrypted secret schemas. It reads Nix-evaluated manifests from
// .stack/gen/codegen/ and produces encrypted payloads and TypeScript modules
// under packages/gen/env/src/. Generated files are checked in so IDEs
// provide type information without requiring an active devshell.
//
// The pipeline is: Nix schema -> env-manifest.json -> codegen -> SOPS-encrypted
// payloads + TS modules -> runtime decryption at app startup.
package codegen

import (
	"context"
	"os"
)

// Module represents a reusable code generation unit. Each module independently
// produces artifacts from a BuildRequest; the Builder orchestrates writing them.
type Module interface {
	Name() string
	Description() string
	Build(ctx context.Context, req BuildRequest) (*BuildOutput, error)
}

// ModuleInfo is the serializable subset of Module metadata, used in manifests
// and passed to modules via BuildRequest so they can discover sibling modules.
type ModuleInfo struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

// BuildRequest contains shared context for module builds. Modules is populated
// from the registry so each module can see what other modules are registered
// (used by the manifest module to record the full module list).
type BuildRequest struct {
	ProjectRoot string
	Force       bool
	Verbose     bool
	Modules     []ModuleInfo
}

// ArtifactKind controls how an artifact is serialized when adapted to other
// backends (e.g., JSON artifacts get canonicalized via marshal/unmarshal).
type ArtifactKind string

const (
	ArtifactKindText ArtifactKind = "text"
	ArtifactKindJSON ArtifactKind = "json"
)

// Artifact is a generated file payload decoupled from any specific output
// backend. It can be written to disk directly by the Builder, or adapted into
// stackpanel.files.entries for the Nix file manager via ArtifactsToFilesEntries.
type Artifact struct {
	Path    string
	Kind    ArtifactKind
	Mode    os.FileMode
	Content []byte
}

// BuildOutput is the raw output of a module before any backend writes files.
// Removals lists paths that should be deleted (e.g., stale artifacts from
// apps/environments that were removed from the manifest).
type BuildOutput struct {
	Artifacts []Artifact
	Removals  []string
	Warnings  []string
	Notes     []string
}

// PlannedModule pairs a module name with its raw build output, before the
// Builder has written anything to disk. Used by Plan for dry-run inspection.
type PlannedModule struct {
	Module string
	Output *BuildOutput
}

// BuildPlan aggregates raw module outputs from a Plan call, allowing callers
// to inspect or adapt artifacts before committing writes (see PlanToFilesEntries).
type BuildPlan struct {
	ProjectRoot string
	Modules     []PlannedModule
}

// BuildResult describes the files a module wrote, skipped, or removed.
// Skipped files had identical content and didn't need rewriting.
type BuildResult struct {
	Module   string   `json:"module"`
	Files    []string `json:"files,omitempty"`
	Skipped  []string `json:"skipped,omitempty"`
	Removed  []string `json:"removed,omitempty"`
	Warnings []string `json:"warnings,omitempty"`
	Notes    []string `json:"notes,omitempty"`
}

// BuildSummary aggregates the results of a codegen build across all modules.
type BuildSummary struct {
	ProjectRoot string        `json:"projectRoot"`
	Results     []BuildResult `json:"results"`
}

// FilesEntry mirrors the subset of stackpanel.files.entries used by the Nix
// file manager. This allows codegen artifacts to be fed back into the Nix
// plane's file generation system instead of being written directly to disk.
type FilesEntry struct {
	Type string `json:"type"`
	Text string `json:"text,omitempty"`
	Mode string `json:"mode,omitempty"`
}
