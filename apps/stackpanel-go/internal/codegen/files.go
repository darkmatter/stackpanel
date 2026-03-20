package codegen

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

func writeArtifact(artifact Artifact, force bool) (bool, error) {
	if artifact.Path == "" {
		return false, fmt.Errorf("codegen: artifact path cannot be empty")
	}

	mode := artifact.Mode
	if mode == 0 {
		mode = 0644
	}

	if err := os.MkdirAll(filepath.Dir(artifact.Path), 0755); err != nil {
		return false, fmt.Errorf("create directory for %s: %w", artifact.Path, err)
	}

	if !force {
		existing, err := os.ReadFile(artifact.Path)
		if err == nil && bytes.Equal(existing, artifact.Content) {
			return false, nil
		}
		if err != nil && !os.IsNotExist(err) {
			return false, fmt.Errorf("read existing file %s: %w", artifact.Path, err)
		}
	}

	if err := os.WriteFile(artifact.Path, artifact.Content, mode); err != nil {
		return false, fmt.Errorf("write %s: %w", artifact.Path, err)
	}

	return true, nil
}

func removeFileIfExists(path string) (bool, error) {
	if path == "" {
		return false, fmt.Errorf("codegen: removal path cannot be empty")
	}

	if err := os.Remove(path); err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, fmt.Errorf("remove %s: %w", path, err)
	}

	return true, nil
}

// ArtifactsToFilesEntries adapts artifacts into stackpanel.files.entries-compatible text entries.
func ArtifactsToFilesEntries(artifacts []Artifact) (map[string]FilesEntry, error) {
	entries := make(map[string]FilesEntry, len(artifacts))
	for _, artifact := range artifacts {
		entry, err := artifactToFilesEntry(artifact)
		if err != nil {
			return nil, err
		}
		entries[artifact.Path] = entry
	}
	return entries, nil
}

// PlanToFilesEntries flattens a build plan into stackpanel.files.entries-compatible data.
func PlanToFilesEntries(plan *BuildPlan) (map[string]FilesEntry, error) {
	if plan == nil {
		return map[string]FilesEntry{}, nil
	}

	entries := make(map[string]FilesEntry)
	for _, module := range plan.Modules {
		if module.Output == nil {
			continue
		}
		for _, artifact := range module.Output.Artifacts {
			entry, err := artifactToFilesEntry(artifact)
			if err != nil {
				return nil, err
			}
			key := artifact.Path
			if plan.ProjectRoot != "" {
				if rel, err := filepath.Rel(plan.ProjectRoot, artifact.Path); err == nil {
					key = rel
				}
			}
			entries[key] = entry
		}
	}

	return entries, nil
}

func artifactToFilesEntry(artifact Artifact) (FilesEntry, error) {
	entry := FilesEntry{Type: "text"}
	if artifact.Mode != 0 {
		entry.Mode = fmt.Sprintf("%04o", artifact.Mode)
	}

	switch artifact.Kind {
	case ArtifactKindText:
		entry.Text = string(artifact.Content)
		return entry, nil
	case ArtifactKindJSON:
		var jsonValue any
		if err := json.Unmarshal(artifact.Content, &jsonValue); err != nil {
			return FilesEntry{}, fmt.Errorf("codegen: parse json artifact %s: %w", artifact.Path, err)
		}
		canonical, err := json.MarshalIndent(jsonValue, "", "  ")
		if err != nil {
			return FilesEntry{}, fmt.Errorf("codegen: marshal json artifact %s: %w", artifact.Path, err)
		}
		entry.Text = string(append(canonical, '\n'))
		return entry, nil
	default:
		return FilesEntry{}, fmt.Errorf("codegen: unsupported artifact kind %q", artifact.Kind)
	}
}
