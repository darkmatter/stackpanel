package cmd

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/apps/stackpanel-go/pkg/nixeval"
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
  - .stackpanel/config.nix      Main configuration file
  - .stackpanel/data/           Data directory for user-managed files
  - .stackpanel/data/default.nix  Auto-loader for data files
  - .stackpanel/data/users.nix  User definitions

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
		printInfo(fmt.Sprintf("Project root: %s", projectRoot))
	}

	// Evaluate the db module to get init files
	printInfo("Evaluating Nix db module...")

	initFiles, err := getInitFiles(ctx, projectRoot)
	if err != nil {
		return fmt.Errorf("failed to evaluate db module: %w\nHint: Make sure nix/stackpanel/db exists and is valid", err)
	}

	if len(initFiles) == 0 {
		printInfo("No files to create")
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
				printDim(fmt.Sprintf("  skip: %s (exists)", relPath))
				skipped++
			} else if exists && scaffoldForce {
				yellow.Printf("  overwrite: %s\n", relPath)
				created++
			} else {
				green.Printf("  create: %s\n", relPath)
				created++
			}
			continue
		}

		// Skip existing files unless force
		if exists && !scaffoldForce {
			if verbose {
				printDim(fmt.Sprintf("Skipping %s (exists)", relPath))
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
			yellow.Printf("  overwritten: %s\n", relPath)
		} else {
			green.Printf("  created: %s\n", relPath)
		}
		created++
	}

	// Summary
	fmt.Println()
	if scaffoldDryRun {
		printInfo(fmt.Sprintf("Dry run: would create %d files, skip %d", created, skipped))
	} else {
		printSuccess(fmt.Sprintf("Scaffolded %d files (%d skipped)", created, skipped))

		if created > 0 {
			fmt.Println()
			printInfo("Next steps:")
			printDim("  1. Review the generated files in .stackpanel/")
			printDim("  2. Edit .stackpanel/config.nix to configure your project")
			printDim("  3. Add users to .stackpanel/data/users.nix")
			printDim("  4. Run 'nix develop --impure' to enter the dev shell")
		}
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
