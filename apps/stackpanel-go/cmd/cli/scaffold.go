package cmd

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/spf13/cobra"
)

var scaffoldCmd = &cobra.Command{
	Use:   "scaffold",
	Short: "Scaffold a new stackpanel project",
	Long: `Scaffold creates the .stackpanel directory structure with boilerplate files.

This command evaluates the Nix db module to get the list of files to create,
then writes them to the appropriate locations. Existing files are NOT overwritten
unless --force is specified.

The scaffolded structure includes:
  - .stackpanel/config.nix       User-editable configuration file
  - .stackpanel/_internal.nix    Internal merging logic (do not edit)
  - .stackpanel/data/            Data directory for user-managed files
  - .stackpanel/data/default.nix Auto-loader for data files
  - .stackpanel/data/users.nix   User definitions

Example:
  stackpanel scaffold                 # Create files in current directory
  stackpanel scaffold --force         # Overwrite existing files
  stackpanel scaffold --dry-run       # Show what would be created`,
	RunE: runScaffold,
}

var (
	scaffoldForce  bool
	scaffoldDryRun bool
)

func init() {
	scaffoldCmd.Flags().BoolVar(&scaffoldForce, "force", false, "Overwrite existing files")
	scaffoldCmd.Flags().BoolVar(&scaffoldDryRun, "dry-run", false, "Show what would be created without writing files")

	rootCmd.AddCommand(scaffoldCmd)
}

func runScaffold(cmd *cobra.Command, args []string) error {
	verbose, _ := cmd.Flags().GetBool("verbose")
	ctx := context.Background()

	// Find project root
	projectRoot, err := findProjectRoot()
	if err != nil {
		projectRoot, err = os.Getwd()
		if err != nil {
			return fmt.Errorf("failed to get current directory: %w", err)
		}
	}

	if verbose {
		output.Info(fmt.Sprintf("Project root: %s", projectRoot))
	}

	// Evaluate the db module to get init files
	output.Info("Evaluating Nix db module...")

	initFiles, err := getInitFiles(ctx, projectRoot)
	if err != nil {
		return fmt.Errorf("failed to evaluate db module: %w\nHint: Make sure nix/stackpanel/db exists and is valid", err)
	}

	if len(initFiles) == 0 {
		output.Info("No files to create")
		return nil
	}

	// Process each file
	created := 0
	skipped := 0

	for relPath, content := range initFiles {
		absPath := filepath.Join(projectRoot, relPath)

		// Check if file exists
		exists := false
		if _, err := os.Stat(absPath); err == nil {
			exists = true
		}

		if scaffoldDryRun {
			if exists && !scaffoldForce {
				output.Dimmed(fmt.Sprintf("  skip: %s (exists)", relPath))
				skipped++
			} else if exists && scaffoldForce {
				output.Yellow.Printf("  overwrite: %s\n", relPath)
				created++
			} else {
				output.Green.Printf("  create: %s\n", relPath)
				created++
			}
			continue
		}

		// Skip existing files unless force
		if exists && !scaffoldForce {
			if verbose {
				output.Dimmed(fmt.Sprintf("Skipping %s (exists)", relPath))
			}
			skipped++
			continue
		}

		// Create directory if needed
		dir := filepath.Dir(absPath)
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", dir, err)
		}

		// Write file
		if err := os.WriteFile(absPath, []byte(content), 0644); err != nil {
			return fmt.Errorf("failed to write %s: %w", relPath, err)
		}

		if exists {
			output.Yellow.Printf("  overwritten: %s\n", relPath)
		} else {
			output.Green.Printf("  created: %s\n", relPath)
		}
		created++
	}

	// Summary
	fmt.Println()
	if scaffoldDryRun {
		output.Info(fmt.Sprintf("Dry run: would create %d files, skip %d", created, skipped))
	} else {
		output.Success(fmt.Sprintf("Scaffolded %d files (%d skipped)", created, skipped))

		// Register this project in the user config so the agent knows about it
		if created > 0 {
			if err := registerScaffoldedProject(projectRoot); err != nil {
				if verbose {
					output.Warning(fmt.Sprintf("Could not register project: %v", err))
				}
			} else if verbose {
				output.Info("Project registered in ~/.config/stackpanel/stackpanel.yaml")
			}
		}

		if created > 0 {
			fmt.Println()
			output.Info("Next steps:")
			output.Dimmed("  1. Review the generated files in .stackpanel/")
			output.Dimmed("  2. Edit .stackpanel/config.nix to configure your project")
			output.Dimmed("  3. Add users to .stackpanel/data/users.nix")
			output.Dimmed("  4. Run 'nix develop --impure' to enter the dev shell")
		}
	}

	return nil
}

// registerScaffoldedProject adds the scaffolded project to the user config.
func registerScaffoldedProject(projectRoot string) error {
	ucm, err := userconfig.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create user config manager: %w", err)
	}

	// Use directory name as project name
	name := filepath.Base(projectRoot)

	_, err = ucm.AddProject(projectRoot, name)
	if err != nil {
		return fmt.Errorf("failed to add project: %w", err)
	}

	return nil
}

// getInitFiles evaluates the db module and returns the map of paths to content
func getInitFiles(ctx context.Context, projectRoot string) (map[string]string, error) {
	// Set STACKPANEL_ROOT for the preset expression
	os.Setenv("STACKPANEL_ROOT", projectRoot)
	defer os.Unsetenv("STACKPANEL_ROOT")

	return nixeval.GetInitFiles(ctx)
}

// findProjectRoot walks up the directory tree to find a project root
// (directory containing flake.nix or .stackpanel)
func findProjectRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}

	for {
		// Check for flake.nix
		if _, err := os.Stat(filepath.Join(dir, "flake.nix")); err == nil {
			return dir, nil
		}
		// Check for .stackpanel
		if _, err := os.Stat(filepath.Join(dir, ".stackpanel")); err == nil {
			return dir, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			// Reached root without finding project
			return "", fmt.Errorf("no project root found (looking for flake.nix or .stackpanel)")
		}
		dir = parent
	}
}
