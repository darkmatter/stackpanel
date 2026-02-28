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

	// ValsRef is the vals reference to use in app configs
	// For source project: ref+sops://<secrets-dir>/vars/<group>.sops.yaml#/<key>
	// For env package: ref+sops://vars/<group>.sops.yaml#/<key>
	ValsRef string `json:"valsRef"`

	// EnvPackageRef is the vals reference for use in the deployed env package
	// This uses relative paths: ref+sops://vars/<group>.sops.yaml#/<key>
	EnvPackageRef string `json:"envPackageRef"`

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
	SecretsDir    string `json:"secretsDir"`    // e.g., ".stackpanel/secrets"
	VarsSubdir    string `json:"varsSubdir"`    // e.g., "vars" (relative to secretsDir)
	EnvPackageDir string `json:"envPackageDir"` // e.g., "packages/env/data"
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
				SecretsDir:    serializable.SecretsDir,
				VarsSubdir:    "vars",
				EnvPackageDir: "packages/env/data",
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
				SecretsDir:    secretsDir,
				VarsSubdir:    "vars",
				EnvPackageDir: "packages/env/data",
			}, nil
		}
	}

	// Fall back to defaults
	return &SecretsConfig{
		SecretsDir:    ".stackpanel/secrets",
		VarsSubdir:    "vars",
		EnvPackageDir: "packages/env/data",
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

// buildValsRef builds a vals reference for a secret in a group
// The path is relative to the project root (for use in source configs)
func (s *Server) buildValsRef(group, key string) (string, error) {
	cfg, err := s.getSecretsConfig()
	if err != nil {
		return "", err
	}
	// Path relative to project root
	relPath := filepath.Join(cfg.SecretsDir, cfg.VarsSubdir, group+".sops.yaml")
	return fmt.Sprintf("ref+sops://%s#/%s", relPath, key), nil
}

// buildEnvPackageRef builds a vals reference for the deployed env package
// This uses paths relative to the env package data directory
func buildEnvPackageRef(group, key string) string {
	// In the env package, vars are at ./vars/<group>.sops.yaml
	return fmt.Sprintf("ref+sops://vars/%s.sops.yaml#/%s", group, key)
}

// getGroupRecipients gets the AGE public keys for a group from the Nix config
func (s *Server) getGroupRecipients(group string) ([]string, error) {
	// First, try to get group-specific recipients from the Nix evaluation
	args := []string{
		"eval", "--impure", "--json",
		fmt.Sprintf(".#stackpanelFullConfig.secrets.groups.%s.recipients or []", group),
	}
	res, err := s.exec.RunNix(args...)
	if err == nil && res.ExitCode == 0 {
		var recipients []string
		if err := json.Unmarshal([]byte(res.Stdout), &recipients); err == nil && len(recipients) > 0 {
			return recipients, nil
		}
	}

	// Fall back to all-public-keys from master keys
	args = []string{
		"eval", "--impure", "--json",
		".#stackpanelFullConfig.secrets.all-public-keys",
	}
	res, err = s.exec.RunNix(args...)
	if err == nil && res.ExitCode == 0 {
		var recipients []string
		if err := json.Unmarshal([]byte(res.Stdout), &recipients); err == nil && len(recipients) > 0 {
			return recipients, nil
		}
	}

	// Fall back to users.yaml
	return s.getAgenixRecipientsFromYAML()
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

	// Decrypt with SOPS
	relPath, _ := filepath.Rel(s.config.ProjectRoot, groupPath)
	res, err := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, "--decrypt", relPath)
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

// writeGroupSecrets encrypts and writes secrets to a group's SOPS file
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

	// Write to temp file
	tmp, err := os.CreateTemp("", "stackpanel-group-*.yaml")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)

	if err := os.WriteFile(tmpPath, plainBytes, 0o600); err != nil {
		tmp.Close()
		return fmt.Errorf("failed to write temp file: %w", err)
	}
	tmp.Close()

	// Encrypt with SOPS using explicit AGE recipients
	args := []string{"--encrypt", "--input-type", "yaml", "--output-type", "yaml"}
	for _, r := range recipients {
		args = append(args, "--age", r)
	}
	args = append(args, tmpPath)

	enc, err := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, args...)
	if err != nil {
		return fmt.Errorf("failed to run sops: %w", err)
	}
	if enc.ExitCode != 0 {
		return fmt.Errorf("sops encrypt failed: %s", strings.TrimSpace(enc.Stderr))
	}

	// Write encrypted content
	if err := os.WriteFile(groupPath, []byte(enc.Stdout), 0o644); err != nil {
		return fmt.Errorf("failed to write group file: %w", err)
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

	// Build the vals references
	valsRef, err := s.buildValsRef(safeGroup, req.Key)
	if err != nil {
		valsRef = buildEnvPackageRef(safeGroup, req.Key) // Fall back to relative ref
	}
	envPackageRef := buildEnvPackageRef(safeGroup, req.Key)

	groupPath, _ := s.getGroupFilePath(safeGroup)
	relPath, _ := filepath.Rel(s.config.ProjectRoot, groupPath)

	log.Info().
		Str("key", req.Key).
		Str("group", safeGroup).
		Str("path", relPath).
		Str("valsRef", valsRef).
		Str("envPackageRef", envPackageRef).
		Int("recipients", len(recipients)).
		Msg("Secret written to group")

	s.writeAPI(w, http.StatusOK, GroupSecretResponse{
		Key:            req.Key,
		Group:          safeGroup,
		Path:           relPath,
		ValsRef:        valsRef,
		EnvPackageRef:  envPackageRef,
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
type EnvPackageData struct {
	Apps   map[string]map[string]map[string]string `json:"apps"`   // app -> env -> key -> valsRef
	Groups []string                                `json:"groups"` // list of group names
}

// handleGenerateEnvPackage generates the packages/env data directory
// POST /api/secrets/generate-env-package
//
// The generated structure uses RELATIVE vals references so it's portable:
//
//	packages/env/data/
//	├── .sops.yaml           # SOPS config
//	├── apps/<app>/<env>.yaml  # Plain YAML with vals refs: ref+sops://vars/<group>.sops.yaml#/<key>
//	└── vars/<group>.sops.yaml # SOPS-encrypted files (copied from source)
func (s *Server) handleGenerateEnvPackage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	cfg, err := s.getSecretsConfig()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to get secrets config: "+err.Error())
		return
	}

	// Get apps configuration from Nix
	args := []string{"eval", "--impure", "--json", ".#stackpanelFullConfig.apps"}
	res, err := s.exec.RunNix(args...)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to evaluate apps config: "+err.Error())
		return
	}
	if res.ExitCode != 0 {
		s.writeAPIError(w, http.StatusInternalServerError, "nix eval failed: "+res.Stderr)
		return
	}

	var apps map[string]struct {
		Environments map[string]struct {
			Name string            `json:"name"`
			Env  map[string]string `json:"env"`
		} `json:"environments"`
	}
	if err := json.Unmarshal([]byte(res.Stdout), &apps); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse apps config: "+err.Error())
		return
	}

	// Build the env package data directory
	envPkgDir := filepath.Join(s.config.ProjectRoot, cfg.EnvPackageDir)
	if err := os.MkdirAll(envPkgDir, 0o755); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to create env package directory: "+err.Error())
		return
	}

	// Create apps directory structure with vals references
	// These refs are RELATIVE to the env package: ref+sops://vars/<group>.sops.yaml#/<key>
	appsDir := filepath.Join(envPkgDir, "apps")
	if err := os.MkdirAll(appsDir, 0o755); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to create apps directory: "+err.Error())
		return
	}

	for appName, app := range apps {
		appDir := filepath.Join(appsDir, appName)
		if err := os.MkdirAll(appDir, 0o755); err != nil {
			continue
		}

		for envName, env := range app.Environments {
			if len(env.Env) == 0 {
				continue
			}

			// Transform source vals refs to relative refs for the env package
			transformedEnv := make(map[string]string)
			for key, value := range env.Env {
				transformedEnv[key] = s.transformValsRefForEnvPackage(value)
			}

			// Write the env YAML with transformed vals references (NOT encrypted)
			envPath := filepath.Join(appDir, envName+".yaml")
			envData, _ := yaml.Marshal(transformedEnv)
			header := fmt.Sprintf("# %s/%s environment variables\n# Contains vals references - resolved at runtime by vals\n# Refs are relative to this data directory\n", appName, envName)
			if err := os.WriteFile(envPath, []byte(header+string(envData)), 0o644); err != nil {
				log.Warn().Err(err).Str("path", envPath).Msg("Failed to write env file")
			}
		}
	}

	// Copy vars directory (SOPS-encrypted files)
	srcGroupsDir := filepath.Join(s.config.ProjectRoot, cfg.SecretsDir, cfg.VarsSubdir)
	dstGroupsDir := filepath.Join(envPkgDir, "vars")
	if err := os.MkdirAll(dstGroupsDir, 0o755); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to create groups directory: "+err.Error())
		return
	}

	var copiedGroups []string
	if entries, err := os.ReadDir(srcGroupsDir); err == nil {
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sops.yaml") {
				continue
			}

			srcPath := filepath.Join(srcGroupsDir, entry.Name())
			dstPath := filepath.Join(dstGroupsDir, entry.Name())

			content, err := os.ReadFile(srcPath)
			if err != nil {
				log.Warn().Err(err).Str("path", srcPath).Msg("Failed to read group file")
				continue
			}

			if err := os.WriteFile(dstPath, content, 0o644); err != nil {
				log.Warn().Err(err).Str("path", dstPath).Msg("Failed to write group file")
				continue
			}

			groupName := strings.TrimSuffix(entry.Name(), ".sops.yaml")
			copiedGroups = append(copiedGroups, groupName)
		}
	}

	// Generate .sops.yaml for the env package
	sopsConfig := s.generateEnvPackageSopsConfig(copiedGroups)
	sopsPath := filepath.Join(envPkgDir, ".sops.yaml")
	if err := os.WriteFile(sopsPath, []byte(sopsConfig), 0o644); err != nil {
		log.Warn().Err(err).Msg("Failed to write .sops.yaml")
	}

	log.Info().
		Int("apps", len(apps)).
		Int("groups", len(copiedGroups)).
		Str("path", envPkgDir).
		Msg("Generated env package data")

	s.writeAPI(w, http.StatusOK, map[string]interface{}{
		"path":   envPkgDir,
		"apps":   len(apps),
		"groups": copiedGroups,
	})
}

// transformValsRefForEnvPackage converts a source vals ref to a relative ref for the env package
// Source: ref+sops://.stackpanel/secrets/vars/dev.sops.yaml#/KEY
// Output: ref+sops://vars/dev.sops.yaml#/KEY
func (s *Server) transformValsRefForEnvPackage(value string) string {
	if !strings.HasPrefix(value, "ref+sops://") {
		return value
	}

	// Parse the vals ref
	// Format: ref+sops://<path>#/<key>
	parts := strings.SplitN(value, "#", 2)
	if len(parts) != 2 {
		return value
	}

	pathPart := strings.TrimPrefix(parts[0], "ref+sops://")
	keyPart := parts[1]

	// Check if this is a vars reference
	cfg, _ := s.getSecretsConfig()
	varsPath := filepath.Join(cfg.SecretsDir, cfg.VarsSubdir)

	if strings.HasPrefix(pathPart, varsPath+"/") {
		// Extract just the filename
		filename := filepath.Base(pathPart)
		return fmt.Sprintf("ref+sops://vars/%s#%s", filename, keyPart)
	}

	// For other refs, try to make them relative to vars/
	if strings.Contains(pathPart, "/vars/") {
		idx := strings.LastIndex(pathPart, "/vars/")
		filename := pathPart[idx+len("/vars/"):]
		return fmt.Sprintf("ref+sops://vars/%s#%s", filename, keyPart)
	}

	// Return as-is if we can't transform it
	return value
}

// generateEnvPackageSopsConfig generates a .sops.yaml for the env package
func (s *Server) generateEnvPackageSopsConfig(groups []string) string {
	var sb strings.Builder

	sb.WriteString("# Auto-generated SOPS config for packages/env\n")
	sb.WriteString("# Regenerate with: stackpanel secrets:generate-env-package\n")
	sb.WriteString("#\n")
	sb.WriteString("# Paths are relative to this directory (packages/env/data/)\n\n")

	// Get all public keys
	args := []string{"eval", "--impure", "--json", ".#stackpanelFullConfig.secrets.all-public-keys"}
	res, _ := s.exec.RunNix(args...)

	var pubKeys []string
	if res != nil && res.ExitCode == 0 {
		json.Unmarshal([]byte(res.Stdout), &pubKeys)
	}

	// Define keys section
	sb.WriteString("keys:\n")
	for i, key := range pubKeys {
		sb.WriteString(fmt.Sprintf("  - &key%d %s\n", i, key))
	}
	sb.WriteString("\n")

	// Creation rules
	sb.WriteString("creation_rules:\n")

	// Apps directory is NOT encrypted (contains only vals references)
	sb.WriteString("  # Apps contain vals references, not actual secrets\n")
	sb.WriteString("  - path_regex: ^apps/.*\\.yaml$\n")
	sb.WriteString("    unencrypted_regex: \".*\"\n\n")

	// Vars directory IS encrypted
	sb.WriteString("  # Vars contain encrypted secret values\n")
	for _, group := range groups {
		sb.WriteString(fmt.Sprintf("  - path_regex: ^vars/%s\\.sops\\.yaml$\n", group))
		sb.WriteString("    key_groups:\n")
		sb.WriteString("      - age:\n")
		for i := range pubKeys {
			sb.WriteString(fmt.Sprintf("          - *key%d\n", i))
		}
	}

	// Fallback rule
	sb.WriteString("\n  # Fallback for any other yaml files\n")
	sb.WriteString("  - path_regex: .*\\.yaml$\n")
	sb.WriteString("    key_groups:\n")
	sb.WriteString("      - age:\n")
	for i := range pubKeys {
		sb.WriteString(fmt.Sprintf("          - *key%d\n", i))
	}

	return sb.String()
}
