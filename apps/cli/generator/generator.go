// Package generator handles file generation for stackpanel.
//
// This package is responsible for writing all generated files based on
// the configuration passed from Nix. It ensures that both generated files
// and the state file are written atomically in the same operation.
package generator

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/cli/config"
)

// Generator handles file generation from config
type Generator struct {
	config  *config.Config
	verbose bool
}

// New creates a new Generator
func New(cfg *config.Config, verbose bool) *Generator {
	return &Generator{
		config:  cfg,
		verbose: verbose,
	}
}

// Run generates all files and writes the state
func (g *Generator) Run() error {
	// Create directories
	if err := g.createDirectories(); err != nil {
		return err
	}

	// Generate IDE files
	if g.config.IDE != nil && g.config.IDE.VSCode != nil && g.config.IDE.VSCode.Enable {
		if err := g.generateVSCodeFiles(); err != nil {
			return err
		}
	}

	// Generate schema files
	if g.config.Schemas != nil && g.config.Schemas.Secrets != nil {
		if err := g.generateSchemaFiles(); err != nil {
			return err
		}
	}

	// Write state file (last, contains the full config)
	if err := g.writeStateFile(); err != nil {
		return err
	}

	return nil
}

// createDirectories ensures all required directories exist
func (g *Generator) createDirectories() error {
	dirs := []string{
		filepath.Join(g.config.ProjectRoot, g.config.Paths.State),
		filepath.Join(g.config.ProjectRoot, g.config.Paths.Gen),
		filepath.Join(g.config.ProjectRoot, g.config.Paths.Gen, "ide", "vscode"),
		filepath.Join(g.config.ProjectRoot, g.config.Paths.Gen, "schemas", "secrets"),
	}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", dir, err)
		}
	}

	return nil
}

// generateVSCodeFiles generates VS Code workspace and related files
func (g *Generator) generateVSCodeFiles() error {
	vscode := g.config.IDE.VSCode
	baseDir := filepath.Join(g.config.ProjectRoot, g.config.Paths.Gen, "ide", "vscode")

	// Generate workspace file
	workspacePath := filepath.Join(baseDir, vscode.WorkspaceName+".code-workspace")
	workspace := g.buildWorkspaceContent()

	workspaceJSON, err := json.MarshalIndent(workspace, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal workspace: %w", err)
	}

	// Remove existing file/symlink before writing
	os.Remove(workspacePath)
	if err := os.WriteFile(workspacePath, workspaceJSON, 0644); err != nil {
		return fmt.Errorf("failed to write workspace file: %w", err)
	}

	if g.verbose {
		fmt.Printf("  Generated %s\n", workspacePath)
	}

	// Generate devshell loader script
	loaderPath := filepath.Join(baseDir, "devshell-loader.sh")
	loaderContent := g.buildDevshellLoader()

	// Remove existing file/symlink before writing
	os.Remove(loaderPath)
	if err := os.WriteFile(loaderPath, []byte(loaderContent), 0755); err != nil {
		return fmt.Errorf("failed to write devshell loader: %w", err)
	}

	if g.verbose {
		fmt.Printf("  Generated %s\n", loaderPath)
	}

	return nil
}

// buildWorkspaceContent creates the VS Code workspace structure
func (g *Generator) buildWorkspaceContent() map[string]interface{} {
	vscode := g.config.IDE.VSCode

	// Build folders list
	folders := []map[string]string{
		{"path": "../../../.."}, // Relative from .stackpanel/gen/ide/vscode to root
	}
	for _, f := range vscode.ExtraFolders {
		folder := map[string]string{"path": f.Path}
		if f.Name != "" {
			folder["name"] = f.Name
		}
		folders = append(folders, folder)
	}

	// Build settings with terminal integration
	settings := make(map[string]interface{})

	// Copy user settings
	for k, v := range vscode.Settings {
		settings[k] = v
	}

	// Add terminal integration
	loaderPath := "${workspaceFolder}/" + g.config.Paths.Gen + "/ide/vscode/devshell-loader.sh"
	settings["terminal.integrated.profiles.osx"] = map[string]interface{}{
		"devenv": map[string]interface{}{
			"path": "/bin/zsh",
			"args": []string{"-c", "source " + loaderPath + " && exec zsh"},
		},
	}
	settings["terminal.integrated.profiles.linux"] = map[string]interface{}{
		"devenv": map[string]interface{}{
			"path": "/bin/bash",
			"args": []string{"-c", "source " + loaderPath + " && exec bash"},
		},
	}
	settings["terminal.integrated.defaultProfile.osx"] = "devenv"
	settings["terminal.integrated.defaultProfile.linux"] = "devenv"

	// Add YAML schema mappings
	schemasDir := "./" + g.config.Paths.Gen + "/schemas/secrets"
	settings["yaml.schemas"] = map[string]interface{}{
		schemasDir + "/config.schema.json":     ".stackpanel/secrets/config.yaml",
		schemasDir + "/users.schema.json":      ".stackpanel/secrets/users.yaml",
		schemasDir + "/app-config.schema.json": ".stackpanel/secrets/apps/*/config.yaml",
		schemasDir + "/schema.schema.json":     ".stackpanel/secrets/apps/*/common.yaml",
		schemasDir + "/env.schema.json": []string{
			".stackpanel/secrets/apps/*/dev.yaml",
			".stackpanel/secrets/apps/*/staging.yaml",
			".stackpanel/secrets/apps/*/prod.yaml",
		},
	}
	settings["yaml.validate"] = true
	settings["yaml.completion"] = true
	settings["yaml.hover"] = true

	// Build extensions list
	extensions := []string{"redhat.vscode-yaml"}
	extensions = append(extensions, vscode.Extensions...)

	return map[string]interface{}{
		"folders":  folders,
		"settings": settings,
		"extensions": map[string]interface{}{
			"recommendations": extensions,
		},
	}
}

// buildDevshellLoader creates the shell script for VS Code terminal integration
func (g *Generator) buildDevshellLoader() string {
	return `#!/usr/bin/env bash
# Devshell loader for VS Code integrated terminal
# This script is sourced by VS Code to enter the devenv shell

# Find the project root (where this script lives relative to)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

cd "$PROJECT_ROOT"

# Check if devenv is available
if command -v devenv &> /dev/null; then
    # Enter devenv shell
    eval "$(devenv print-dev-env)"
elif [ -f .envrc ]; then
    # Fallback to direnv
    if command -v direnv &> /dev/null; then
        eval "$(direnv export bash)"
    fi
fi
`
}

// generateSchemaFiles generates JSON schema files
func (g *Generator) generateSchemaFiles() error {
	secrets := g.config.Schemas.Secrets
	schemasDir := filepath.Join(g.config.ProjectRoot, g.config.Paths.Gen, "schemas", "secrets")

	schemas := map[string]json.RawMessage{
		"config.schema.json":     secrets.Config,
		"users.schema.json":      secrets.Users,
		"app-config.schema.json": secrets.AppConfig,
		"schema.schema.json":     secrets.Schema,
		"env.schema.json":        secrets.Env,
	}

	for name, content := range schemas {
		if content == nil {
			continue
		}

		path := filepath.Join(schemasDir, name)

		// Pretty-print the JSON
		var parsed interface{}
		if err := json.Unmarshal(content, &parsed); err != nil {
			return fmt.Errorf("failed to parse schema %s: %w", name, err)
		}

		formatted, err := json.MarshalIndent(parsed, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to format schema %s: %w", name, err)
		}

		if err := os.WriteFile(path, formatted, 0644); err != nil {
			return fmt.Errorf("failed to write schema %s: %w", name, err)
		}

		if g.verbose {
			fmt.Printf("  Generated %s\n", path)
		}
	}

	return nil
}

// writeStateFile writes the state.json file
func (g *Generator) writeStateFile() error {
	statePath := g.config.StateFile()

	// Create state directory if needed
	stateDir := filepath.Dir(statePath)
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		return fmt.Errorf("failed to create state directory: %w", err)
	}

	// Build state object (subset of config for runtime use)
	state := map[string]interface{}{
		"version":     g.config.Version,
		"projectName": g.config.ProjectName,
		"basePort":    g.config.BasePort,
		"paths":       g.config.Paths,
		"apps":        g.config.Apps,
		"services":    g.config.Services,
		"network":     g.config.Network,
	}

	stateJSON, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal state: %w", err)
	}

	if err := os.WriteFile(statePath, stateJSON, 0644); err != nil {
		return fmt.Errorf("failed to write state file: %w", err)
	}

	if g.verbose {
		fmt.Printf("  Generated %s\n", statePath)
	}

	return nil
}
