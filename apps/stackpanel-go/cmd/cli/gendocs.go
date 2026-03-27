// Package cmd provides CLI commands for the stackpanel tool.
//
// This file contains the gendocs command for generating MDX documentation.
package cmd

import (
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/docgen"
	"github.com/spf13/cobra"
)

// gendocs.go generates MDX documentation from three sources:
//
//  1. Nix options JSON (from nixosOptionsDoc) -> options reference pages
//  2. Module README.md files -> module documentation pages
//  3. Cobra command definitions (rootCmd) -> CLI reference pages
//
// The root command is passed to docgen so it can traverse the full command
// tree at runtime, ensuring CLI docs stay in sync with the actual binary.
var gendocsCmd = &cobra.Command{
	Use:   "gendocs <options.json> <output-dir> [modules-dir]",
	Short: "Generate MDX documentation from Nix options JSON and CLI commands",
	Long: `Generate MDX documentation from Nix options JSON, module README files, and CLI commands.

This command reads the Nix options JSON file and generates MDX documentation
files suitable for use with documentation frameworks like Fumadocs.

Generated documentation includes:
  - Options reference (from Nix options JSON)
  - Module documentation (from README.md files in modules directory)
  - CLI reference (from cobra command definitions)

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

	return docgen.RunWithCLI(optionsPath, docsDir, nixModulesDir, rootCmd)
}
