// Package github syncs repository collaborator lists and their SSH public keys
// from GitHub. This feeds the secrets management system: collaborator SSH keys
// become AGE recipients for SOPS-encrypted secrets, allowing team members to
// decrypt secrets without sharing a master key.
//
// Requires the `gh` CLI to be installed and authenticated.
package github

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"strings"
)

// Collaborator represents a GitHub repository collaborator
type Collaborator struct {
	Login       string      `json:"login"`
	ID          int         `json:"id"`
	AvatarURL   string      `json:"avatar_url"`
	Type        string      `json:"type"`
	SiteAdmin   bool        `json:"site_admin"`
	RoleName    string      `json:"role_name"`
	Permissions Permissions `json:"permissions"`
}

// Permissions represents the permissions a collaborator has
type Permissions struct {
	Admin    bool `json:"admin"`
	Maintain bool `json:"maintain"`
	Push     bool `json:"push"`
	Triage   bool `json:"triage"`
	Pull     bool `json:"pull"`
}

// User is the enriched collaborator model written to .stack/data/users.nix.
type User struct {
	Login      string   `json:"login"`
	ID         int      `json:"id"`
	RoleName   string   `json:"role_name"`
	IsAdmin    bool     `json:"is_admin"`
	PublicKeys []string `json:"public_keys"`
}

// GetCollaborators fetches repository collaborators using gh CLI.
// Uses --paginate to handle repos with many collaborators.
func GetCollaborators(owner, repo string) ([]Collaborator, error) {
	endpoint := fmt.Sprintf("repos/%s/%s/collaborators", owner, repo)

	cmd := exec.Command("gh", "api", endpoint, "--paginate")
	output, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("gh api failed: %s", string(exitErr.Stderr))
		}
		return nil, fmt.Errorf("failed to run gh: %w", err)
	}

	var collaborators []Collaborator
	if err := json.Unmarshal(output, &collaborators); err != nil {
		return nil, fmt.Errorf("failed to parse collaborators: %w", err)
	}

	return collaborators, nil
}

// FetchPublicKeys fetches public SSH keys from github.com/<user>.keys.
// This is a public, unauthenticated endpoint - no gh CLI needed.
func FetchPublicKeys(username string) ([]string, error) {
	url := fmt.Sprintf("https://github.com/%s.keys", username)

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch keys: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to fetch keys: HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Split by newline and filter empty lines
	lines := strings.Split(strings.TrimSpace(string(body)), "\n")
	var keys []string
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" {
			keys = append(keys, line)
		}
	}

	return keys, nil
}

// SyncCollaborators fetches collaborators and optionally enriches them with SSH
// public keys. Bot accounts (Type != "User") are filtered out. Key fetch failures
// are non-fatal - the user is included without keys.
func SyncCollaborators(owner, repo string, fetchKeys bool) ([]User, error) {
	collaborators, err := GetCollaborators(owner, repo)
	if err != nil {
		return nil, err
	}

	var users []User
	for _, c := range collaborators {
		// Skip non-user types (e.g., bots)
		if c.Type != "User" {
			continue
		}

		user := User{
			Login:    c.Login,
			ID:       c.ID,
			RoleName: c.RoleName,
			IsAdmin:  c.Permissions.Admin,
		}

		if fetchKeys {
			keys, err := FetchPublicKeys(c.Login)
			if err != nil {
				// Log warning but continue
				fmt.Printf("Warning: failed to fetch keys for %s: %v\n", c.Login, err)
			} else {
				user.PublicKeys = keys
			}
		}

		users = append(users, user)
	}

	return users, nil
}

// GetCurrentRepo detects the repository from the current working directory
// using gh CLI. Requires being inside a git repo with a GitHub remote.
func GetCurrentRepo() (owner, repo string, err error) {
	cmd := exec.Command("gh", "repo", "view", "--json", "owner,name")
	output, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return "", "", fmt.Errorf("gh repo view failed: %s", string(exitErr.Stderr))
		}
		return "", "", fmt.Errorf("failed to run gh: %w", err)
	}

	var result struct {
		Owner struct {
			Login string `json:"login"`
		} `json:"owner"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(output, &result); err != nil {
		return "", "", fmt.Errorf("failed to parse repo info: %w", err)
	}

	return result.Owner.Login, result.Name, nil
}
