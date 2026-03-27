// secrets_groups.go implements group-based SOPS secret management.
//
// Secrets are organized into groups (typically matching environments: dev, staging, prod).
// Each group maps to a single SOPS-encrypted YAML file at:
//
//	.stack/secrets/vars/<group>.sops.yaml
//
// Groups have configured recipients (AGE public keys) from the Nix secrets config,
// which determine who can decrypt secrets in that group.
// Key names follow chamber-style conventions: lowercase alphanumeric + hyphens.
package server

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// secretKeyPattern enforces chamber-style naming: lowercase alphanumeric + hyphens,
// must start with a letter or digit. No slashes, no uppercase.
var secretKeyPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)

// isValidSecretKey checks if a secret key name follows chamber naming rules.
func isValidSecretKey(key string) bool {
	return secretKeyPattern.MatchString(key)
}

// GroupSecretRequest represents a request to write a secret to a group's SOPS file
type GroupSecretRequest struct {
	// Key is the secret key name (e.g., DATABASE_URL)
	Key string `json:"key"`

	// Value is the plaintext secret value to encrypt
	Value string `json:"value"`

	// Group is the access control group (e.g., "dev", "prod", "ops")
	// Determines which SOPS file the secret is stored in
	Group string `json:"group"`

	// Description is an optional description of the secret
	Description string `json:"description,omitempty"`
}

// GroupSecretResponse is the response after writing a secret to a group
type GroupSecretResponse struct {
	// Key is the secret key that was written
	Key string `json:"key"`

	// Group is the group the secret was written to
	Group string `json:"group"`

	// Path is the relative path to the SOPS file (from project root)
	Path string `json:"path"`

	// RecipientCount is the number of AGE recipients the file is encrypted to
	RecipientCount int `json:"recipientCount"`
}

// GroupSecretReadRequest represents a request to read a secret from a group
type GroupSecretReadRequest struct {
	// Key is the secret key to read
	Key string `json:"key"`

	// Group is the access control group
	Group string `json:"group"`
}

// GroupSecretReadResponse is the response after reading a secret
type GroupSecretReadResponse struct {
	Key   string `json:"key"`
	Group string `json:"group"`
	Value string `json:"value"`
}

// SecretsConfig holds paths and settings from Nix config
type SecretsConfig struct {
	SecretsDir string `json:"secretsDir"` // e.g., ".stack/secrets"
	VarsSubdir string `json:"varsSubdir"` // e.g., "vars" (relative to secretsDir)
}

type SerializableSecretsConfig struct {
	SecretsDir     string `json:"secretsDir"`
	SopsConfigFile string `json:"sopsConfigFile,omitempty"`
	Recipients     map[string]struct {
		PublicKey string   `json:"publicKey"`
		Tags      []string `json:"tags,omitempty"`
	} `json:"recipients,omitempty"`
	Variables map[string]struct {
		File       string   `json:"file,omitempty"`
		YamlKey    string   `json:"yamlKey,omitempty"`
		Tags       []string `json:"tags,omitempty"`
		Recipients []string `json:"recipients,omitempty"`
	} `json:"variables,omitempty"`
	RecipientGroups map[string]struct {
		Recipients []string `json:"recipients,omitempty"`
	} `json:"recipientGroups,omitempty"`
	CreationRules []struct {
		PathRegex               string   `json:"pathRegex,omitempty"`
		Recipients              []string `json:"recipients,omitempty"`
		DirectRecipients        []string `json:"directRecipients,omitempty"`
		RecipientGroups         []string `json:"recipientGroups,omitempty"`
		UnencryptedCommentRegex string   `json:"unencryptedCommentRegex,omitempty"`
	} `json:"creationRules,omitempty"`
	Groups map[string]struct {
		Tags       []string `json:"tags,omitempty"`
		Recipients []string `json:"recipients,omitempty"`
	} `json:"groups,omitempty"`
}

// getSerializableSecretsConfig evaluates the Nix flake to get the full secrets
// configuration including recipients, groups, variables, and creation rules.
// This is the source of truth for who can encrypt/decrypt which groups.
func (s *Server) getSerializableSecretsConfig() (*SerializableSecretsConfig, error) {
	args := []string{
		"eval", "--impure", "--json",
		".#stackpanelFullConfig.serializable.secrets",
	}
	res, err := s.exec.RunNix(args...)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate secrets config: %w", err)
	}
	if res.ExitCode != 0 {
		return nil, fmt.Errorf("failed to evaluate secrets config: %s", strings.TrimSpace(res.Stderr))
	}

	var serializable SerializableSecretsConfig
	if err := json.Unmarshal([]byte(res.Stdout), &serializable); err != nil {
		return nil, fmt.Errorf("failed to parse secrets config: %w", err)
	}
	if serializable.Recipients == nil {
		serializable.Recipients = map[string]struct {
			PublicKey string   `json:"publicKey"`
			Tags      []string `json:"tags,omitempty"`
		}{}
	}
	if serializable.Variables == nil {
		serializable.Variables = map[string]struct {
			File       string   `json:"file,omitempty"`
			YamlKey    string   `json:"yamlKey,omitempty"`
			Tags       []string `json:"tags,omitempty"`
			Recipients []string `json:"recipients,omitempty"`
		}{}
	}
	if serializable.RecipientGroups == nil {
		serializable.RecipientGroups = map[string]struct {
			Recipients []string `json:"recipients,omitempty"`
		}{}
	}
	if serializable.Groups == nil {
		serializable.Groups = map[string]struct {
			Tags       []string `json:"tags,omitempty"`
			Recipients []string `json:"recipients,omitempty"`
		}{}
	}
	return &serializable, nil
}

// getVariableSecretMeta looks up Nix-computed metadata for a variable,
// returning file path and YAML key overrides if configured.
func (s *Server) getVariableSecretMeta(variableID string) (struct {
	File       string
	YamlKey    string
	Tags       []string
	Recipients []string
}, bool, error) {
	serializable, err := s.getSerializableSecretsConfig()
	if err != nil {
		return struct {
			File       string
			YamlKey    string
			Tags       []string
			Recipients []string
		}{}, false, err
	}
	meta, ok := serializable.Variables[variableID]
	return struct {
		File       string
		YamlKey    string
		Tags       []string
		Recipients []string
	}{
		File:       meta.File,
		YamlKey:    meta.YamlKey,
		Tags:       meta.Tags,
		Recipients: meta.Recipients,
	}, ok, nil
}

// getSecretsConfig reads secrets configuration from Nix
func (s *Server) getSecretsConfig() (*SecretsConfig, error) {
	// Try to get config from Nix evaluation
	args := []string{
		"eval", "--impure", "--json",
		".#stackpanelFullConfig.serializable.secrets",
	}
	res, err := s.exec.RunNix(args...)
	if err == nil && res.ExitCode == 0 {
		var serializable struct {
			SecretsDir string `json:"secretsDir"`
		}
		if err := json.Unmarshal([]byte(res.Stdout), &serializable); err == nil && serializable.SecretsDir != "" {
			return &SecretsConfig{
				SecretsDir: serializable.SecretsDir,
				VarsSubdir: "vars",
			}, nil
		}
	}

	// Try alternate path
	args = []string{
		"eval", "--impure", "--json",
		".#stackpanelFullConfig.secrets.secrets-dir",
	}
	res, err = s.exec.RunNix(args...)
	if err == nil && res.ExitCode == 0 {
		var secretsDir string
		if err := json.Unmarshal([]byte(res.Stdout), &secretsDir); err == nil && secretsDir != "" {
			return &SecretsConfig{
				SecretsDir: secretsDir,
				VarsSubdir: "vars",
			}, nil
		}
	}

	// Fall back to defaults
	return &SecretsConfig{
		SecretsDir: ".stack/secrets",
		VarsSubdir: "vars",
	}, nil
}

// getGroupsDir returns the absolute path to the groups directory
func (s *Server) getGroupsDir() (string, error) {
	cfg, err := s.getSecretsConfig()
	if err != nil {
		return "", err
	}
	return filepath.Join(s.config.ProjectRoot, cfg.SecretsDir, cfg.VarsSubdir), nil
}

// getGroupFilePath returns the absolute path to a group's SOPS file
func (s *Server) getGroupFilePath(group string) (string, error) {
	// Sanitize group name to prevent path traversal
	safeGroup := sanitizeSecretID(group)
	if safeGroup == "" {
		return "", errors.New("invalid group name")
	}
	groupsDir, err := s.getGroupsDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(groupsDir, safeGroup+".sops.yaml"), nil
}

// getGroupRecipients gets the configured public keys for a group from Nix.
func (s *Server) getGroupRecipients(group string) ([]string, error) {
	serializable, err := s.getSerializableSecretsConfig()
	if err != nil {
		return nil, err
	}
	groupCfg, ok := serializable.Groups[group]
	if !ok {
		return nil, fmt.Errorf("group %q not found in secrets config", group)
	}

	publicKeys := make([]string, 0, len(groupCfg.Recipients))
	seen := make(map[string]struct{}, len(groupCfg.Recipients))
	for _, recipientName := range groupCfg.Recipients {
		recipient, ok := serializable.Recipients[recipientName]
		if !ok {
			continue
		}
		publicKey := strings.TrimSpace(recipient.PublicKey)
		if publicKey == "" {
			continue
		}
		if _, exists := seen[publicKey]; exists {
			continue
		}
		seen[publicKey] = struct{}{}
		publicKeys = append(publicKeys, publicKey)
	}
	if len(publicKeys) > 0 {
		return publicKeys, nil
	}

	return nil, fmt.Errorf("no recipients configured for group %q", group)
}

// readGroupSecrets reads and decrypts a group's SOPS file
func (s *Server) readGroupSecrets(group string) (map[string]interface{}, error) {
	groupPath, err := s.getGroupFilePath(group)
	if err != nil {
		return nil, err
	}

	// Check if file exists
	if _, err := os.Stat(groupPath); os.IsNotExist(err) {
		return make(map[string]interface{}), nil
	}

	// Decrypt with SOPS — use the absolute path so --config lookup is consistent
	res, err := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, s.sopsDecryptArgs(groupPath)...)
	if err != nil {
		return nil, fmt.Errorf("failed to run sops: %w", err)
	}
	if res.ExitCode != 0 {
		return nil, fmt.Errorf("sops decrypt failed: %s", strings.TrimSpace(res.Stderr))
	}

	var secrets map[string]interface{}
	if err := yaml.Unmarshal([]byte(res.Stdout), &secrets); err != nil {
		return nil, fmt.Errorf("failed to parse decrypted YAML: %w", err)
	}

	return secrets, nil
}

// sopsConfigPath returns the absolute path to the generated .sops.yaml if it exists.
// Checks .stack/secrets/.sops.yaml first (Nix-generated), then project root.
func (s *Server) sopsConfigPath() string {
	candidates := []string{
		filepath.Join(s.config.ProjectRoot, ".stack", "secrets", ".sops.yaml"),
		filepath.Join(s.config.ProjectRoot, ".sops.yaml"),
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	return ""
}

// sopsEncryptArgs builds the base sops encrypt argument list, always injecting
// --config when the generated .sops.yaml exists so that sops doesn't fall back
// to CWD lookup and fail when encrypting temp files.
func (s *Server) sopsEncryptArgs(targetFile string) []string {
	args := []string{"--encrypt", "--in-place"}
	if cfg := s.sopsConfigPath(); cfg != "" {
		args = append(args, "--config", cfg)
	}
	args = append(args, targetFile)
	return args
}

// sopsDecryptArgs builds the base sops decrypt argument list with --config injection.
func (s *Server) sopsDecryptArgs(targetFile string) []string {
	args := []string{"--decrypt"}
	if cfg := s.sopsConfigPath(); cfg != "" {
		args = append(args, "--config", cfg)
	}
	args = append(args, targetFile)
	return args
}

// writeGroupSecrets writes plaintext YAML to the group file path, then encrypts
// in-place using `sops --encrypt`. Writing to the final path first ensures SOPS
// can match the correct .sops.yaml creation rule by file path. On failure, the
// plaintext file is removed to prevent leaking secrets.
func (s *Server) writeGroupSecrets(group string, secrets map[string]interface{}, recipients []string) error {
	groupPath, err := s.getGroupFilePath(group)
	if err != nil {
		return err
	}

	// Ensure groups directory exists
	if err := os.MkdirAll(filepath.Dir(groupPath), 0o755); err != nil {
		return fmt.Errorf("failed to create groups directory: %w", err)
	}

	// Marshal to YAML
	plainBytes, err := yaml.Marshal(secrets)
	if err != nil {
		return fmt.Errorf("failed to marshal secrets: %w", err)
	}

	// Write plaintext to the destination first, then encrypt in-place.
	// This ensures sops can use the .sops.yaml creation rule matched by the file path.
	if err := os.WriteFile(groupPath, plainBytes, 0o600); err != nil {
		return fmt.Errorf("failed to write plain group file: %w", err)
	}

	enc, err := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, s.sopsEncryptArgs(groupPath)...)
	if err != nil {
		_ = os.Remove(groupPath)
		return fmt.Errorf("failed to run sops: %w", err)
	}
	if enc.ExitCode != 0 {
		_ = os.Remove(groupPath)
		return fmt.Errorf("sops encrypt failed: %s", strings.TrimSpace(enc.Stderr))
	}

	return nil
}

// handleGroupSecretWrite handles writing a secret to a group's SOPS file
// POST /api/secrets/group/write
func (s *Server) handleGroupSecretWrite(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req GroupSecretRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	// Validate request
	if strings.TrimSpace(req.Key) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "key is required")
		return
	}
	// Enforce chamber naming rules: lowercase alphanumeric + hyphens only
	if !isValidSecretKey(req.Key) {
		s.writeAPIError(w, http.StatusBadRequest,
			"invalid key name: must contain only lowercase letters, numbers, and hyphens, and start with a letter or number")
		return
	}
	if strings.TrimSpace(req.Group) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "group is required")
		return
	}

	// Sanitize group name
	safeGroup := sanitizeSecretID(req.Group)
	if safeGroup == "" {
		s.writeAPIError(w, http.StatusBadRequest, "invalid group name")
		return
	}

	// Get recipients for this group
	recipients, err := s.getGroupRecipients(safeGroup)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "failed to get recipients: "+err.Error())
		return
	}
	if len(recipients) == 0 {
		s.writeAPIError(w, http.StatusBadRequest, "no recipients found for group - ensure master keys are configured")
		return
	}

	// Read existing secrets for this group
	secrets, err := s.readGroupSecrets(safeGroup)
	if err != nil {
		log.Warn().Err(err).Str("group", safeGroup).Msg("Failed to read existing group secrets, starting fresh")
		secrets = make(map[string]interface{})
	}

	// Update the secret
	secrets[req.Key] = req.Value

	// Write back encrypted
	if err := s.writeGroupSecrets(safeGroup, secrets, recipients); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to write secret: "+err.Error())
		return
	}

	groupPath, _ := s.getGroupFilePath(safeGroup)
	relPath, _ := filepath.Rel(s.config.ProjectRoot, groupPath)

	log.Info().
		Str("key", req.Key).
		Str("group", safeGroup).
		Str("path", relPath).
		Int("recipients", len(recipients)).
		Msg("Secret written to group")

	s.writeAPI(w, http.StatusOK, GroupSecretResponse{
		Key:            req.Key,
		Group:          safeGroup,
		Path:           relPath,
		RecipientCount: len(recipients),
	})
}

// handleGroupSecretRead handles reading a secret from a group's SOPS file
// POST /api/secrets/group/read
func (s *Server) handleGroupSecretRead(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req GroupSecretReadRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	if strings.TrimSpace(req.Key) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "key is required")
		return
	}
	if !isValidSecretKey(req.Key) {
		s.writeAPIError(w, http.StatusBadRequest, "invalid key name: must be lowercase alphanumeric and hyphens only (e.g., 'database-url')")
		return
	}
	if strings.TrimSpace(req.Group) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "group is required")
		return
	}

	safeGroup := sanitizeSecretID(req.Group)
	if safeGroup == "" {
		s.writeAPIError(w, http.StatusBadRequest, "invalid group name")
		return
	}

	secrets, err := s.readGroupSecrets(safeGroup)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to decrypt group secrets: "+err.Error())
		return
	}

	value, exists := secrets[req.Key]
	if !exists {
		s.writeAPIError(w, http.StatusNotFound, "secret not found in group")
		return
	}

	s.writeAPI(w, http.StatusOK, GroupSecretReadResponse{
		Key:   req.Key,
		Group: safeGroup,
		Value: fmt.Sprintf("%v", value),
	})
}

// handleGroupSecretDelete handles deleting a secret from a group's SOPS file
// DELETE /api/secrets/group/delete
func (s *Server) handleGroupSecretDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	key := strings.TrimSpace(r.URL.Query().Get("key"))
	group := strings.TrimSpace(r.URL.Query().Get("group"))

	if key == "" {
		s.writeAPIError(w, http.StatusBadRequest, "key is required")
		return
	}
	if !isValidSecretKey(key) {
		s.writeAPIError(w, http.StatusBadRequest, "invalid key name: must be lowercase alphanumeric and hyphens only (e.g., 'database-url')")
		return
	}
	if group == "" {
		s.writeAPIError(w, http.StatusBadRequest, "group is required")
		return
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

	if _, exists := secrets[key]; !exists {
		s.writeAPIError(w, http.StatusNotFound, "secret not found in group")
		return
	}

	// Delete the key
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

	log.Info().
		Str("key", key).
		Str("group", safeGroup).
		Msg("Secret deleted from group")

	s.writeAPI(w, http.StatusOK, map[string]interface{}{
		"key":     key,
		"group":   safeGroup,
		"deleted": true,
	})
}

// handleGroupSecretsList lists all secrets in a group (keys only, not values)
// GET /api/secrets/group/list?group=<group>
func (s *Server) handleGroupSecretsList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	group := strings.TrimSpace(r.URL.Query().Get("group"))

	// If no group specified, list all groups and their keys
	if group == "" {
		s.handleListAllGroups(w, r)
		return
	}

	safeGroup := sanitizeSecretID(group)
	if safeGroup == "" {
		s.writeAPIError(w, http.StatusBadRequest, "invalid group name")
		return
	}

	secrets, err := s.readGroupSecrets(safeGroup)
	if err != nil {
		// If file doesn't exist, return empty list
		groupPath, _ := s.getGroupFilePath(safeGroup)
		if _, statErr := os.Stat(groupPath); os.IsNotExist(statErr) {
			s.writeAPI(w, http.StatusOK, map[string]interface{}{
				"group": safeGroup,
				"keys":  []string{},
			})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, "failed to decrypt group secrets: "+err.Error())
		return
	}

	keys := make([]string, 0, len(secrets))
	for k := range secrets {
		keys = append(keys, k)
	}

	s.writeAPI(w, http.StatusOK, map[string]interface{}{
		"group": safeGroup,
		"keys":  keys,
	})
}

// handleListAllGroups lists all groups and their secret keys
func (s *Server) handleListAllGroups(w http.ResponseWriter, r *http.Request) {
	groupsDir, err := s.getGroupsDir()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to get groups directory: "+err.Error())
		return
	}

	entries, err := os.ReadDir(groupsDir)
	if err != nil {
		if os.IsNotExist(err) {
			s.writeAPI(w, http.StatusOK, map[string]interface{}{
				"groups": map[string][]string{},
			})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, "failed to read groups directory: "+err.Error())
		return
	}

	groups := make(map[string][]string)

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sops.yaml") {
			continue
		}

		groupName := strings.TrimSuffix(entry.Name(), ".sops.yaml")
		secrets, err := s.readGroupSecrets(groupName)
		if err != nil {
			log.Warn().Err(err).Str("group", groupName).Msg("Failed to read group secrets")
			groups[groupName] = []string{}
			continue
		}

		keys := make([]string, 0, len(secrets))
		for k := range secrets {
			keys = append(keys, k)
		}
		groups[groupName] = keys
	}

	s.writeAPI(w, http.StatusOK, map[string]interface{}{
		"groups": groups,
	})
}

// EnvPackageData contains info about the generated env package
