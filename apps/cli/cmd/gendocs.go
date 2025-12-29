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
package cmd

import (
	"fmt"
	"os"

	"github.com/darkmatter/stackpanel/cli/internal/docgen"
	"github.com/spf13/cobra"
)

// Directory names for generated documentation
const (
	DirnameReference = "reference"
	DirnameModules   = "modules"
	DirnameDevenv    = "devenv"
)

var gendocsCmd = &cobra.Command{
	Use:   "gendocs <options.json> <output-dir> [modules-dir]",
	Short: "Generate MDX documentation from Nix options JSON",
	Long: `Generate MDX documentation from Nix options JSON and module README files.

This command reads the Nix options JSON file and generates MDX documentation
files suitable for use with documentation frameworks like Fumadocs.

If a modules directory is provided, it will also scan for README.md files
in subdirectories and generate corresponding MDX documentation pages.`,
	Args: cobra.RangeArgs(2, 3),
	RunE: runGenDocs,
}

func init() {
	rootCmd.AddCommand(gendocsCmd)
}

func runGenDocs(cmd *cobra.Command, args []string) error {
	optionsPath := args[0]
	docsDir := args[1]
	var nixModulesDir string
	if len(args) > 2 {
		nixModulesDir = args[2]
	}

	docgen.Run(optionsPath, docsDir, nixModulesDir)

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
