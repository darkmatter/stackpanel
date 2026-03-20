package codegen

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
)

const manifestModuleName = "manifest"

type manifestModule struct{}

type manifestPayload struct {
	SchemaVersion int          `json:"schemaVersion"`
	ProjectRoot   string       `json:"projectRoot"`
	Modules       []ModuleInfo `json:"modules"`
}

// NewManifestModule returns the built-in manifest generator.
func NewManifestModule() Module {
	return manifestModule{}
}

func (manifestModule) Name() string {
	return manifestModuleName
}

func (manifestModule) Description() string {
	return "Write the registered codegen module manifest"
}

func (manifestModule) Build(ctx context.Context, req BuildRequest) (*BuildOutput, error) {
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
	}

	payload := manifestPayload{
		SchemaVersion: 1,
		ProjectRoot:   req.ProjectRoot,
		Modules:       req.Modules,
	}

	content, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("marshal manifest: %w", err)
	}
	content = append(content, '\n')

	return &BuildOutput{
		Artifacts: []Artifact{
			{
				Path:    filepath.Join(req.ProjectRoot, ".stack", "gen", "codegen", "modules.json"),
				Kind:    ArtifactKindJSON,
				Mode:    0644,
				Content: content,
			},
		},
	}, nil
}
