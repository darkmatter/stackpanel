// agenix.go implements the secrets management HTTP API for the Stackpanel agent.
//
// Despite the "agenix" name (historical), this file handles the unified secrets
// system which uses SOPS-encrypted YAML files grouped by environment (dev, staging,
// prod). It also manages AGE identity configuration, KMS integration, and the
// SOPS age key discovery/validation pipeline.
//
// Secret storage layout:
//
//	.stack/secrets/vars/dev.sops.yaml      -- per-environment SOPS files
//	.stack/secrets/.sops.yaml              -- generated SOPS config (creation rules)
//	.stack/state/age-identity              -- pointer to AGE private key
//	.stack/state/kms-config.json           -- optional AWS KMS config
//	.stack/data/variables.nix              -- secret metadata registry
package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"

	nixser "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// AgenixSecretRequest represents a request to write an age-encrypted secret
type AgenixSecretRequest struct {
	// ID is the unique identifier for the secret (used as filename: <id>.age)
	ID string `json:"id"`

	// Key is the environment variable name (e.g., DATABASE_URL)
	Key string `json:"key"`

	// Value is the plaintext secret value to encrypt
	Value string `json:"value"`

	// Description is an optional description of the secret
	Description string `json:"description,omitempty"`

	// Environments is the list of environments this secret is available in
	// If empty, defaults to all environments
	Environments []string `json:"environments,omitempty"`
}

// AgenixSecretResponse is the response after writing a secret
type AgenixSecretResponse struct {
	ID       string `json:"id"`
	Path     string `json:"path"`
	AgePath  string `json:"agePath"`
	KeyCount int    `json:"keyCount"`
}

// AgenixDecryptRequest represents a request to decrypt an age-encrypted secret
type AgenixDecryptRequest struct {
	// ID is the secret identifier (matches filename without .age extension)
	ID string `json:"id"`

	// IdentityPath is the path to the AGE private key file
	// If empty, tries default locations: ~/.config/age/key.txt, ~/.age/key.txt
	IdentityPath string `json:"identityPath,omitempty"`
}

// AgenixDecryptResponse is the response after decrypting a secret
type AgenixDecryptResponse struct {
	ID    string `json:"id"`
	Value string `json:"value"`
}

// groupFromID extracts the environment/group prefix from a variable ID path.
// "/dev/postgres-url" → "dev", "/prod/api-key" → "prod"
// Falls back to "dev" if the ID has no path structure.
func groupFromID(id string) string {
	trimmed := strings.Trim(strings.TrimSpace(id), "/")
	parts := strings.SplitN(trimmed, "/", 2)
	if len(parts) > 0 && parts[0] != "" {
		return parts[0]
	}
	return "dev"
}

// isFlatSecretVariableID returns true if the ID represents an actual secret
// (not a plain variable or computed value). "var" and "computed" groups are
// non-encrypted and handled separately.
func isFlatSecretVariableID(id string) bool {
	group := groupFromID(id)
	return group != "" && group != "var" && group != "computed"
}

// variableNameFromID returns the last path segment: "/dev/postgres-url" → "postgres-url"
func variableNameFromID(id string) string {
	trimmed := strings.Trim(strings.TrimSpace(id), "/")
	if trimmed == "" {
		return ""
	}
	parts := strings.Split(trimmed, "/")
	return parts[len(parts)-1]
}

// secretFileStemFromID converts a variable name into a safe filename stem.
func secretFileStemFromID(id string) string {
	name := variableNameFromID(id)
	name = strings.ReplaceAll(name, "/", "-")
	name = strings.ReplaceAll(name, `\`, "-")
	name = strings.ReplaceAll(name, " ", "-")
	return name
}

// secretYAMLKeyFromID converts a variable name to a YAML-safe key using underscores.
func secretYAMLKeyFromID(id string) string {
	name := variableNameFromID(id)
	name = strings.ReplaceAll(name, "-", "_")
	name = strings.ReplaceAll(name, ".", "_")
	name = strings.ReplaceAll(name, "/", "_")
	name = strings.ReplaceAll(name, `\`, "_")
	name = strings.ReplaceAll(name, " ", "_")
	return name
}

// getFlatSecretFilePath resolves the SOPS file path and YAML key for a variable ID.
// Nix-computed metadata takes precedence (allowing overrides), falling back to
// convention-based grouping: /dev/postgres-url → vars/dev.sops.yaml, key: postgres_url
func (s *Server) getFlatSecretFilePath(id string) (string, string, error) {
	// Check Nix-computed metadata first (allows overrides)
	meta, ok, err := s.getVariableSecretMeta(id)
	if err == nil && ok && strings.TrimSpace(meta.File) != "" {
		return filepath.Join(s.config.ProjectRoot, ".stack", "secrets", meta.File), meta.YamlKey, nil
	}
	// Default: path-based grouping — /dev/postgres-url → vars/dev.sops.yaml, key: postgres_url
	group := groupFromID(id)
	yamlKey := secretYAMLKeyFromID(id)
	return filepath.Join(s.config.ProjectRoot, ".stack", "secrets", "vars", group+".sops.yaml"), yamlKey, nil
}

// readFlatSecret decrypts a single secret value from its group SOPS file.
func (s *Server) readFlatSecret(id string) (string, error) {
	secretPath, yamlKey, err := s.getFlatSecretFilePath(id)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(secretPath); os.IsNotExist(err) {
		return "", fmt.Errorf("secret file not found")
	}
	res, err := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, s.sopsDecryptArgs(secretPath)...)
	if err != nil {
		return "", fmt.Errorf("failed to run sops: %w", err)
	}
	if res.ExitCode != 0 {
		return "", fmt.Errorf("sops decrypt failed: %s", strings.TrimSpace(res.Stderr))
	}
	secrets := map[string]interface{}{}
	if err := yaml.Unmarshal([]byte(res.Stdout), &secrets); err != nil {
		return "", fmt.Errorf("failed to parse decrypted YAML: %w", err)
	}
	value, ok := secrets[yamlKey]
	if !ok {
		return "", fmt.Errorf("secret key %q not found in file", yamlKey)
	}
	return fmt.Sprintf("%v", value), nil
}

// writeFlatSecret upserts a secret value into the group SOPS file.
// It decrypts the existing file, merges the new key, and re-encrypts in-place.
// On encryption failure the plaintext file is removed to avoid leaking secrets.
func (s *Server) writeFlatSecret(id string, value string) (string, error) {
	secretPath, yamlKey, err := s.getFlatSecretFilePath(id)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(secretPath), 0o755); err != nil {
		return "", fmt.Errorf("failed to create vars directory: %w", err)
	}

	// Read and decrypt existing group file so we can upsert the key.
	existing := map[string]interface{}{}
	if _, statErr := os.Stat(secretPath); statErr == nil {
		decRes, decErr := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, s.sopsDecryptArgs(secretPath)...)
		if decErr == nil && decRes.ExitCode == 0 {
			_ = yaml.Unmarshal([]byte(decRes.Stdout), &existing)
		}
	}

	// Upsert the key.
	existing[yamlKey] = value

	// Write merged plaintext, then encrypt in-place.
	plainBytes, err := yaml.Marshal(existing)
	if err != nil {
		return "", fmt.Errorf("failed to marshal group secrets: %w", err)
	}
	if err := os.WriteFile(secretPath, plainBytes, 0o600); err != nil {
		return "", fmt.Errorf("failed to write group secrets file: %w", err)
	}
	res, err := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, s.sopsEncryptArgs(secretPath)...)
	if err != nil {
		_ = os.Remove(secretPath)
		return "", fmt.Errorf("failed to run sops: %w", err)
	}
	if res.ExitCode != 0 {
		_ = os.Remove(secretPath)
		return "", fmt.Errorf("sops encrypt failed: %s", strings.TrimSpace(res.Stderr))
	}
	_ = os.Chmod(secretPath, 0o644)
	relPath, _ := filepath.Rel(s.config.ProjectRoot, secretPath)
	return relPath, nil
}

// handleAgenixSecretRead handles decrypting and reading a secret
// POST /api/secrets/read
//
// The secret group and key are derived from the variable ID:
//   - /dev/my-key     -> group="dev", key="my-key"
//   - /common/my-key  -> group="common", key="my-key"
//
// The value is decrypted directly from the group's SOPS file.
func (s *Server) handleAgenixSecretRead(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req AgenixDecryptRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	if strings.TrimSpace(req.ID) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "id is required")
		return
	}

	if isFlatSecretVariableID(req.ID) {
		value, err := s.readFlatSecret(req.ID)
		if err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, err.Error())
			return
		}
		s.writeAPI(w, http.StatusOK, AgenixDecryptResponse{ID: req.ID, Value: value})
		return
	}

	// Derive group and key from the variable ID (legacy grouped secret format)
	group, key := parseVariableID(req.ID)

	// Non-encrypted keygroups (var, computed) are not secrets — return literal value
	if group == "var" || group == "computed" {
		value, err := s.getVariableValue(req.ID)
		if err != nil {
			s.writeAPIError(w, http.StatusNotFound, "variable not found: "+err.Error())
			return
		}
		s.writeAPI(w, http.StatusOK, AgenixDecryptResponse{
			ID:    req.ID,
			Value: value,
		})
		return
	}

	// Direct SOPS decrypt: read the secret from the group's SOPS file
	secrets, err := s.readGroupSecrets(group)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to decrypt group secrets: "+err.Error())
		return
	}

	secretValue, exists := secrets[key]
	if !exists {
		s.writeAPIError(w, http.StatusNotFound, fmt.Sprintf("secret %q not found in group %q", key, group))
		return
	}

	log.Info().
		Str("id", req.ID).
		Str("group", group).
		Str("key", key).
		Msg("Secret decrypted via direct SOPS")

	s.writeAPI(w, http.StatusOK, AgenixDecryptResponse{
		ID:    req.ID,
		Value: fmt.Sprintf("%v", secretValue),
	})
}

// parseVariableID splits a variable ID like "/dev/my-key" into group and key.
// Returns ("dev", "my-key") for "/dev/my-key".
// Returns ("dev", id) as fallback if the ID doesn't match the expected format.
func parseVariableID(id string) (group string, key string) {
	// Remove leading slash
	trimmed := strings.TrimPrefix(id, "/")
	parts := strings.SplitN(trimmed, "/", 2)
	if len(parts) == 2 {
		return parts[0], parts[1]
	}
	// Fallback: assume "dev" group
	return "dev", trimmed
}

// getVariableValue looks up a variable by ID and returns its value
func (s *Server) getVariableValue(id string) (string, error) {
	data, err := s.readNixEntityJSON("variables")
	if err != nil {
		return "", fmt.Errorf("failed to read variables: %w", err)
	}

	var variables struct {
		Variables map[string]struct {
			Value string `json:"value"`
		} `json:"variables"`
	}

	if err := json.Unmarshal(data, &variables); err != nil {
		return "", fmt.Errorf("failed to parse variables: %w", err)
	}

	v, ok := variables.Variables[id]
	if !ok {
		return "", fmt.Errorf("variable %q not found", id)
	}

	return v.Value, nil
}

// findAgeIdentity looks for an AGE identity file in common locations
func (s *Server) findAgeIdentity() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}

	candidates := []string{
		filepath.Join(home, ".config", "age", "key.txt"),
		filepath.Join(home, ".age", "key.txt"),
		filepath.Join(home, ".config", "sops", "age", "keys.txt"),
	}

	for _, path := range candidates {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	return ""
}

// decryptAgeSecret decrypts an age-encrypted file using the given identity
func (s *Server) decryptAgeSecret(agePath, identityPath string) (string, error) {
	args := []string{"-d", "-i", identityPath, agePath}

	res, err := s.exec.Run("age", args...)
	if err != nil {
		return "", fmt.Errorf("failed to run age: %w", err)
	}

	if res.ExitCode != 0 {
		return "", fmt.Errorf("age decryption failed: %s", strings.TrimSpace(res.Stderr))
	}

	return res.Stdout, nil
}

// handleAgenixSecretWrite handles writing a secret using the group-based SOPS system.
// Legacy individual .age files are no longer supported - secrets are stored in
// group YAML files (vars/dev.sops.yaml, vars/staging.sops.yaml, vars/prod.sops.yaml).
// POST /api/secrets/write
func (s *Server) handleAgenixSecretWrite(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req AgenixSecretRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	// Validate request
	if strings.TrimSpace(req.Key) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "key is required")
		return
	}

	if isFlatSecretVariableID(req.ID) {
		relPath, err := s.writeFlatSecret(req.ID, req.Value)
		if err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, "failed to write secret: "+err.Error())
			return
		}
		s.writeAPI(w, http.StatusOK, AgenixSecretResponse{ID: req.ID, Path: relPath, AgePath: relPath, KeyCount: 0})
		return
	}

	// Determine the group from environments (default to "dev")
	group := "dev"
	if len(req.Environments) > 0 {
		group = req.Environments[0]
	}

	// Delegate to group-based secret write
	groupReq := GroupSecretRequest{
		Key:         req.Key,
		Value:       req.Value,
		Group:       group,
		Description: req.Description,
	}

	// Get recipients for this group
	safeGroup := sanitizeSecretID(group)
	recipients, err := s.getGroupRecipients(safeGroup)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "failed to get recipients: "+err.Error())
		return
	}
	if len(recipients) == 0 {
		s.writeAPIError(w, http.StatusBadRequest, "no recipients found - ensure master keys are configured")
		return
	}

	// Read existing secrets for this group
	secrets, err := s.readGroupSecrets(safeGroup)
	if err != nil {
		log.Warn().Err(err).Str("group", safeGroup).Msg("Failed to read existing group secrets, starting fresh")
		secrets = make(map[string]interface{})
	}

	// Update the secret
	secrets[groupReq.Key] = groupReq.Value

	// Write back encrypted
	if err := s.writeGroupSecrets(safeGroup, secrets, recipients); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to write secret: "+err.Error())
		return
	}

	// Update variables.nix with the secret metadata
	if err := s.updateVariableEntry(req.ID, req.Key, req.Description, req.Environments); err != nil {
		log.Warn().Err(err).Msg("Failed to update variables.nix")
	}

	groupPath, _ := s.getGroupFilePath(safeGroup)
	relPath, _ := filepath.Rel(s.config.ProjectRoot, groupPath)

	log.Info().
		Str("id", req.ID).
		Str("key", req.Key).
		Str("group", safeGroup).
		Str("path", relPath).
		Int("recipients", len(recipients)).
		Msg("Secret written to group")

	s.writeAPI(w, http.StatusOK, AgenixSecretResponse{
		ID:       req.ID,
		Path:     relPath,
		AgePath:  groupPath,
		KeyCount: len(recipients),
	})
}

// handleAgenixSecretDelete handles deleting a secret.
// Secrets are now stored in group YAML files, not individual .age files.
// DELETE /api/secrets/delete?id=<id>&group=<group>
func (s *Server) handleAgenixSecretDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		s.writeAPIError(w, http.StatusBadRequest, "id is required")
		return
	}

	if isFlatSecretVariableID(id) {
		secretPath, _, err := s.getFlatSecretFilePath(id)
		if err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, err.Error())
			return
		}
		if err := os.Remove(secretPath); err != nil && !os.IsNotExist(err) {
			s.writeAPIError(w, http.StatusInternalServerError, "failed to delete secret file: "+err.Error())
			return
		}
		if err := s.removeVariableEntry(id); err != nil {
			log.Warn().Err(err).Msg("Failed to remove from variables.nix")
		}
		s.writeAPI(w, http.StatusOK, map[string]any{"deleted": true, "id": id})
		return
	}

	group := strings.TrimSpace(r.URL.Query().Get("group"))
	if group == "" {
		group = "dev"
	}

	safeGroup := sanitizeSecretID(group)
	if safeGroup == "" {
		s.writeAPIError(w, http.StatusBadRequest, "invalid group name")
		return
	}

	// Get recipients for re-encryption
	recipients, err := s.getGroupRecipients(safeGroup)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "failed to get recipients: "+err.Error())
		return
	}

	// Read existing secrets
	secrets, err := s.readGroupSecrets(safeGroup)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to decrypt group secrets: "+err.Error())
		return
	}

	// Use the key (id) to find and delete the secret
	key := id
	if _, exists := secrets[key]; !exists {
		s.writeAPIError(w, http.StatusNotFound, "secret not found in group")
		return
	}

	delete(secrets, key)

	// Write back encrypted (or delete file if empty)
	if len(secrets) == 0 {
		groupPath, _ := s.getGroupFilePath(safeGroup)
		if err := os.Remove(groupPath); err != nil && !os.IsNotExist(err) {
			s.writeAPIError(w, http.StatusInternalServerError, "failed to delete empty group file: "+err.Error())
			return
		}
	} else {
		if err := s.writeGroupSecrets(safeGroup, secrets, recipients); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, "failed to write group secrets: "+err.Error())
			return
		}
	}

	// Remove from variables.nix
	if err := s.removeVariableEntry(id); err != nil {
		log.Warn().Err(err).Msg("Failed to remove from variables.nix")
	}

	log.Info().Str("id", id).Str("group", safeGroup).Msg("Secret deleted from group")
	s.writeAPI(w, http.StatusOK, map[string]any{"deleted": true, "id": id, "group": safeGroup})
}

// handleAgenixSecretsList lists all secrets across all groups.
// GET /api/secrets/list
func (s *Server) handleAgenixSecretsList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Delegate to the group-based list which returns all groups and their keys
	s.handleListAllGroups(w, r)
}

// getAgenixRecipients collects AGE/SSH public keys from Nix user definitions,
// filtered by environment access. Users are loaded from two sources in priority order:
//  1. .stack/data/external/users.nix (auto-synced from GitHub collaborators)
//  2. .stack/data/users.nix (manual definitions)
//
// System keys from secrets config are always appended.
func (s *Server) getAgenixRecipients(environments []string) ([]string, error) {
	// Try multiple user sources in order of priority:
	// 1. .stack/data/external/users.nix (auto-synced from GitHub)
	// 2. .stack/data/users.nix (manual user definitions)
	// Users are read from Nix files only (legacy users.yaml is no longer supported)

	userPaths := []string{
		filepath.Join(s.config.ProjectRoot, ".stack", "data", "external", "users.nix"),
		filepath.Join(s.config.ProjectRoot, ".stack", "data", "users.nix"),
	}

	var allUsers map[string]struct {
		Name                       string   `json:"name"`
		Github                     string   `json:"github,omitempty"`
		PublicKeys                 []string `json:"public-keys,omitempty"`
		SecretsAllowedEnvironments []string `json:"secrets-allowed-environments,omitempty"`
	}

	// Try each user source
	for _, usersPath := range userPaths {
		if _, err := os.Stat(usersPath); os.IsNotExist(err) {
			continue
		}

		args := []string{"eval", "--impure", "--json", "-f", usersPath}
		res, err := s.exec.RunNix(args...)
		if err != nil || res.ExitCode != 0 {
			continue
		}

		var users map[string]struct {
			Name                       string   `json:"name"`
			Github                     string   `json:"github,omitempty"`
			PublicKeys                 []string `json:"public-keys,omitempty"`
			SecretsAllowedEnvironments []string `json:"secrets-allowed-environments,omitempty"`
		}

		if err := json.Unmarshal([]byte(res.Stdout), &users); err != nil {
			continue
		}

		// Merge users (later sources can override)
		if allUsers == nil {
			allUsers = users
		} else {
			for k, v := range users {
				allUsers[k] = v
			}
		}
	}

	// If no Nix users found, return empty with error
	if allUsers == nil || len(allUsers) == 0 {
		return nil, fmt.Errorf("no users found in .stack/data/users.nix or .stack/data/external/users.nix")
	}

	var recipients []string
	envSet := make(map[string]bool)
	for _, env := range environments {
		envSet[strings.ToLower(env)] = true
	}

	for _, user := range allUsers {
		// If no environments specified, include all users
		// Otherwise, check if user has access to any of the specified environments
		hasAccess := len(environments) == 0
		if !hasAccess {
			for _, allowedEnv := range user.SecretsAllowedEnvironments {
				if envSet[strings.ToLower(allowedEnv)] {
					hasAccess = true
					break
				}
			}
		}

		if hasAccess {
			for _, key := range user.PublicKeys {
				key = strings.TrimSpace(key)
				// Accept both AGE keys (age1...) and SSH ed25519 keys (ssh-ed25519 ...)
				// The `age` CLI supports encrypting to SSH keys directly
				if strings.HasPrefix(key, "age1") || strings.HasPrefix(key, "ssh-ed25519 ") {
					recipients = append(recipients, key)
				}
			}
		}
	}

	// Also get system keys from secrets config
	systemKeys := s.getSystemKeys()
	recipients = append(recipients, systemKeys...)

	return recipients, nil
}

// getAgenixRecipientsFromYAML is deprecated - users are now read from Nix files only.
// Kept as a stub for backwards compatibility with secrets_groups.go fallback.
func (s *Server) getAgenixRecipientsFromYAML() ([]string, error) {
	return nil, fmt.Errorf("legacy users.yaml is no longer supported - use .stack/data/users.nix")
}

// getSystemKeys returns system-level AGE keys (CI, deploy servers, etc.)
func (s *Server) getSystemKeys() []string {
	// Read from secrets config
	configPath := filepath.Join(s.config.ProjectRoot, ".stack", "data", "secrets.nix")

	args := []string{"eval", "--impure", "--json", "-f", configPath}
	res, err := s.exec.RunNix(args...)
	if err != nil || res.ExitCode != 0 {
		return nil
	}

	var config struct {
		SystemKeys []string `json:"system-keys,omitempty"`
	}
	if err := json.Unmarshal([]byte(res.Stdout), &config); err != nil {
		return nil
	}

	return config.SystemKeys
}

// writeAgeSecret encrypts and writes a secret using the age CLI
func (s *Server) writeAgeSecret(path string, value string, recipients []string) error {
	// Create temp file with plaintext
	tmpFile, err := os.CreateTemp("", "stackpanel-secret-*.txt")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)

	if _, err := tmpFile.WriteString(value); err != nil {
		tmpFile.Close()
		return fmt.Errorf("failed to write temp file: %w", err)
	}
	tmpFile.Close()

	// Build age command with recipients
	args := []string{"-e"}
	for _, r := range recipients {
		args = append(args, "-r", r)
	}
	args = append(args, "-o", path, tmpPath)

	// Run age command
	res, err := s.exec.Run("age", args...)
	if err != nil {
		return fmt.Errorf("failed to run age: %w", err)
	}

	if res.ExitCode != 0 {
		return fmt.Errorf("age encryption failed: %s", strings.TrimSpace(res.Stderr))
	}

	return nil
}

// updateVariableEntry writes secret metadata to variables.nix so the Nix module
// system knows about the secret (its key, type, environments) even though the
// actual encrypted value lives in the SOPS file.
func (s *Server) updateVariableEntry(id, key, description string, environments []string) error {
	dataPath := filepath.Join(s.config.ProjectRoot, ".stack", "data", "variables.nix")

	// Read existing variables
	var variables map[string]map[string]any

	args := []string{"eval", "--impure", "--json", "-f", dataPath}
	res, err := s.exec.RunNix(args...)
	if err == nil && res.ExitCode == 0 {
		if err := json.Unmarshal([]byte(res.Stdout), &variables); err != nil {
			variables = make(map[string]map[string]any)
		}
	} else {
		variables = make(map[string]map[string]any)
	}

	// Add/update the entry
	entry := map[string]any{
		"id":    id,
		"key":   key,
		"type":  "SECRET",
		"value": "", // Empty for secrets - the actual value is in the .age file
	}
	if description != "" {
		entry["description"] = description
	}
	if len(environments) > 0 {
		entry["environments"] = environments
	}

	variables[id] = entry

	// Serialize back to Nix
	nixExpr, err := nixser.SerializeIndented(variables, "  ")
	if err != nil {
		return fmt.Errorf("failed to serialize to Nix: %w", err)
	}

	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(dataPath), 0o755); err != nil {
		return fmt.Errorf("failed to create data directory: %w", err)
	}

	if err := os.WriteFile(dataPath, []byte(nixExpr+"\n"), 0o644); err != nil {
		return fmt.Errorf("failed to write variables.nix: %w", err)
	}

	return nil
}

// removeVariableEntry removes a variable from variables.nix
func (s *Server) removeVariableEntry(id string) error {
	dataPath := filepath.Join(s.config.ProjectRoot, ".stack", "data", "variables.nix")

	var variables map[string]map[string]any

	args := []string{"eval", "--impure", "--json", "-f", dataPath}
	res, err := s.exec.RunNix(args...)
	if err != nil || res.ExitCode != 0 {
		return nil // Nothing to remove
	}

	if err := json.Unmarshal([]byte(res.Stdout), &variables); err != nil {
		return nil
	}

	delete(variables, id)

	nixExpr, err := nixser.SerializeIndented(variables, "  ")
	if err != nil {
		return fmt.Errorf("failed to serialize to Nix: %w", err)
	}

	return os.WriteFile(dataPath, []byte(nixExpr+"\n"), 0o644)
}

// updateSecretsNix is deprecated - individual .age files and secrets.nix are no longer used.
// Secrets are now stored in group YAML files encrypted via SOPS.
func (s *Server) updateSecretsNix() error {
	return nil
}

// sanitizeSecretID ensures the secret ID is safe for use as a filename
func sanitizeSecretID(id string) string {
	id = strings.TrimSpace(id)
	if id == "" {
		return ""
	}

	// Replace path separators with dashes
	id = strings.ReplaceAll(id, "/", "-")
	id = strings.ReplaceAll(id, "\\", "-")

	// Remove any characters that aren't alphanumeric, dash, or underscore
	var result strings.Builder
	for _, r := range id {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			result.WriteRune(r)
		}
	}

	sanitized := result.String()

	// Don't allow empty or just dots
	if sanitized == "" || sanitized == "." || sanitized == ".." {
		return ""
	}

	// Limit length
	if len(sanitized) > 128 {
		sanitized = sanitized[:128]
	}

	return sanitized
}

// ==============================================================================
// Age Identity Management
// ==============================================================================

const (
	// ageIdentityFileName is the filename for the age identity in state dir
	ageIdentityFileName = "age-identity"
)

// AgeIdentityRequest represents a request to set the age identity
type AgeIdentityRequest struct {
	// Value can be either:
	// - A path to a key file (e.g., ~/.ssh/id_ed25519)
	// - The actual key content (starts with AGE-SECRET-KEY- or -----BEGIN)
	Value string `json:"value"`
}

// AgeIdentityResponse is the response for age identity operations
type AgeIdentityResponse struct {
	// Type is either "path" or "key"
	Type string `json:"type"`
	// Value is the path (if type=path) or masked key indicator (if type=key)
	Value string `json:"value"`
	// KeyPath is the actual file path used for decryption
	KeyPath string `json:"keyPath"`
}

type SopsAgeKeysStatusResponse struct {
	Available          bool     `json:"available"`
	KeyCount           int      `json:"keyCount"`
	PublicKeys         []string `json:"publicKeys"`
	MatchedPublicKeys  []string `json:"matchedPublicKeys"`
	RecipientMatch     bool     `json:"recipientMatch"`
	MatchingRecipients []string `json:"matchingRecipients"`
	DecryptableGroups  []string `json:"decryptableGroups"`
	KeychainService    string   `json:"keychainService"`
	UserKeyPath        string   `json:"userKeyPath"`
	RepoKeyPath        string   `json:"repoKeyPath"`
	ConfiguredPaths    []string `json:"configuredPaths"`
	ConfiguredOpRefs   []string `json:"configuredOpRefs"`
	LocalKeyPath       string   `json:"localKeyPath"`
	LocalKeyExists     bool     `json:"localKeyExists"`
	StorageTier        string   `json:"storageTier"`
	Recommendation     string   `json:"recommendation,omitempty"`
	Error              string   `json:"error,omitempty"`
}

type SopsAgeKeySourceRequest struct {
	Type    string `json:"type"`
	Value   string `json:"value"`
	Account string `json:"account,omitempty"`
}

// getAgeIdentityPath returns the path to the age identity state file
func (s *Server) getAgeIdentityPath() string {
	stateDir := filepath.Join(s.config.ProjectRoot, ".stack", "state")
	return filepath.Join(stateDir, ageIdentityFileName)
}

// getAgeIdentityKeyPath returns the path to the actual key file (for key content storage)
func (s *Server) getAgeIdentityKeyPath() string {
	stateDir := filepath.Join(s.config.ProjectRoot, ".stack", "state")
	return filepath.Join(stateDir, "age-key.txt")
}

// isAgeKeyContent checks if the value appears to be AGE key content rather than a file path.
// This handles:
// - Raw AGE secret keys: AGE-SECRET-KEY-1...
// - AGE identity files with comment headers (# created:... followed by key)
// - SSH/PEM private keys: -----BEGIN...
func isAgeKeyContent(value string) bool {
	// Direct key content
	if strings.HasPrefix(value, "AGE-SECRET-KEY-") || strings.HasPrefix(value, "-----BEGIN") {
		return true
	}

	// AGE identity files often start with comment lines like:
	// # created: 2023-01-01T00:00:00Z
	// # public key: age1...
	// AGE-SECRET-KEY-1...
	if strings.HasPrefix(value, "#") {
		// Check if it contains an AGE secret key somewhere in the content
		return strings.Contains(value, "AGE-SECRET-KEY-")
	}

	return false
}

// handleAgeIdentityGet reads the current age identity configuration
func (s *Server) handleAgeIdentityGet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	identityFile := s.getAgeIdentityPath()
	resp := AgeIdentityResponse{
		Type:    "",
		Value:   "",
		KeyPath: "",
	}

	data, err := os.ReadFile(identityFile)
	if err != nil {
		if os.IsNotExist(err) {
			// No identity configured - return empty
			s.writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": resp})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to read identity: %v", err))
		return
	}

	value := strings.TrimSpace(string(data))
	if value == "" {
		s.writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": resp})
		return
	}

	// Determine if it's a path or key content
	if isAgeKeyContent(value) {
		// It's key content - the actual key is stored separately
		resp.Type = "key"
		resp.Value = "(key stored)"
		resp.KeyPath = s.getAgeIdentityKeyPath()
	} else {
		// It's a path
		resp.Type = "path"
		resp.Value = value
		// Expand ~ to home dir
		if strings.HasPrefix(value, "~") {
			if home, err := os.UserHomeDir(); err == nil {
				resp.KeyPath = filepath.Join(home, value[1:])
			} else {
				resp.KeyPath = value
			}
		} else {
			resp.KeyPath = value
		}
	}

	s.writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": resp})
}

// handleAgeIdentitySet sets the age identity (path or key content)
func (s *Server) handleAgeIdentitySet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	var req AgeIdentityRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	stateDir := filepath.Join(s.config.ProjectRoot, ".stack", "state")
	if err := os.MkdirAll(stateDir, 0700); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to create state dir: %v", err))
		return
	}

	identityFile := s.getAgeIdentityPath()
	keyFile := s.getAgeIdentityKeyPath()
	value := strings.TrimSpace(req.Value)

	resp := AgeIdentityResponse{}

	if value == "" {
		// Clear the identity
		os.Remove(identityFile)
		os.Remove(keyFile)
		resp.Type = ""
		resp.Value = ""
		resp.KeyPath = ""
	} else if isAgeKeyContent(value) {
		// It's key content - store the key in a separate file
		if err := os.WriteFile(keyFile, []byte(value), 0600); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to write key: %v", err))
			return
		}
		// Store indicator in identity file
		if err := os.WriteFile(identityFile, []byte("AGE-SECRET-KEY-..."), 0600); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to write identity: %v", err))
			return
		}
		resp.Type = "key"
		resp.Value = "(key stored)"
		resp.KeyPath = keyFile
		log.Info().Str("keyPath", keyFile).Msg("Age identity key stored")
	} else {
		// It's a path - validate it exists
		expandedPath := value
		if strings.HasPrefix(value, "~") {
			if home, err := os.UserHomeDir(); err == nil {
				expandedPath = filepath.Join(home, value[1:])
			}
		}

		if _, err := os.Stat(expandedPath); err != nil {
			s.writeAPIError(w, http.StatusBadRequest, fmt.Sprintf("Key file not found: %s", expandedPath))
			return
		}

		// Store the path
		if err := os.WriteFile(identityFile, []byte(value), 0600); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to write identity: %v", err))
			return
		}
		// Remove any stored key content
		os.Remove(keyFile)

		resp.Type = "path"
		resp.Value = value
		resp.KeyPath = expandedPath
		log.Info().Str("path", value).Str("expanded", expandedPath).Msg("Age identity path stored")
	}

	s.writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": resp})
}

func (s *Server) handleSopsAgeKeysStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	resp := s.resolveSopsAgeKeysStatus("")
	s.writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": resp})
}

func (s *Server) handleValidateSopsAgeKeySource(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	var req SopsAgeKeySourceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if strings.TrimSpace(req.Type) == "" || strings.TrimSpace(req.Value) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "type and value are required")
		return
	}
	resp := s.validateSingleSopsAgeKeySource(req)
	s.writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": resp})
}

func (s *Server) validateSingleSopsAgeKeySource(req SopsAgeKeySourceRequest) SopsAgeKeysStatusResponse {
	resp := SopsAgeKeysStatusResponse{
		PublicKeys:         []string{},
		MatchedPublicKeys:  []string{},
		MatchingRecipients: []string{},
		DecryptableGroups:  []string{},
		ConfiguredPaths:    []string{},
		ConfiguredOpRefs:   []string{},
		LocalKeyPath:       filepath.Join(s.config.ProjectRoot, ".stack", "keys", "local.txt"),
		KeychainService:    s.defaultKeychainService(),
	}

	privateKeys, err := s.readKeysFromSource(req)
	if err != nil {
		resp.Error = err.Error()
		return resp
	}
	resp.Available = len(privateKeys) > 0
	resp.KeyCount = len(privateKeys)
	resp.PublicKeys = s.deriveAgePublicKeys(privateKeys)

	if serializable, serr := s.getSerializableSecretsConfig(); serr == nil {
		matchingRecipientNames := map[string]struct{}{}
		matchedPublicKeys := map[string]struct{}{}
		for recipientName, recipient := range serializable.Recipients {
			configuredKey := strings.TrimSpace(recipient.PublicKey)
			for _, pub := range resp.PublicKeys {
				if strings.TrimSpace(pub) == configuredKey {
					resp.RecipientMatch = true
					matchingRecipientNames[recipientName] = struct{}{}
					matchedPublicKeys[pub] = struct{}{}
				}
			}
		}
		for pub := range matchedPublicKeys {
			resp.MatchedPublicKeys = append(resp.MatchedPublicKeys, pub)
		}
		sort.Strings(resp.MatchedPublicKeys)
		for name := range matchingRecipientNames {
			resp.MatchingRecipients = append(resp.MatchingRecipients, name)
		}
		sort.Strings(resp.MatchingRecipients)
		for groupName, group := range serializable.RecipientGroups {
			for _, recipientName := range group.Recipients {
				if _, ok := matchingRecipientNames[recipientName]; ok {
					resp.DecryptableGroups = append(resp.DecryptableGroups, groupName)
					break
				}
			}
		}
		sort.Strings(resp.DecryptableGroups)
	}

	if !resp.Available {
		resp.Recommendation = "This source did not return any AGE private keys."
	} else if !resp.RecipientMatch {
		resp.Recommendation = "The source returned keys, but none of their public keys match configured recipients."
	}
	return resp
}

// readKeysFromSource retrieves AGE private keys from various backends:
// file paths, SSH keys (via ssh-to-age), macOS Keychain, 1Password, AWS SSM,
// vals expressions, or arbitrary shell scripts.
func (s *Server) readKeysFromSource(req SopsAgeKeySourceRequest) ([]string, error) {
	value := strings.TrimSpace(req.Value)
	account := strings.TrimSpace(req.Account)
	var stdout string
	switch req.Type {
	case "user-key-path", "repo-key-path", "file", "ssh-key":
		resolved := value
		resolved = strings.Replace(resolved, "$HOME", os.Getenv("HOME"), 1)
		resolved = strings.Replace(resolved, "$XDG_CONFIG_HOME", os.Getenv("XDG_CONFIG_HOME"), 1)
		if strings.HasPrefix(resolved, "~") {
			resolved = filepath.Join(os.Getenv("HOME"), strings.TrimPrefix(resolved, "~/"))
		}
		if !filepath.IsAbs(resolved) {
			resolved = filepath.Join(s.config.ProjectRoot, resolved)
		}
		if req.Type == "ssh-key" {
			res, err := s.exec.RunWithOptions("ssh-to-age", s.config.ProjectRoot, nil, "-private-key", "-i", resolved)
			if err != nil || res.ExitCode != 0 {
				if err != nil {
					return nil, fmt.Errorf("ssh-to-age failed: %w", err)
				}
				return nil, fmt.Errorf("ssh-to-age: %s", strings.TrimSpace(res.Stderr))
			}
			stdout = res.Stdout
		} else {
			bytes, err := os.ReadFile(resolved)
			if err != nil {
				return nil, fmt.Errorf("failed to read %s: %w", resolved, err)
			}
			stdout = string(bytes)
		}
	case "keychain":
		args := []string{"find-generic-password", "-s", value, "-w"}
		if account != "" {
			args = []string{"find-generic-password", "-s", value, "-a", account, "-w"}
		}
		res, err := s.exec.RunWithOptions("security", s.config.ProjectRoot, nil, args...)
		if err != nil || res.ExitCode != 0 {
			if err != nil {
				return nil, err
			}
			return nil, fmt.Errorf("%s", strings.TrimSpace(res.Stderr))
		}
		stdout = res.Stdout
	case "op-ref":
		args := []string{"read", value}
		if account != "" {
			args = []string{"read", "--account", account, value}
		}
		res, err := s.exec.RunWithOptions("op", s.config.ProjectRoot, nil, args...)
		if err != nil || res.ExitCode != 0 {
			if err != nil {
				return nil, err
			}
			return nil, fmt.Errorf("%s", strings.TrimSpace(res.Stderr))
		}
		stdout = res.Stdout
	case "aws-kms":
		var args []string
		if strings.HasPrefix(value, "arn:") {
			args = []string{"secretsmanager", "get-secret-value",
				"--secret-id", value,
				"--query", "SecretString",
				"--output", "text"}
		} else {
			args = []string{"ssm", "get-parameter",
				"--name", value,
				"--with-decryption",
				"--query", "Parameter.Value",
				"--output", "text"}
		}
		res, err := s.exec.RunWithOptions("aws", s.config.ProjectRoot, nil, args...)
		if err != nil || res.ExitCode != 0 {
			if err != nil {
				return nil, err
			}
			return nil, fmt.Errorf("%s", strings.TrimSpace(res.Stderr))
		}
		stdout = res.Stdout
	case "vals":
		res, err := s.exec.RunWithOptions("vals", s.config.ProjectRoot, nil, "eval", "-e", value)
		if err != nil || res.ExitCode != 0 {
			if err != nil {
				return nil, err
			}
			return nil, fmt.Errorf("%s", strings.TrimSpace(res.Stderr))
		}
		stdout = res.Stdout
	case "script":
		res, err := s.exec.RunWithOptions("bash", s.config.ProjectRoot, nil, "-lc", value)
		if err != nil || res.ExitCode != 0 {
			if err != nil {
				return nil, err
			}
			return nil, fmt.Errorf("%s", strings.TrimSpace(res.Stderr))
		}
		stdout = res.Stdout
	default:
		return nil, fmt.Errorf("unsupported source type: %s", req.Type)
	}
	keys := []string{}
	for _, line := range strings.Split(stdout, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "AGE-SECRET-KEY-") {
			keys = append(keys, trimmed)
		}
	}
	return keys, nil
}

// resolveSopsAgeKeysStatus discovers all available AGE private keys, derives their
// public keys, and cross-references them against configured recipients to determine
// which secret groups the current user can decrypt. This powers the "key status"
// panel in the studio UI.
func (s *Server) resolveSopsAgeKeysStatus(overrideSourceLines string) SopsAgeKeysStatusResponse {

	resp := SopsAgeKeysStatusResponse{
		PublicKeys:         []string{},
		MatchedPublicKeys:  []string{},
		MatchingRecipients: []string{},
		DecryptableGroups:  []string{},
		ConfiguredPaths:    []string{},
		ConfiguredOpRefs:   []string{},
		LocalKeyPath:       filepath.Join(s.config.ProjectRoot, ".stack", "keys", "local.txt"),
		KeychainService:    s.defaultKeychainService(),
	}

	if _, err := os.Stat(resp.LocalKeyPath); err == nil {
		resp.LocalKeyExists = true
	}
	hasRobustSource := false

	if data, err := s.readConsolidatedData(); err == nil {
		if secretsRaw, ok := data["secrets"].(map[string]any); ok {
			if sakRaw, ok := secretsRaw["sops-age-keys"].(map[string]any); ok {
				if sourcesRaw, ok := sakRaw["sources"].([]any); ok {
					for _, raw := range sourcesRaw {
						source, ok := raw.(map[string]any)
						if !ok {
							continue
						}
						enabled := true
						if enabledRaw, ok := source["enabled"].(bool); ok {
							enabled = enabledRaw
						}
						if !enabled {
							continue
						}
						typeVal, _ := source["type"].(string)
						value, _ := source["value"].(string)
						value = strings.TrimSpace(value)
						if value == "" {
							continue
						}
						switch typeVal {
						case "user-key-path":
							resp.UserKeyPath = value
						case "repo-key-path":
							resp.RepoKeyPath = value
						case "file":
							resp.ConfiguredPaths = append(resp.ConfiguredPaths, value)
						case "op-ref", "keychain", "vals", "script":
							if typeVal == "op-ref" {
								resp.ConfiguredOpRefs = append(resp.ConfiguredOpRefs, value)
							}
							hasRobustSource = true
						}
					}
				}
				if userPath, ok := sakRaw["user-key-path"].(string); ok {
					resp.UserKeyPath = userPath
				}
				if repoPath, ok := sakRaw["repo-key-path"].(string); ok {
					resp.RepoKeyPath = repoPath
				}
				if pathsRaw, ok := sakRaw["paths"].([]any); ok {
					for _, v := range pathsRaw {
						if path, ok := v.(string); ok && strings.TrimSpace(path) != "" {
							resp.ConfiguredPaths = append(resp.ConfiguredPaths, path)
						}
					}
				}
				if refsRaw, ok := sakRaw["op-refs"].([]any); ok {
					for _, v := range refsRaw {
						if ref, ok := v.(string); ok && strings.TrimSpace(ref) != "" {
							resp.ConfiguredOpRefs = append(resp.ConfiguredOpRefs, ref)
						}
					}
				}
			}
		}
	}

	if resp.RepoKeyPath == "" {
		resp.RepoKeyPath = ".stack/keys/local.txt"
	}
	if resp.UserKeyPath == "" {
		if runtime.GOOS == "darwin" {
			resp.UserKeyPath = "$HOME/Library/Application Support/sops/age/keys.txt"
		} else {
			resp.UserKeyPath = "$XDG_CONFIG_HOME/sops/age/keys.txt"
		}
	}

	env := []string{}
	if strings.TrimSpace(overrideSourceLines) != "" {
		env = append(env, "SOPS_AGE_SOURCE_LINES_OVERRIDE="+overrideSourceLines)
	}
	res, err := s.exec.RunWithOptions("sops-age-keys", s.config.ProjectRoot, env, "--json")
	if err != nil {
		resp.Error = err.Error()
	} else if res.ExitCode != 0 {
		resp.Error = strings.TrimSpace(res.Stderr)
	} else {
		var payload struct {
			Available   bool     `json:"available"`
			PrivateKeys []string `json:"privateKeys"`
			PublicKeys  []string `json:"publicKeys"`
			Paths       []string `json:"paths"`
			OpRefs      []string `json:"opRefs"`
			MissingOp   bool     `json:"missingOp"`
		}
		if err := json.Unmarshal([]byte(res.Stdout), &payload); err != nil {
			// Backward compatibility: older agent/devshell sessions may still have
			// a pre-JSON sops-age-keys on PATH that prints raw private keys.
			keys := []string{}
			for _, line := range strings.Split(res.Stdout, "\n") {
				trimmed := strings.TrimSpace(line)
				if strings.HasPrefix(trimmed, "AGE-SECRET-KEY-") {
					keys = append(keys, trimmed)
				}
			}
			if len(keys) == 0 {
				resp.Error = fmt.Sprintf("failed to parse sops-age-keys output: %v", err)
			} else {
				payload.Available = true
				payload.PrivateKeys = keys
				payload.PublicKeys = s.deriveAgePublicKeys(keys)
			}
		} else {
			// parsed JSON payload already populated
		}

		if len(payload.PrivateKeys) > 0 || payload.Available {
			resp.Available = payload.Available
			resp.KeyCount = len(payload.PrivateKeys)
			resp.PublicKeys = payload.PublicKeys
			if strings.TrimSpace(overrideSourceLines) != "" {
				resp.ConfiguredPaths = payload.Paths
				resp.ConfiguredOpRefs = payload.OpRefs
			}

			if serializable, serr := s.getSerializableSecretsConfig(); serr == nil {
				// Build a normalised map: AGE-public-key -> recipientName
				// Recipients may be stored as "age1..." or "ssh-ed25519 AAAA..."
				// Convert SSH public keys to their AGE equivalents for comparison.
				normalizedRecipients := map[string]string{} // agePublicKey -> recipientName
				for recipientName, recipient := range serializable.Recipients {
					raw := strings.TrimSpace(recipient.PublicKey)
					if strings.HasPrefix(raw, "age1") {
						normalizedRecipients[raw] = recipientName
					} else if strings.HasPrefix(raw, "ssh-") {
						if agePub := s.sshPublicKeyToAge(raw); agePub != "" {
							normalizedRecipients[agePub] = recipientName
						}
					}
				}

				matchingRecipientNames := map[string]struct{}{}
				matchedPublicKeys := map[string]struct{}{}
				for _, pub := range resp.PublicKeys {
					if recipientName, ok := normalizedRecipients[strings.TrimSpace(pub)]; ok {
						resp.RecipientMatch = true
						matchingRecipientNames[recipientName] = struct{}{}
						matchedPublicKeys[pub] = struct{}{}
					}
				}
				for pub := range matchedPublicKeys {
					resp.MatchedPublicKeys = append(resp.MatchedPublicKeys, pub)
				}
				sort.Strings(resp.MatchedPublicKeys)
				for name := range matchingRecipientNames {
					resp.MatchingRecipients = append(resp.MatchingRecipients, name)
				}
				sort.Strings(resp.MatchingRecipients)

				for groupName, group := range serializable.RecipientGroups {
					for _, recipientName := range group.Recipients {
						if _, ok := matchingRecipientNames[recipientName]; ok {
							resp.DecryptableGroups = append(resp.DecryptableGroups, groupName)
							break
						}
					}
				}
				sort.Strings(resp.DecryptableGroups)
			}
		}
	}

	switch {
	case hasRobustSource || len(resp.ConfiguredOpRefs) > 0:
		resp.StorageTier = "external"
	case resp.UserKeyPath != "" || len(resp.ConfiguredPaths) > 0 || resp.LocalKeyExists:
		resp.StorageTier = "local-only"
	default:
		resp.StorageTier = "none"
	}

	if !resp.Available {
		resp.Recommendation = "No AGE key is currently resolvable. Configure stackpanel.secrets.sops-age-keys with a local path or a secure external source before editing secrets."
	} else if !resp.RecipientMatch {
		resp.Recommendation = "Keys resolve successfully, but none of their derived public keys match the configured recipients. Add the matching public key to stackpanel.secrets.recipients or stackpanel.users."
	} else if resp.StorageTier == "local-only" {
		resp.Recommendation = "Keys resolve successfully, but only from local files. Consider storing them in 1Password, macOS Keychain, AWS SSM, or another secure external source outside the repo."
	}
	return resp
}

// deriveAgePublicKeys converts AGE secret keys to their corresponding public keys
// by writing each to a temp file and invoking `age-keygen -y`. Duplicates are removed.
func (s *Server) deriveAgePublicKeys(secretKeys []string) []string {
	publicKeys := []string{}
	seen := map[string]struct{}{}
	for _, secretKey := range secretKeys {
		tmp, err := os.CreateTemp("", "stackpanel-age-key-*.txt")
		if err != nil {
			continue
		}
		tmpPath := tmp.Name()
		_ = tmp.Chmod(0o600)
		_, _ = tmp.WriteString(secretKey + "\n")
		_ = tmp.Close()
		res, err := s.exec.RunWithOptions("age-keygen", s.config.ProjectRoot, nil, "-y", tmpPath)
		_ = os.Remove(tmpPath)
		if err != nil || res.ExitCode != 0 {
			continue
		}
		pub := strings.TrimSpace(res.Stdout)
		if pub == "" {
			continue
		}
		if _, ok := seen[pub]; ok {
			continue
		}
		seen[pub] = struct{}{}
		publicKeys = append(publicKeys, pub)
	}
	sort.Strings(publicKeys)
	return publicKeys
}

// sshPublicKeyToAge converts an SSH public key string (e.g. "ssh-ed25519 AAAA...")
// to its AGE public key equivalent using the ssh-to-age binary.
// Returns "" if conversion fails or the key is not an Ed25519 key.
func (s *Server) sshPublicKeyToAge(sshPubKey string) string {
	tmp, err := os.CreateTemp("", "stackpanel-ssh-pub-*.pub")
	if err != nil {
		return ""
	}
	tmpPath := tmp.Name()
	_, _ = tmp.WriteString(sshPubKey + "\n")
	_ = tmp.Close()
	defer os.Remove(tmpPath)

	res, err := s.exec.RunWithOptions("ssh-to-age", s.config.ProjectRoot, nil, "-i", tmpPath)
	if err != nil || res.ExitCode != 0 {
		return ""
	}
	pub := strings.TrimSpace(res.Stdout)
	if !strings.HasPrefix(pub, "age1") {
		return ""
	}
	return pub
}

// defaultKeychainService builds a macOS Keychain service name unique to this
// project by incorporating the git remote host/owner/repo. This prevents key
// collisions when a developer works on multiple stackpanel projects.
func (s *Server) defaultKeychainService() string {
	base := "stackpanel.sops-age-key"
	res, err := s.exec.RunWithOptions("git", s.config.ProjectRoot, nil, "remote", "get-url", "origin")
	if err != nil || res.ExitCode != 0 {
		return base + "." + sanitizeServiceSegment(filepath.Base(s.config.ProjectRoot))
	}
	remote := strings.TrimSpace(res.Stdout)
	host, owner, repo := parseGitRemote(remote)
	parts := []string{base}
	for _, part := range []string{host, owner, repo} {
		part = sanitizeServiceSegment(part)
		if part != "" {
			parts = append(parts, part)
		}
	}
	if len(parts) == 1 {
		parts = append(parts, sanitizeServiceSegment(filepath.Base(s.config.ProjectRoot)))
	}
	return strings.Join(parts, ".")
}

// sanitizeServiceSegment normalizes a string for use in a dot-separated Keychain service name.
func sanitizeServiceSegment(value string) string {
	value = strings.TrimSpace(strings.TrimSuffix(value, ".git"))
	value = strings.ReplaceAll(value, "/", ".")
	value = strings.ReplaceAll(value, ":", ".")
	value = strings.ReplaceAll(value, "_", "-")
	value = strings.ToLower(value)
	filtered := make([]rune, 0, len(value))
	lastDot := false
	for _, r := range value {
		keep := (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' || r == '.'
		if !keep {
			continue
		}
		if r == '.' {
			if lastDot {
				continue
			}
			lastDot = true
		} else {
			lastDot = false
		}
		filtered = append(filtered, r)
	}
	return strings.Trim(string(filtered), ".-")
}

// parseGitRemote extracts host, owner, and repo from git remote URLs.
// Supports git@host:owner/repo, https://host/owner/repo, and ssh:// variants.
func parseGitRemote(remote string) (host string, owner string, repo string) {
	remote = strings.TrimSpace(remote)
	if strings.HasPrefix(remote, "git@") {
		withoutPrefix := strings.TrimPrefix(remote, "git@")
		parts := strings.SplitN(withoutPrefix, ":", 2)
		if len(parts) == 2 {
			host = parts[0]
			segments := strings.Split(strings.TrimSuffix(parts[1], ".git"), "/")
			if len(segments) >= 2 {
				owner = segments[0]
				repo = segments[1]
			}
		}
		return
	}
	if strings.HasPrefix(remote, "https://") || strings.HasPrefix(remote, "http://") || strings.HasPrefix(remote, "ssh://") {
		withoutScheme := remote
		if idx := strings.Index(withoutScheme, "://"); idx != -1 {
			withoutScheme = withoutScheme[idx+3:]
		}
		withoutScheme = strings.TrimPrefix(withoutScheme, "git@")
		parts := strings.Split(strings.TrimSuffix(withoutScheme, ".git"), "/")
		if len(parts) >= 3 {
			host = parts[0]
			owner = parts[1]
			repo = parts[2]
		}
	}
	return
}

// GetConfiguredIdentityPath returns the identity path for use by other handlers
// Returns empty string if not configured
func (s *Server) GetConfiguredIdentityPath() string {
	identityFile := s.getAgeIdentityPath()
	data, err := os.ReadFile(identityFile)
	if err != nil {
		return ""
	}

	value := strings.TrimSpace(string(data))
	if value == "" {
		return ""
	}

	// If it's key content, return the key file path
	if isAgeKeyContent(value) {
		return s.getAgeIdentityKeyPath()
	}

	// It's a path - expand ~
	if strings.HasPrefix(value, "~") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, value[1:])
		}
	}

	return value
}

// handleAgeIdentity routes to GET or POST handlers
func (s *Server) handleAgeIdentity(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleAgeIdentityGet(w, r)
	case http.MethodPost:
		s.handleAgeIdentitySet(w, r)
	default:
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
	}
}

// ==============================================================================
// KMS Configuration Management
// ==============================================================================

const (
	kmsConfigFileName = "kms-config.json"
)

// KMSConfigRequest represents a request to set KMS configuration
type KMSConfigRequest struct {
	Enable     bool   `json:"enable"`
	KeyArn     string `json:"keyArn"`
	AwsProfile string `json:"awsProfile,omitempty"`
}

// KMSConfigResponse is the response for KMS config operations
type KMSConfigResponse struct {
	Enable     bool   `json:"enable"`
	KeyArn     string `json:"keyArn"`
	AwsProfile string `json:"awsProfile"`
	// Source indicates where the config came from: "state" or "nix"
	Source string `json:"source"`
}

// getKMSConfigPath returns the path to the KMS config state file
func (s *Server) getKMSConfigPath() string {
	stateDir := filepath.Join(s.config.ProjectRoot, ".stack", "state")
	return filepath.Join(stateDir, kmsConfigFileName)
}

func (s *Server) readKMSConfig() (KMSConfigResponse, error) {
	resp := KMSConfigResponse{
		Enable:     false,
		KeyArn:     "",
		AwsProfile: "",
		Source:     "",
	}

	data, err := os.ReadFile(s.getKMSConfigPath())
	if err != nil {
		if os.IsNotExist(err) {
			return resp, nil
		}
		return resp, fmt.Errorf("failed to read KMS config: %w", err)
	}

	if err := json.Unmarshal(data, &resp); err != nil {
		return KMSConfigResponse{}, fmt.Errorf("failed to parse KMS config: %w", err)
	}

	resp.Source = "state"
	return resp, nil
}

// normalizePublicKeyForSops converts an SSH public key to its AGE equivalent.
// Returns the key unchanged if it is already AGE format or conversion fails.
// This is a package-level helper so it can be used without a Server receiver.
func normalizePublicKeyForSops(pub string, sshToAgeFn func(string) string) string {
	pub = strings.TrimSpace(pub)
	if pub == "" {
		return ""
	}
	if strings.HasPrefix(pub, "age1") {
		return pub
	}
	if strings.HasPrefix(pub, "ssh-") {
		if converted := sshToAgeFn(pub); converted != "" {
			return converted
		}
		// Conversion failed — return raw so it is still written; SOPS handles SSH natively
		return pub
	}
	return pub
}

// renderSecretsSopsConfig generates the .sops.yaml creation rules file from
// the Nix-computed secrets config. Each secret group gets its own path_regex
// rule, and a catch-all rule covers any remaining encrypted files.
func (s *Server) renderSecretsSopsConfig(serializable *SerializableSecretsConfig, kmsCfg KMSConfigResponse) string {
	if serializable == nil {
		serializable = &SerializableSecretsConfig{}
	}

	normFn := func(pub string) string {
		return normalizePublicKeyForSops(pub, s.sshPublicKeyToAge)
	}

	recipientNames := make([]string, 0, len(serializable.Recipients))
	for name := range serializable.Recipients {
		recipientNames = append(recipientNames, name)
	}
	sort.Strings(recipientNames)

	groupNames := make([]string, 0, len(serializable.Groups))
	for name := range serializable.Groups {
		groupNames = append(groupNames, name)
	}
	sort.Strings(groupNames)

	kmsEnabled := kmsCfg.Enable && strings.TrimSpace(kmsCfg.KeyArn) != ""

	var sb strings.Builder
	sb.WriteString("# Auto-generated from stackpanel secrets config - DO NOT EDIT.\n")
	sb.WriteString("# All YAML comments inside encrypted files are stored in plaintext and\n")
	sb.WriteString("# double as descriptions in the studio UI.\n")
	if len(recipientNames) == 0 {
		sb.WriteString("keys: []\n")
	} else {
		sb.WriteString("keys:\n")
		for _, name := range recipientNames {
			recipient := serializable.Recipients[name]
			publicKey := normFn(recipient.PublicKey)
			if publicKey == "" {
				continue
			}
			anchor := sanitizeSecretID(name)
			if anchor == "" {
				anchor = strings.ReplaceAll(name, "-", "_")
			}
			sb.WriteString(fmt.Sprintf("  - &%s %s\n", anchor, publicKey))
		}
	}

	rules := make([]string, 0, len(groupNames)+1)
	for _, groupName := range groupNames {
		rule := s.renderSecretsSopsRule(fmt.Sprintf("^vars/%s\\.sops\\.yaml$", groupName), serializable, serializable.Groups[groupName].Recipients, kmsCfg, kmsEnabled, normFn)
		if rule != "" {
			rules = append(rules, rule)
		}
	}
	catchAll := s.renderSecretsSopsRule(`.*(secret|\.enc\.).*`, serializable, recipientNames, kmsCfg, kmsEnabled, normFn)
	if catchAll != "" {
		rules = append(rules, catchAll)
	}

	if len(rules) == 0 {
		sb.WriteString("creation_rules: []\n")
		return sb.String()
	}

	sb.WriteString("creation_rules:\n")
	for _, rule := range rules {
		sb.WriteString(rule)
	}

	return sb.String()
}

// renderSecretsSopsRule generates a single SOPS creation_rule YAML block.
func (s *Server) renderSecretsSopsRule(pathRegex string, serializable *SerializableSecretsConfig, recipients []string, kmsCfg KMSConfigResponse, kmsEnabled bool, normFn func(string) string) string {
	if len(recipients) == 0 && !kmsEnabled {
		return ""
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("  - path_regex: %s\n", pathRegex))
	sb.WriteString("    unencrypted_comment_regex: '.*'\n")

	seenAnchors := map[string]struct{}{}
	if len(recipients) > 0 {
		sb.WriteString("    age:\n")
		for _, recipientName := range recipients {
			recipient, ok := serializable.Recipients[recipientName]
			if !ok {
				continue
			}
			// Skip if neither raw nor normalized key exists
			normalizedKey := normFn(recipient.PublicKey)
			if normalizedKey == "" {
				continue
			}
			anchor := sanitizeSecretID(recipientName)
			if anchor == "" {
				anchor = strings.ReplaceAll(recipientName, "-", "_")
			}
			if _, exists := seenAnchors[anchor]; exists {
				continue
			}
			seenAnchors[anchor] = struct{}{}
			sb.WriteString(fmt.Sprintf("      - *%s\n", anchor))
		}
	}

	if kmsEnabled {
		sb.WriteString(fmt.Sprintf("    kms: %q\n", kmsCfg.KeyArn))
		if strings.TrimSpace(kmsCfg.AwsProfile) != "" {
			sb.WriteString(fmt.Sprintf("    aws_profile: %q\n", kmsCfg.AwsProfile))
		}
	}

	return sb.String()
}

// regenerateSecretsSopsConfig re-renders and writes the .sops.yaml file.
// Called after any change to recipients, groups, or KMS config.
func (s *Server) regenerateSecretsSopsConfig(kmsCfg KMSConfigResponse) error {
	serializable, err := s.getSerializableSecretsConfig()
	if err != nil {
		return err
	}

	sopsConfigPath := serializable.SopsConfigFile
	if strings.TrimSpace(sopsConfigPath) == "" {
		secretsDir := serializable.SecretsDir
		if strings.TrimSpace(secretsDir) == "" {
			secretsDir = ".stack/secrets"
		}
		sopsConfigPath = filepath.Join(secretsDir, ".sops.yaml")
	}
	if !filepath.IsAbs(sopsConfigPath) {
		sopsConfigPath = filepath.Join(s.config.ProjectRoot, sopsConfigPath)
	}

	content := s.renderSecretsSopsConfig(serializable, kmsCfg)
	if err := os.MkdirAll(filepath.Dir(sopsConfigPath), 0o755); err != nil {
		return fmt.Errorf("failed to create secrets config dir: %w", err)
	}
	if err := os.WriteFile(sopsConfigPath, []byte(content), 0o644); err != nil {
		return fmt.Errorf("failed to write %s: %w", sopsConfigPath, err)
	}
	return nil
}

func (s *Server) saveKMSConfig(req KMSConfigRequest) (KMSConfigResponse, error) {
	stateDir := filepath.Join(s.config.ProjectRoot, ".stack", "state")
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return KMSConfigResponse{}, fmt.Errorf("failed to create state dir: %w", err)
	}

	configFile := s.getKMSConfigPath()
	resp := KMSConfigResponse{
		Enable:     req.Enable,
		KeyArn:     req.KeyArn,
		AwsProfile: req.AwsProfile,
		Source:     "state",
	}

	if !req.Enable || strings.TrimSpace(req.KeyArn) == "" {
		if err := os.Remove(configFile); err != nil && !os.IsNotExist(err) {
			return KMSConfigResponse{}, fmt.Errorf("failed to clear KMS config: %w", err)
		}
		resp = KMSConfigResponse{}
		log.Info().Msg("KMS config cleared")
	} else {
		data, err := json.MarshalIndent(resp, "", "  ")
		if err != nil {
			return KMSConfigResponse{}, fmt.Errorf("failed to marshal config: %w", err)
		}
		if err := os.WriteFile(configFile, data, 0o600); err != nil {
			return KMSConfigResponse{}, fmt.Errorf("failed to write config: %w", err)
		}
		log.Info().Bool("enable", req.Enable).Str("keyArn", req.KeyArn).Msg("KMS config saved")
	}

	if err := s.regenerateSecretsSopsConfig(resp); err != nil {
		return KMSConfigResponse{}, err
	}

	return resp, nil
}

// handleKMSConfigGet reads the current KMS configuration
func (s *Server) handleKMSConfigGet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	resp, err := s.readKMSConfig()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}
	s.writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": resp})
}

// handleKMSConfigSet sets the KMS configuration
func (s *Server) handleKMSConfigSet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	var req KMSConfigRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	// Validate KMS ARN format if provided
	if req.Enable && req.KeyArn != "" {
		if !strings.HasPrefix(req.KeyArn, "arn:aws:kms:") {
			s.writeAPIError(w, http.StatusBadRequest, "Invalid KMS ARN format - must start with arn:aws:kms:")
			return
		}
	}

	resp, err := s.saveKMSConfig(req)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": resp})
}

// handleKMSConfig routes to GET or POST handlers
func (s *Server) handleKMSConfig(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleKMSConfigGet(w, r)
	case http.MethodPost:
		s.handleKMSConfigSet(w, r)
	default:
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
	}
}
