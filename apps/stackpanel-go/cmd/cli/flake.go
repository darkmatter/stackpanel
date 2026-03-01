package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
)

var flakeCmd = &cobra.Command{
	Use:   "flake",
	Short: "Manage flake.nix configuration",
	Long:  `Commands for managing flake.nix inputs and configuration.`,
}

var flakeAddInputCmd = &cobra.Command{
	Use:   "add-input <name> <url>",
	Short: "Add a flake input to flake.nix",
	Long: `Add a new flake input to flake.nix using tree-sitter for robust parsing.

This command parses the flake.nix file into a syntax tree, inserts the new
input declaration, and optionally adds a module import to stackpanelImports.

Comments, formatting, and whitespace are fully preserved.

Examples:
  # Add a basic input with nixpkgs follows
  stackpanel flake add-input sops-nix github:Mic92/sops-nix

  # Add without nixpkgs follows
  stackpanel flake add-input process-compose github:Platonic-Systems/process-compose-flake --no-follows

  # Add input and module import
  stackpanel flake add-input my-module github:author/my-module --module-path stackpanelModules.default

  # Dry run — show the modified file without writing
  stackpanel flake add-input my-module github:author/my-module --dry-run`,
	Args: cobra.ExactArgs(2),
	Run:  runFlakeAddInput,
}

var (
	flakeAddInputFollows    bool
	flakeAddInputModulePath string
	flakeAddInputNoLock     bool
	flakeAddInputDryRun     bool
)

func init() {
	flakeAddInputCmd.Flags().BoolVar(&flakeAddInputFollows, "follows", true, "Add inputs.nixpkgs.follows = \"nixpkgs\"")
	flakeAddInputCmd.Flags().StringVar(&flakeAddInputModulePath, "module-path", "", "Also add module import (e.g., stackpanelModules.default)")
	flakeAddInputCmd.Flags().BoolVar(&flakeAddInputNoLock, "no-lock", false, "Skip running nix flake lock")
	flakeAddInputCmd.Flags().BoolVar(&flakeAddInputDryRun, "dry-run", false, "Print modified flake.nix without writing")

	flakeCmd.AddCommand(flakeAddInputCmd)
	rootCmd.AddCommand(flakeCmd)
}

func runFlakeAddInput(cmd *cobra.Command, args []string) {
	inputName := args[0]
	inputURL := args[1]

	// Find project root
	projectRoot, err := findProjectRoot()
	if err != nil {
		output.Error(fmt.Sprintf("Could not find project root: %v", err))
		os.Exit(1)
	}

	flakePath := filepath.Join(projectRoot, "flake.nix")

	// Read flake.nix
	source, err := os.ReadFile(flakePath)
	if err != nil {
		output.Error(fmt.Sprintf("Could not read %s: %v", flakePath, err))
		os.Exit(1)
	}

	// Parse with tree-sitter
	editor, err := flakeedit.NewFlakeEditor(source)
	if err != nil {
		output.Error(fmt.Sprintf("Could not parse flake.nix: %v", err))
		os.Exit(1)
	}
	defer editor.Close()

	// Build import expression if module-path is specified
	importExpr := ""
	if flakeAddInputModulePath != "" {
		importExpr = fmt.Sprintf("inputs.%s.%s", inputName, flakeAddInputModulePath)
	}

	// Perform the edit
	result, err := editor.AddInputAndImport(
		flakeedit.FlakeInput{
			Name:           inputName,
			URL:            inputURL,
			FollowsNixpkgs: flakeAddInputFollows,
		},
		importExpr,
	)
	if err != nil {
		output.Error(fmt.Sprintf("Failed to edit flake.nix: %v", err))
		os.Exit(1)
	}

	// Report what happened
	if result.InputAlreadyExists {
		output.Warning(fmt.Sprintf("Input '%s' already exists in flake.nix", inputName))
	}
	if result.InputAdded {
		output.Success(fmt.Sprintf("Added input: %s = \"%s\"", inputName, inputURL))
	}
	if result.ImportAdded {
		output.Success(fmt.Sprintf("Added import: %s", importExpr))
	}
	if !result.InputAdded && !result.ImportAdded {
		output.Info("No changes needed")
		return
	}

	// Dry run — just print
	if flakeAddInputDryRun {
		output.Info("Dry run — modified flake.nix would be:")
		fmt.Println(string(result.Modified))
		return
	}

	// Write backup
	backupPath := flakePath + ".bak"
	if err := os.WriteFile(backupPath, source, 0o644); err != nil {
		output.Warning(fmt.Sprintf("Could not write backup to %s: %v", backupPath, err))
	}

	// Write modified flake.nix
	if err := os.WriteFile(flakePath, result.Modified, 0o644); err != nil {
		output.Error(fmt.Sprintf("Could not write %s: %v", flakePath, err))
		os.Exit(1)
	}
	output.Success(fmt.Sprintf("Updated %s", flakePath))

	// Lock the new input
	if !flakeAddInputNoLock && result.InputAdded {
		output.Info(fmt.Sprintf("Running: nix flake lock --update-input %s", inputName))
		lockCmd := exec.Command("nix", "flake", "lock", "--update-input", inputName)
		lockCmd.Dir = projectRoot
		lockCmd.Stdout = os.Stdout
		lockCmd.Stderr = os.Stderr
		if err := lockCmd.Run(); err != nil {
			output.Error(fmt.Sprintf("nix flake lock failed: %v", err))
			output.Warning("Restoring flake.nix from backup...")
			if restoreErr := os.WriteFile(flakePath, source, 0o644); restoreErr != nil {
				output.Error(fmt.Sprintf("Failed to restore backup: %v", restoreErr))
			} else {
				output.Info("flake.nix restored from backup")
			}
			os.Exit(1)
		}
		output.Success("Flake input locked successfully")
	}

	// Clean up backup on success
	os.Remove(backupPath)
}
