// Package cmd provides CLI commands for the stackpanel tool.
//
// This file contains the main gendocs command for generating MDX documentation
// from Nix options JSON and module README files. The implementation is split
// across multiple files:
//   - gendocs.go (this file): Command definition and main entry point
//   - gendocs_types.go: Type definitions
//   - gendocs_frontmatter.go: Frontmatter and directive parsing
//   - gendocs_options.go: Options reference generation
//   - gendocs_discovery.go: Module discovery (README.md and .nix files)
//   - gendocs_convert.go: MDX conversion utilities
//   - gendocs_modules.go: Module documentation generation
package docgen

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/spf13/cobra"
)

// Directory names for generated documentation
const (
	DirnameReference = "reference"
	DirnameModules   = "modules"
	DirnameDevenv    = "devenv"
)


func Run(optionsPath string, docsDir string, nixModulesDir string) error {
	if nixModulesDir == "" {
		nixModulesDir = ""
	}
	}

	outputDir := fmt.Sprintf("%s/%s", docsDir, DirnameReference)
	modulesOutputDir := fmt.Sprintf("%s/%s", docsDir, DirnameModules)
	devenvDir := fmt.Sprintf("%s/%s", docsDir, DirnameDevenv)

	// Clean up old generated files to prevent stale content
	for _, dir := range []string{outputDir, modulesOutputDir, devenvDir} {
		if err := os.RemoveAll(dir); err != nil {
			fmt.Printf("Warning: failed to clean %s: %v\n", dir, err)
		}
	}

	// Read and parse options JSON
	fmt.Printf("Reading options from: %s\n", optionsPath)
	optionsData, err := os.ReadFile(optionsPath)
	if err != nil {
		return fmt.Errorf("failed to read options file: %w", err)
	}

	var options OptionsJSON
	if err := json.Unmarshal(optionsData, &options); err != nil {
		return fmt.Errorf("failed to parse options JSON: %w", err)
	}

	fmt.Printf("Found %d options\n", len(options))

	// Group options by category
	groups := groupOptions(options)
	categories := make([]string, 0, len(groups))
	for cat := range groups {
		categories = append(categories, cat)
	}
	sort.Strings(categories)

	fmt.Printf("Categories: %s\n", strings.Join(categories, ", "))

	// Ensure output directories exist
	dirs := []string{outputDir, modulesOutputDir, devenvDir}
	if err := mkDirs(dirs...); err != nil {
		return fmt.Errorf("failed to create output directories: %w", err)
	}

	// Generate index
	indexPath := filepath.Join(outputDir, "index.mdx")
	if err := os.WriteFile(indexPath, []byte(generateIndexMdx(categories)), 0644); err != nil {
		return fmt.Errorf("failed to write index: %w", err)
	}
	fmt.Printf("  ✓ %s\n", indexPath)

	// Generate category pages
	for category, opts := range groups {
		categoryPath := filepath.Join(outputDir, category+".mdx")
		if err := os.WriteFile(categoryPath, []byte(generateCategoryMdx(category, opts)), 0644); err != nil {
			return fmt.Errorf("failed to write category %s: %w", category, err)
		}
		fmt.Printf("  ✓ %s (%d options)\n", categoryPath, len(opts))
	}

	fmt.Printf("\nGenerated %d reference files\n", len(categories)+1)

	// Generate module documentation from README files and .nix headers
	if nixModulesDir != "" {
		generatedModules, err := generateModuleDocs(nixModulesDir, modulesOutputDir)
		if err != nil {
			return fmt.Errorf("failed to generate module docs: %w", err)
		}
		if len(generatedModules) > 0 {
			fmt.Printf("\nGenerated %d module doc(s)\n", len(generatedModules))
		}
	}

	return nil
}

func mkDirs(paths ...string) error {
	for _, p := range paths {
		if err := os.MkdirAll(p, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", p, err)
		}
	}
	return nil
}
