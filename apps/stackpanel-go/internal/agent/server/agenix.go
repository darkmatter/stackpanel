package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
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

// handleAgenixSecretRead handles decrypting and reading a secret
// POST /api/secrets/read
//
// The secret is looked up by ID from the variables data, and its value
// (a vals reference like "ref+sops://...") is evaluated using `vals eval`.
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

	// Look up the variable by ID to get its vals reference
	valsRef, err := s.getVariableValue(req.ID)
	if err != nil {
		s.writeAPIError(w, http.StatusNotFound, "secret not found: "+err.Error())
		return
	}

	// Check if it's a vals reference (starts with "ref+")
	if !strings.HasPrefix(valsRef, "ref+") {
		// It's a literal value, just return it
		s.writeAPI(w, http.StatusOK, AgenixDecryptResponse{
			ID:    req.ID,
			Value: valsRef,
		})
		return
	}

	// Evaluate the vals reference using `vals eval`
	value, err := s.evalValsRef(valsRef)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to decrypt: "+err.Error())
		return
	}

	log.Info().
		Str("id", req.ID).
		Msg("Secret decrypted successfully")

	s.writeAPI(w, http.StatusOK, AgenixDecryptResponse{
		ID:    req.ID,
		Value: value,
	})
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

// evalValsRef evaluates a vals reference using `vals eval`
func (s *Server) evalValsRef(ref string) (string, error) {
	// Create a simple YAML document with the reference
	// Escape single quotes in the ref for shell safety
	escapedRef := strings.ReplaceAll(ref, "'", "'\"'\"'")
	input := fmt.Sprintf("value: %s", escapedRef)

	// Run vals eval via shell so we can pipe input and use devshell PATH
	// The executor handles devshell environment variables
	result, err := s.exec.RunWithOptions(
		"sh",
		s.config.ProjectRoot,
		nil,
		"-c",
		fmt.Sprintf("echo '%s' | vals eval -i -", input),
	)
	if err != nil {
		return "", fmt.Errorf("vals eval failed: %w", err)
	}
	if result.ExitCode != 0 {
		return "", fmt.Errorf("vals eval failed: %s", result.Stderr)
	}

	// Parse the output YAML
	var outputDoc struct {
		Value string `yaml:"value"`
	}
	if err := yaml.Unmarshal([]byte(result.Stdout), &outputDoc); err != nil {
		return "", fmt.Errorf("failed to parse vals output: %w", err)
	}

	return outputDoc.Value, nil
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

// handleAgenixSecretWrite handles writing a secret using age encryption
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
	if strings.TrimSpace(req.ID) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "id is required")
		return
	}
	if strings.TrimSpace(req.Key) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "key is required")
		return
	}

	// Sanitize ID for use as filename
	safeID := sanitizeSecretID(req.ID)
	if safeID == "" {
		s.writeAPIError(w, http.StatusBadRequest, "invalid secret id")
		return
	}

	// Get recipients (public keys) from users
	recipients, err := s.getAgenixRecipients(req.Environments)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	if len(recipients) == 0 {
		s.writeAPIError(w, http.StatusBadRequest, "no recipients found - ensure users have public-keys defined")
		return
	}

	// Ensure secrets directory exists
	secretsDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "vars")
	if err := os.MkdirAll(secretsDir, 0o755); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to create secrets directory: "+err.Error())
		return
	}

	// Write the secret using age
	agePath := filepath.Join(secretsDir, safeID+".age")
	if err := s.writeAgeSecret(agePath, req.Value, recipients); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to write secret: "+err.Error())
		return
	}

	// Update variables.nix with the secret metadata (not the value)
	if err := s.updateVariableEntry(req.ID, req.Key, req.Description, req.Environments); err != nil {
		log.Warn().Err(err).Msg("Failed to update variables.nix")
		// Don't fail the request - the secret was written successfully
	}

	// Update the secrets.nix file for agenix
	if err := s.updateSecretsNix(); err != nil {
		log.Warn().Err(err).Msg("Failed to update secrets.nix")
	}

	relPath, _ := filepath.Rel(s.config.ProjectRoot, agePath)

	log.Info().
		Str("id", req.ID).
		Str("key", req.Key).
		Str("path", relPath).
		Int("recipients", len(recipients)).
		Msg("Secret written successfully")

	s.writeAPI(w, http.StatusOK, AgenixSecretResponse{
		ID:       req.ID,
		Path:     relPath,
		AgePath:  agePath,
		KeyCount: len(recipients),
	})
}

// handleAgenixSecretDelete handles deleting an age-encrypted secret
// DELETE /api/secrets/delete?id=<id>
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

	safeID := sanitizeSecretID(id)
	if safeID == "" {
		s.writeAPIError(w, http.StatusBadRequest, "invalid secret id")
		return
	}

	// Delete the .age file
	agePath := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "vars", safeID+".age")
	if err := os.Remove(agePath); err != nil && !os.IsNotExist(err) {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to delete secret file: "+err.Error())
		return
	}

	// Remove from variables.nix
	if err := s.removeVariableEntry(id); err != nil {
		log.Warn().Err(err).Msg("Failed to remove from variables.nix")
	}

	// Update secrets.nix
	if err := s.updateSecretsNix(); err != nil {
		log.Warn().Err(err).Msg("Failed to update secrets.nix")
	}

	log.Info().Str("id", id).Msg("Secret deleted")
	s.writeAPI(w, http.StatusOK, map[string]any{"deleted": true, "id": id})
}

// handleAgenixSecretsList lists all age-encrypted secrets
// GET /api/secrets/list
func (s *Server) handleAgenixSecretsList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	secretsDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "vars")

	entries, err := os.ReadDir(secretsDir)
	if err != nil {
		if os.IsNotExist(err) {
			s.writeAPI(w, http.StatusOK, map[string]any{"secrets": []string{}})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, "failed to read secrets directory: "+err.Error())
		return
	}

	var secrets []map[string]any
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".age") {
			continue
		}

		id := strings.TrimSuffix(entry.Name(), ".age")
		info, _ := entry.Info()

		secret := map[string]any{
			"id":   id,
			"file": entry.Name(),
		}
		if info != nil {
			secret["modTime"] = info.ModTime().Unix()
			secret["size"] = info.Size()
		}
		secrets = append(secrets, secret)
	}

	s.writeAPI(w, http.StatusOK, map[string]any{"secrets": secrets})
}

// getAgenixRecipients returns the list of age/SSH public keys for encryption
func (s *Server) getAgenixRecipients(environments []string) ([]string, error) {
	// Try multiple user sources in order of priority:
	// 1. .stackpanel/data/external/users.nix (auto-synced from GitHub)
	// 2. .stackpanel/data/users.nix (manual user definitions)
	// 3. .stackpanel/secrets/users.yaml (legacy YAML format)

	userPaths := []string{
		filepath.Join(s.config.ProjectRoot, ".stackpanel", "data", "external", "users.nix"),
		filepath.Join(s.config.ProjectRoot, ".stackpanel", "data", "users.nix"),
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

	// Fall back to YAML if no Nix users found
	if allUsers == nil || len(allUsers) == 0 {
		return s.getAgenixRecipientsFromYAML()
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

// getAgenixRecipientsFromYAML falls back to reading users.yaml
func (s *Server) getAgenixRecipientsFromYAML() ([]string, error) {
	// Try the old YAML format as fallback
	usersPath := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "users.yaml")
	content, err := os.ReadFile(usersPath)
	if err != nil {
		return nil, fmt.Errorf("no users found: %w", err)
	}

	// Parse as simple key: {pubkey: ...} format
	var users map[string]struct {
		Pubkey string `yaml:"pubkey"`
	}
	if err := yaml.Unmarshal(content, &users); err != nil {
		return nil, fmt.Errorf("failed to parse users.yaml: %w", err)
	}

	var recipients []string
	for _, u := range users {
		key := strings.TrimSpace(u.Pubkey)
		// Accept both AGE keys and SSH ed25519 keys
		if strings.HasPrefix(key, "age1") || strings.HasPrefix(key, "ssh-ed25519 ") {
			recipients = append(recipients, key)
		}
	}

	return recipients, nil
}

// getSystemKeys returns system-level AGE keys (CI, deploy servers, etc.)
func (s *Server) getSystemKeys() []string {
	// Read from secrets config
	configPath := filepath.Join(s.config.ProjectRoot, ".stackpanel", "data", "secrets.nix")

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

// updateVariableEntry updates the variables.nix file with secret metadata
func (s *Server) updateVariableEntry(id, key, description string, environments []string) error {
	dataPath := filepath.Join(s.config.ProjectRoot, ".stackpanel", "data", "variables.nix")

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
	dataPath := filepath.Join(s.config.ProjectRoot, ".stackpanel", "data", "variables.nix")

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

// updateSecretsNix generates/updates the secrets.nix file for agenix
func (s *Server) updateSecretsNix() error {
	secretsDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "vars")
	secretsNixPath := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "secrets.nix")

	// List all .age files
	entries, err := os.ReadDir(secretsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}

	// Get all recipients
	recipients, err := s.getAgenixRecipients(nil)
	if err != nil {
		recipients = []string{}
	}

	// Build secrets.nix content
	var sb strings.Builder
	sb.WriteString("# Auto-generated by StackPanel - do not edit manually\n")
	sb.WriteString("# This file defines public keys for agenix secret encryption\n")
	sb.WriteString("let\n")
	sb.WriteString("  # All recipients who can decrypt secrets\n")
	sb.WriteString("  allKeys = [\n")
	for _, r := range recipients {
		sb.WriteString(fmt.Sprintf("    %q\n", r))
	}
	sb.WriteString("  ];\n")
	sb.WriteString("in\n")
	sb.WriteString("{\n")

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".age") {
			continue
		}
		// Use relative path from secrets.nix location
		relPath := filepath.Join("vars", entry.Name())
		sb.WriteString(fmt.Sprintf("  %q.publicKeys = allKeys;\n", relPath))
	}

	sb.WriteString("}\n")

	// Write the file
	if err := os.MkdirAll(filepath.Dir(secretsNixPath), 0o755); err != nil {
		return err
	}

	return os.WriteFile(secretsNixPath, []byte(sb.String()), 0o644)
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

// getAgeIdentityPath returns the path to the age identity state file
func (s *Server) getAgeIdentityPath() string {
	stateDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "state")
	return filepath.Join(stateDir, ageIdentityFileName)
}

// getAgeIdentityKeyPath returns the path to the actual key file (for key content storage)
func (s *Server) getAgeIdentityKeyPath() string {
	stateDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "state")
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

	stateDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "state")
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
	stateDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "state")
	return filepath.Join(stateDir, kmsConfigFileName)
}

// handleKMSConfigGet reads the current KMS configuration
func (s *Server) handleKMSConfigGet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	configFile := s.getKMSConfigPath()
	resp := KMSConfigResponse{
		Enable:     false,
		KeyArn:     "",
		AwsProfile: "",
		Source:     "",
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		if os.IsNotExist(err) {
			// No state config - return empty (could try reading from Nix config here)
			s.writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": resp})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to read KMS config: %v", err))
		return
	}

	if err := json.Unmarshal(data, &resp); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to parse KMS config: %v", err))
		return
	}

	resp.Source = "state"
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

	stateDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "state")
	if err := os.MkdirAll(stateDir, 0700); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to create state dir: %v", err))
		return
	}

	configFile := s.getKMSConfigPath()

	// Validate KMS ARN format if provided
	if req.Enable && req.KeyArn != "" {
		if !strings.HasPrefix(req.KeyArn, "arn:aws:kms:") {
			s.writeAPIError(w, http.StatusBadRequest, "Invalid KMS ARN format - must start with arn:aws:kms:")
			return
		}
	}

	resp := KMSConfigResponse{
		Enable:     req.Enable,
		KeyArn:     req.KeyArn,
		AwsProfile: req.AwsProfile,
		Source:     "state",
	}

	if !req.Enable && req.KeyArn == "" {
		// Disable - remove the config file
		os.Remove(configFile)
		resp.Source = ""
		log.Info().Msg("KMS config cleared")
	} else {
		// Save the config
		data, err := json.MarshalIndent(resp, "", "  ")
		if err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to marshal config: %v", err))
			return
		}
		if err := os.WriteFile(configFile, data, 0600); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to write config: %v", err))
			return
		}
		log.Info().Bool("enable", req.Enable).Str("keyArn", req.KeyArn).Msg("KMS config saved")
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
