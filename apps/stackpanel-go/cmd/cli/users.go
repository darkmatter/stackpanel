// users.go syncs GitHub collaborators into Nix data files for user management.
//
// Two files are generated:
//   - github-collaborators.nix: auto-generated raw collaborator data (overwritten on each sync)
//   - users.nix: one-time scaffold that imports collaborators and maps to stackpanel.users format
//     (only created if missing, so manual customisations are preserved)
package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/github"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixgen"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/envvars"
	"github.com/spf13/cobra"
)

var usersCmd = &cobra.Command{
	Use:     "users",
	Aliases: []string{"user", "u"},
	Short:   "Manage project users",
	Long: `Manage users who have access to the project.

Users can be synced from GitHub collaborators and their public keys
are automatically fetched for use with secrets encryption.`,
}

var usersSyncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Sync users from GitHub collaborators",
	Long: `Sync users from GitHub repository collaborators.

This command:
1. Fetches collaborators from the GitHub repository using gh CLI
2. Fetches public SSH keys for each collaborator from github.com/<user>.keys
3. Generates .stack/data/github-collaborators.nix with raw collaborator data
4. Creates .stack/data/users.nix that transforms data to stackpanel.users format

The github-collaborators.nix file is auto-generated and should not be edited.
Edit users.nix to customize permissions or add non-GitHub users.

Requires: gh CLI to be installed and authenticated.`,
	Run: runUsersSync,
}

var (
	syncOwner   string
	syncRepo    string
	syncNoKeys  bool
	syncDataDir string
)

func init() {
	usersCmd.AddCommand(usersSyncCmd)
	rootCmd.AddCommand(usersCmd)

	// Flags for sync command
	usersSyncCmd.Flags().StringVar(&syncOwner, "owner", "", "GitHub repository owner (default: current repo)")
	usersSyncCmd.Flags().StringVar(&syncRepo, "repo", "", "GitHub repository name (default: current repo)")
	usersSyncCmd.Flags().BoolVar(&syncNoKeys, "no-keys", false, "Skip fetching public keys")
	usersSyncCmd.Flags().StringVar(&syncDataDir, "data-dir", "", "Data directory path (default: .stack/data)")
}

func runUsersSync(cmd *cobra.Command, args []string) {
	verbose, _ := cmd.Flags().GetBool("verbose")

	// Determine owner and repo
	owner := syncOwner
	repo := syncRepo

	if owner == "" || repo == "" {
		if verbose {
			output.Info("Detecting current repository...")
		}

		detectedOwner, detectedRepo, err := github.GetCurrentRepo()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to detect repository: %v", err))
			output.Dimmed("Use --owner and --repo flags to specify the repository")
			os.Exit(1)
		}

		if owner == "" {
			owner = detectedOwner
		}
		if repo == "" {
			repo = detectedRepo
		}
	}

	output.Info(fmt.Sprintf("Syncing collaborators from %s/%s...", owner, repo))

	// Fetch collaborators
	users, err := github.SyncCollaborators(owner, repo, !syncNoKeys)
	if err != nil {
		output.Error(fmt.Sprintf("Failed to fetch collaborators: %v", err))
		os.Exit(1)
	}

	if len(users) == 0 {
		output.Warning("No collaborators found")
		return
	}

	output.Success(fmt.Sprintf("Found %d collaborators", len(users)))

	// Determine data directory
	dataDir := syncDataDir
	if dataDir == "" {
		// Try env var first
		if dir := envvars.StackpanelDataDir.Get(); dir != "" {
			dataDir = dir
		} else {
			// Try to get from nix config
			cfg, err := nixconfig.Load()
			if err == nil && cfg.Paths.Data != "" {
				dataDir = filepath.Join(cfg.Paths.Data, "data")
			} else {
				// Default
				dataDir = ".stack/data"
			}
		}
	}

	// The data directory defaults to .stack/data but respects the configured
	// data path. We always write into an "external" subdirectory to keep
	// auto-generated files separate from user-authored data files.
	if !strings.HasSuffix(dataDir, "external") {
		dataDir = filepath.Join(dataDir, "external")
	}

	// Generate github-collaborators.nix
	collabsPath := filepath.Join(dataDir, "github-collaborators.nix")
	collabsContent := nixgen.GenerateGitHubCollaboratorsNix(users, owner, repo)

	if verbose {
		output.Info(fmt.Sprintf("Writing %s...", collabsPath))
	}

	if err := nixgen.WriteNixFile(collabsPath, collabsContent); err != nil {
		output.Error(fmt.Sprintf("Failed to write %s: %v", collabsPath, err))
		os.Exit(1)
	}
	output.Success(fmt.Sprintf("Generated %s", collabsPath))

	// Generate users.nix if it doesn't exist
	usersPath := filepath.Join(dataDir, "users.nix")
	if _, err := os.Stat(usersPath); os.IsNotExist(err) {
		usersContent := nixgen.GenerateUsersNix()

		if verbose {
			output.Info(fmt.Sprintf("Writing %s...", usersPath))
		}

		if err := nixgen.WriteNixFile(usersPath, usersContent); err != nil {
			output.Error(fmt.Sprintf("Failed to write %s: %v", usersPath, err))
			os.Exit(1)
		}
		output.Success(fmt.Sprintf("Generated %s", usersPath))
	} else {
		output.Dimmed(fmt.Sprintf("Skipped %s (already exists)", usersPath))
	}

	// Print summary
	fmt.Println()
	output.Info("Summary:")
	for _, user := range users {
		keyCount := len(user.PublicKeys)
		role := user.RoleName
		if user.IsAdmin {
			role = role + " (admin)"
		}
		fmt.Printf("  • %s - %s, %d public key(s)\n", user.Login, role, keyCount)
	}

	fmt.Println()
	output.Dimmed("To use these users in your stackpanel config:")
	output.Dimmed("  stackpanel.users = import ./.stack/data/users.nix;")
}
