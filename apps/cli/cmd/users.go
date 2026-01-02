package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/darkmatter/stackpanel/cli/internal/github"
	"github.com/darkmatter/stackpanel/cli/internal/nixgen"
	"github.com/darkmatter/stackpanel/packages/stackpanel-go/state"
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
3. Generates .stackpanel/data/github-collaborators.nix with raw collaborator data
4. Creates .stackpanel/data/users.nix that transforms data to stackpanel.users format

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
	usersSyncCmd.Flags().StringVar(&syncDataDir, "data-dir", "", "Data directory path (default: .stackpanel/data)")
}

func runUsersSync(cmd *cobra.Command, args []string) {
	verbose, _ := cmd.Flags().GetBool("verbose")

	// Determine owner and repo
	owner := syncOwner
	repo := syncRepo

	if owner == "" || repo == "" {
		if verbose {
			printInfo("Detecting current repository...")
		}

		detectedOwner, detectedRepo, err := github.GetCurrentRepo()
		if err != nil {
			printError(fmt.Sprintf("Failed to detect repository: %v", err))
			printDim("Use --owner and --repo flags to specify the repository")
			os.Exit(1)
		}

		if owner == "" {
			owner = detectedOwner
		}
		if repo == "" {
			repo = detectedRepo
		}
	}

	printInfo(fmt.Sprintf("Syncing collaborators from %s/%s...", owner, repo))

	// Fetch collaborators
	users, err := github.SyncCollaborators(owner, repo, !syncNoKeys)
	if err != nil {
		printError(fmt.Sprintf("Failed to fetch collaborators: %v", err))
		os.Exit(1)
	}

	if len(users) == 0 {
		printWarning("No collaborators found")
		return
	}

	printSuccess(fmt.Sprintf("Found %d collaborators", len(users)))

	// Determine data directory
	dataDir := syncDataDir
	if dataDir == "" {
		// Try to get from state file, otherwise use default
		st, err := state.Load("")
		if err == nil && st.Paths.Data != "" {
			dataDir = filepath.Join(st.Paths.Data, "data")
		} else {
			dataDir = ".stackpanel/data"
		}
	}

	// Generate github-collaborators.nix
	collabsPath := filepath.Join(dataDir, "github-collaborators.nix")
	collabsContent := nixgen.GenerateGitHubCollaboratorsNix(users, owner, repo)

	if verbose {
		printInfo(fmt.Sprintf("Writing %s...", collabsPath))
	}

	if err := nixgen.WriteNixFile(collabsPath, collabsContent); err != nil {
		printError(fmt.Sprintf("Failed to write %s: %v", collabsPath, err))
		os.Exit(1)
	}
	printSuccess(fmt.Sprintf("Generated %s", collabsPath))

	// Generate users.nix if it doesn't exist
	usersPath := filepath.Join(dataDir, "users.nix")
	if _, err := os.Stat(usersPath); os.IsNotExist(err) {
		usersContent := nixgen.GenerateUsersNix()

		if verbose {
			printInfo(fmt.Sprintf("Writing %s...", usersPath))
		}

		if err := nixgen.WriteNixFile(usersPath, usersContent); err != nil {
			printError(fmt.Sprintf("Failed to write %s: %v", usersPath, err))
			os.Exit(1)
		}
		printSuccess(fmt.Sprintf("Generated %s", usersPath))
	} else {
		printDim(fmt.Sprintf("Skipped %s (already exists)", usersPath))
	}

	// Print summary
	fmt.Println()
	printInfo("Summary:")
	for _, user := range users {
		keyCount := len(user.PublicKeys)
		role := user.RoleName
		if user.IsAdmin {
			role = role + " (admin)"
		}
		fmt.Printf("  • %s - %s, %d public key(s)\n", user.Login, role, keyCount)
	}

	fmt.Println()
	printDim("To use these users in your stackpanel config:")
	printDim("  stackpanel.users = import ./.stackpanel/data/users.nix;")
}
