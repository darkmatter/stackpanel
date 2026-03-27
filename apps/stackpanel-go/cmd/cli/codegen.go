// codegen.go implements host-side code generation commands.
//
// Codegen runs outside of Nix evaluation/derivation builds because some
// generators need access to the host filesystem, git state, or ambient
// environment that isn't available inside the Nix sandbox.
package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/codegen"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/spf13/cobra"
)

var (
	codegenProjectRoot string
	codegenForce       bool
	codegenExportPath  string
)

var codegenCmd = &cobra.Command{
	Use:   "codegen",
	Short: "Build generated project artifacts",
	Long: `Build generated project artifacts using reusable codegen modules.

This command is the entrypoint for host-side code generation that should not run
inside Nix evaluation or derivation builds.

Examples:
  stackpanel codegen build
  stackpanel codegen build manifest
  stackpanel codegen build --project-root /path/to/project`,
}

var codegenBuildCmd = &cobra.Command{
	Use:   "build [module...]",
	Short: "Build registered codegen modules",
	Long: `Build one or more registered codegen modules.

Without arguments, all registered modules are built in sorted order.`,
	RunE: runCodegenBuild,
}

var codegenExportFilesEntriesCmd = &cobra.Command{
	Use:   "export-files-entries [module...]",
	Short: "Export module artifacts as stackpanel.files.entries JSON",
	Long: `Export one or more codegen modules as stackpanel.files.entries-compatible JSON.

This is useful when a host-side generator should also be consumable by Nix-backed
file writers or other tooling that understands stackpanel.files.entries.`,
	RunE: runCodegenExportFilesEntries,
}

func init() {
	codegenBuildCmd.Flags().StringVar(&codegenProjectRoot, "project-root", "", "Project root (defaults to the current stackpanel project)")
	codegenBuildCmd.Flags().BoolVar(&codegenForce, "force", false, "Rewrite generated files even when contents are unchanged")
	codegenExportFilesEntriesCmd.Flags().StringVar(&codegenProjectRoot, "project-root", "", "Project root (defaults to the current stackpanel project)")
	codegenExportFilesEntriesCmd.Flags().StringVar(&codegenExportPath, "output", "", "Optional output path for the exported JSON (prints to stdout if omitted)")

	codegenCmd.AddCommand(codegenBuildCmd)
	codegenCmd.AddCommand(codegenExportFilesEntriesCmd)
	rootCmd.AddCommand(codegenCmd)
}

func runCodegenBuild(cmd *cobra.Command, args []string) error {
	projectRoot, err := resolveCodegenProjectRoot()
	if err != nil {
		return err
	}

	verbose, _ := cmd.Flags().GetBool("verbose")
	summary, err := buildCodegenModules(cmd.Context(), projectRoot, args, codegenForce, verbose)
	if err != nil {
		return err
	}

	printCodegenSummary(summary, verbose)
	output.Success(fmt.Sprintf("Built %d codegen module(s)", len(summary.Results)))
	return nil
}

// runCodegenExportFilesEntries bridges host-side codegen with the Nix file
// writer system. It plans (but doesn't execute) codegen modules, then
// serialises their output as stackpanel.files.entries JSON — allowing Nix
// modules or other tooling to consume host-generated artifacts declaratively.
func runCodegenExportFilesEntries(cmd *cobra.Command, args []string) error {
	projectRoot, err := resolveCodegenProjectRoot()
	if err != nil {
		return err
	}

	verbose, _ := cmd.Flags().GetBool("verbose")
	builder := codegen.NewBuilder(codegen.DefaultRegistry())
	plan, err := builder.Plan(cmd.Context(), projectRoot, args, false, verbose)
	if err != nil {
		return err
	}

	entries, err := codegen.PlanToFilesEntries(plan)
	if err != nil {
		return err
	}

	content, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal files entries: %w", err)
	}
	content = append(content, '\n')

	if codegenExportPath == "" {
		_, err = cmd.OutOrStdout().Write(content)
		return err
	}

	outputPath := codegenExportPath
	if !filepath.IsAbs(outputPath) {
		outputPath = filepath.Join(projectRoot, outputPath)
	}
	if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
		return fmt.Errorf("create export directory: %w", err)
	}
	if err := os.WriteFile(outputPath, content, 0644); err != nil {
		return fmt.Errorf("write files entries export: %w", err)
	}

	output.Success(fmt.Sprintf("Exported stackpanel.files.entries to %s", relativeDisplayPath(projectRoot, outputPath)))
	return nil
}

func buildCodegenModules(ctx context.Context, projectRoot string, moduleNames []string, force, verbose bool) (*codegen.BuildSummary, error) {
	builder := codegen.NewBuilder(codegen.DefaultRegistry())
	return builder.Build(ctx, projectRoot, moduleNames, force, verbose)
}

func resolveCodegenProjectRoot() (string, error) {
	projectRoot := codegenProjectRoot
	if projectRoot != "" {
		return projectRoot, nil
	}
	return findProjectRoot()
}

func printCodegenSummary(summary *codegen.BuildSummary, verbose bool) {
	for _, result := range summary.Results {
		if len(result.Files) > 0 || len(result.Removed) > 0 {
			output.Info(fmt.Sprintf("Built codegen module %s", result.Module))
			for _, file := range result.Files {
				output.Dimmed(fmt.Sprintf("  wrote %s", relativeDisplayPath(summary.ProjectRoot, file)))
			}
			for _, path := range result.Removed {
				output.Dimmed(fmt.Sprintf("  removed %s", relativeDisplayPath(summary.ProjectRoot, path)))
			}
			for _, warning := range result.Warnings {
				output.Warning(warning)
			}
			for _, note := range result.Notes {
				output.Dimmed(fmt.Sprintf("  note: %s", note))
			}
			continue
		}

		output.Dimmed(fmt.Sprintf("  skipped %s", result.Module))
		for _, warning := range result.Warnings {
			output.Warning(warning)
		}
		if verbose {
			for _, file := range result.Skipped {
				output.Dimmed(fmt.Sprintf("    %s", relativeDisplayPath(summary.ProjectRoot, file)))
			}
			for _, note := range result.Notes {
				output.Dimmed(fmt.Sprintf("    %s", note))
			}
		}
	}
}

// relativeDisplayPath converts an absolute path to a project-relative one
// for cleaner CLI output. Falls back to the absolute path on error.
func relativeDisplayPath(projectRoot, path string) string {
	rel, err := filepath.Rel(projectRoot, path)
	if err != nil {
		return path
	}
	return rel
}
