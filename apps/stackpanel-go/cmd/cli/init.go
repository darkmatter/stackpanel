package cmd

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/spf13/cobra"
)

// Default flake reference for stackpanel
// Users can override with --flake flag or STACKPANEL_FLAKE env var
const defaultStackpanelFlake = "github:darkmatter/stackpanel"

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize a new stackpanel project",
	Long: `Initialize creates the .stackpanel directory structure with boilerplate files.

This command evaluates the stackpanel flake to get the list of files to create,
then writes them to the appropriate locations. Existing files are NOT overwritten
unless --force is specified.

The initialized structure includes:
  - .stackpanel/config.nix       User-editable configuration file
  - .stackpanel/_internal.nix    Internal merging logic (do not edit)
  - .stackpanel/data.nix         Agent-editable data file
  - .stackpanel/.gitignore       Gitignore for state and local config

Example:
  stackpanel init                              # Create files in current directory
  stackpanel init --force                      # Overwrite existing files
  stackpanel init --dry-run                    # Show what would be created
  stackpanel init --flake path:/path/to/sp     # Use local stackpanel for development`,
	RunE: runInit,
}

var (
	initForce  bool
	initDryRun bool
	initFlake  string
)

func init() {
	initCmd.Flags().BoolVar(&initForce, "force", false, "Overwrite existing files")
	initCmd.Flags().BoolVar(&initDryRun, "dry-run", false, "Show what would be created without writing files")
	initCmd.Flags().StringVar(&initFlake, "flake", "", "Stackpanel flake reference (default: github:darkmatter/stackpanel)")

	rootCmd.AddCommand(initCmd)
}

func runInit(cmd *cobra.Command, args []string) error {
	verbose, _ := cmd.Flags().GetBool("verbose")
	ctx := context.Background()

	// Determine target directory (where to create .stackpanel/)
	targetDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("failed to get current directory: %w", err)
	}

	if verbose {
		output.Info(fmt.Sprintf("Target directory: %s", targetDir))
	}

	// Determine which flake to use for initFiles
	flakeRef := initFlake
	if flakeRef == "" {
		flakeRef = os.Getenv("STACKPANEL_FLAKE")
	}
	if flakeRef == "" {
		flakeRef = defaultStackpanelFlake
	}

	if verbose {
		output.Info(fmt.Sprintf("Using stackpanel flake: %s", flakeRef))
	}

	// Evaluate initFiles from the stackpanel flake
	output.Info("Fetching templates from stackpanel...")

	initFiles, err := getInitFilesFromFlake(ctx, flakeRef)
	if err != nil {
		return fmt.Errorf("failed to get init files from flake: %w\nHint: Check that the flake reference is valid", err)
	}

	if len(initFiles) == 0 {
		output.Info("No files to create")
		return nil
	}

	// Process each file
	created := 0
	skipped := 0

	for relPath, content := range initFiles {
		absPath := filepath.Join(targetDir, relPath)

		// Check if file exists
		exists := false
		if _, err := os.Stat(absPath); err == nil {
			exists = true
		}

		if initDryRun {
			if exists && !initForce {
				output.Dimmed(fmt.Sprintf("  skip: %s (exists)", relPath))
				skipped++
			} else if exists && initForce {
				output.Yellow.Printf("  overwrite: %s\n", relPath)
				created++
			} else {
				output.Green.Printf("  create: %s\n", relPath)
				created++
			}
			continue
		}

		// Skip existing files unless force
		if exists && !initForce {
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
	if initDryRun {
		output.Info(fmt.Sprintf("Dry run: would create %d files, skip %d", created, skipped))
	} else {
		output.Success(fmt.Sprintf("Initialized %d files (%d skipped)", created, skipped))

		// Register this project in the user config so the agent knows about it
		if created > 0 {
			if err := registerInitProject(targetDir); err != nil {
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
			output.Dimmed("  3. Create a flake.nix that imports stackpanel (or use 'nix flake init -t github:darkmatter/stackpanel')")
			output.Dimmed("  4. Run 'nix develop --impure' to enter the dev shell")
		}
	}

	return nil
}

// registerInitProject adds the initialized project to the user config.
func registerInitProject(projectRoot string) error {
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

// getInitFilesFromFlake evaluates initFiles from a stackpanel flake reference.
// The flakeRef can be:
//   - "github:darkmatter/stackpanel" (default, from GitHub)
//   - "path:/local/path/to/stackpanel" (for local development)
//   - "git+file:///local/path/to/stackpanel" (faster local, uses git filtering)
//   - Any valid Nix flake reference
//
// Note: "path:" references are automatically converted to "git+file://" for better
// performance (uses git to filter files instead of copying everything).
func getInitFilesFromFlake(ctx context.Context, flakeRef string) (map[string]string, error) {
	// Convert path: to git+file:// for better performance
	// path: copies the entire directory, git+file:// uses git to filter
	if strings.HasPrefix(flakeRef, "path:") {
		localPath := strings.TrimPrefix(flakeRef, "path:")
		flakeRef = "git+file://" + localPath
	}

	return nixeval.GetInitFilesFromFlake(ctx, flakeRef)
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
