package codegen

import (
	"context"
	"fmt"
	"path/filepath"
)

// Builder runs registered codegen modules.
type Builder struct {
	registry *Registry
}

// NewBuilder creates a builder for the given registry.
func NewBuilder(registry *Registry) *Builder {
	if registry == nil {
		registry = DefaultRegistry()
	}
	return &Builder{registry: registry}
}

// Plan runs selected modules and returns their raw artifacts without writing them.
func (b *Builder) Plan(ctx context.Context, projectRoot string, moduleNames []string, force, verbose bool) (*BuildPlan, error) {
	if projectRoot == "" {
		return nil, fmt.Errorf("codegen: project root is required")
	}

	absProjectRoot, err := filepath.Abs(projectRoot)
	if err != nil {
		return nil, fmt.Errorf("codegen: resolve project root: %w", err)
	}

	modules, err := b.selectModules(moduleNames)
	if err != nil {
		return nil, err
	}

	request := BuildRequest{
		ProjectRoot: absProjectRoot,
		Force:       force,
		Verbose:     verbose,
		Modules:     b.registry.ModuleInfos(),
	}

	plan := &BuildPlan{ProjectRoot: absProjectRoot}
	for _, module := range modules {
		output, buildErr := module.Build(ctx, request)
		if buildErr != nil {
			return nil, fmt.Errorf("codegen: module %s: %w", module.Name(), buildErr)
		}
		plan.Modules = append(plan.Modules, PlannedModule{
			Module: module.Name(),
			Output: output,
		})
	}

	return plan, nil
}

// Build runs all selected modules and writes their artifacts to the workspace.
func (b *Builder) Build(ctx context.Context, projectRoot string, moduleNames []string, force, verbose bool) (*BuildSummary, error) {
	plan, err := b.Plan(ctx, projectRoot, moduleNames, force, verbose)
	if err != nil {
		return nil, err
	}

	summary := &BuildSummary{ProjectRoot: plan.ProjectRoot}
	for _, module := range plan.Modules {
		result, err := b.writeModuleOutput(module.Module, module.Output, force)
		if err != nil {
			return nil, fmt.Errorf("codegen: module %s: %w", module.Module, err)
		}
		summary.Results = append(summary.Results, result)
	}

	return summary, nil
}

func (b *Builder) writeModuleOutput(moduleName string, output *BuildOutput, force bool) (BuildResult, error) {
	result := BuildResult{Module: moduleName}
	if output == nil {
		return result, nil
	}

	for _, artifact := range output.Artifacts {
		wrote, err := writeArtifact(artifact, force)
		if err != nil {
			return BuildResult{}, err
		}
		if wrote {
			result.Files = append(result.Files, artifact.Path)
		} else {
			result.Skipped = append(result.Skipped, artifact.Path)
		}
	}

	for _, path := range output.Removals {
		removed, err := removeFileIfExists(path)
		if err != nil {
			return BuildResult{}, err
		}
		if removed {
			result.Removed = append(result.Removed, path)
		}
	}

	result.Warnings = append(result.Warnings, output.Warnings...)
	result.Notes = append(result.Notes, output.Notes...)
	return result, nil
}

func (b *Builder) selectModules(moduleNames []string) ([]Module, error) {
	if len(moduleNames) == 0 {
		return b.registry.Modules(), nil
	}

	selected := make([]Module, 0, len(moduleNames))
	for _, name := range moduleNames {
		module, ok := b.registry.Lookup(name)
		if !ok {
			return nil, fmt.Errorf("unknown module %q", name)
		}
		selected = append(selected, module)
	}

	return selected, nil
}
