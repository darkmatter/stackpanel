package codegen

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
)

const manifestModuleName = "manifest"

type manifestModule struct{}

// manifestPayload is written to .stack/gen/codegen/modules.json so external
// tools (studio UI, CLI) can discover which codegen modules are available
// without importing Go code.
type manifestPayload struct {
	SchemaVersion int          `json:"schemaVersion"`
	ProjectRoot   string       `json:"projectRoot"`
	Modules       []ModuleInfo `json:"modules"`
}

// NewManifestModule returns the built-in manifest generator. The manifest
// module records which modules are registered, providing discoverability
// for the studio UI and other tooling.
func NewManifestModule() Module {
	return manifestModule{}
}

func (manifestModule) Name() string {
	return manifestModuleName
}

func (manifestModule) Description() string {
	return "Write the registered codegen module manifest"
}

// Build writes the module registry as JSON. The early context check is a
// courtesy — this module is cheap, but Build is called in a loop where
// earlier modules may have taken a long time.
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
