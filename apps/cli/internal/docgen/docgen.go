// Package docgen provides documentation generation utilities for stackpanel.
//
// This package generates MDX documentation from multiple sources:
//   - Nix options JSON (reference documentation)
//   - Module README files (internal documentation)
//   - Cobra CLI commands (CLI reference)
//
// The implementation is split across multiple files:
//   - docgen.go (this file): Main entry points and orchestration
//   - types.go: Type definitions
//   - frontmatter.go: Frontmatter and directive parsing
//   - options.go: Options reference generation
//   - discovery.go: Module discovery (README.md and .nix files)
//   - convert.go: MDX conversion utilities
//   - modules.go: Module documentation generation
//   - cli.go: CLI documentation generation
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

type Topic string

// Directory names for generated documentation
const (
	// Docs generated from evaluating Nix options => /core/reference
	DirnameReference Topic = "reference"
	// Docs generated from READMEs => /internal
	DirnameModules Topic = "internal"
	// Docs gnerate from CLI readme => cli
	DirnameCLI Topic = "cli"
)

func mkpath(topic Topic, basedir string) string {
	return fmt.Sprintf("%s/%s", basedir, topic)
}

// Run generates documentation without CLI command docs.
// This is the legacy entry point for backward compatibility.
// Use RunWithCLI to also generate CLI documentation.
func Run(optionsPath string, docsDir string, nixModulesDir string) error {
	return RunWithCLI(optionsPath, docsDir, nixModulesDir, nil)
}

// RunWithCLI generates all documentation including CLI command docs.
// If rootCmd is nil, CLI docs generation is skipped.
func RunWithCLI(optionsPath string, docsDir string, nixModulesDir string, rootCmd *cobra.Command) error {
	dirs := map[Topic]string{
		"reference": mkpath(DirnameReference, docsDir),
		"internal":  mkpath(DirnameModules, docsDir),
		"cli":       mkpath(DirnameCLI, docsDir),
	}

	// Clean up old generated files to prevent stale content
	// Preserve meta.json files as they are manually maintained
	for _, dir := range []string{dirs["reference"], dirs["internal"], dirs["cli"]} {
		if err := cleanDirectory(dir); err != nil {
			fmt.Printf("Warning: failed to clean %s: %v\n", dir, err)
		}
	}

	// generates docs/reference
	if err := generateOptionsDocs(optionsPath, dirs["reference"], dirs["internal"]); err != nil {
		return fmt.Errorf("failed to generate options docs: %w", err)
	}

	// generates docs/internal
	if nixModulesDir != "" {
		generatedModules, err := generateModuleDocs(nixModulesDir, dirs["internal"])
		if err != nil {
			return fmt.Errorf("failed to generate module docs: %w", err)
		}
		if len(generatedModules) > 0 {
			fmt.Printf("\nGenerated %d module doc(s)\n", len(generatedModules))
		}
	}

	// generates docs/cli
	if rootCmd != nil {
		fmt.Println("\nGenerating CLI documentation...")
		if err := GenerateCLIDocs(rootCmd, dirs["cli"]); err != nil {
			return fmt.Errorf("failed to generate CLI docs: %w", err)
		}
	}

	return nil
}

func generateOptionsDocs(optionsPath string, outputDir string, modulesOutputDir string) error {
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
	dirs := []string{outputDir, modulesOutputDir}
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

// cleanDirectory removes all files and subdirectories except meta.json files
func cleanDirectory(dir string) error {
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}

	for _, entry := range entries {
		path := filepath.Join(dir, entry.Name())

		if entry.IsDir() {
			// Recursively clean subdirectories
			if err := cleanDirectory(path); err != nil {
				return err
			}
			// Remove the subdirectory if it's empty
			subEntries, err := os.ReadDir(path)
			if err == nil && len(subEntries) == 0 {
				os.Remove(path)
			}
		} else if entry.Name() != "meta.json" {
			// Remove all files except meta.json
			if err := os.Remove(path); err != nil {
				return err
			}
		}
	}

	return nil
}
