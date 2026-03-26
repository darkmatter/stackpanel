// sops.go implements a legacy SOPS secrets API that operates on per-environment
// YAML files (e.g., .stack/secrets/dev.yaml). This predates the group-based
// system in secrets_groups.go and is kept for backwards compatibility.
// New code should prefer the group-based endpoints.
package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/rs/zerolog/log"
)

// SOPSSecret represents a secret in SOPS format
type SOPSSecret struct {
	Key         string `json:"key"`
	Value       string `json:"value"`
	Environment string `json:"environment"`
}

// SOPSFile represents a SOPS-encrypted file structure
type SOPSFile struct {
	Path    string                 `json:"path"`
	Secrets map[string]interface{} `json:"secrets"`
}

// handleSecretsRead handles reading SOPS-encrypted secrets
func (s *Server) handleSecretsRead(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	env := r.URL.Query().Get("environment")
	if env == "" {
		env = "dev"
	}

	// Construct path to secrets file
	secretsPath := filepath.Join(s.config.ProjectRoot, ".stack", "secrets", fmt.Sprintf("%s.yaml", env))

	// Check if file exists
	if _, err := os.Stat(secretsPath); os.IsNotExist(err) {
		s.writeJSON(w, http.StatusOK, apiResponse{
			Success: true,
			Data: map[string]interface{}{
				"exists":  false,
				"path":    secretsPath,
				"secrets": map[string]interface{}{},
			},
		})
		return
	}

	// Use sops to decrypt the file
	result, err := s.exec.Run("sops", "-d", "--output-type", "json", secretsPath)
	if err != nil {
		log.Error().Err(err).Str("path", secretsPath).Msg("Failed to run sops")
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to decrypt secrets: " + err.Error()})
		return
	}

	if result.ExitCode != 0 {
		// If sops fails, try to read the file as-is (might be unencrypted or have issues)
		content, readErr := os.ReadFile(secretsPath)
		if readErr != nil {
			s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to read secrets file"})
			return
		}

		s.writeJSON(w, http.StatusOK, apiResponse{
			Success: true,
			Data: map[string]interface{}{
				"exists":    true,
				"path":      secretsPath,
				"encrypted": true,
				"raw":       string(content),
				"error":     result.Stderr,
			},
		})
		return
	}

	// Parse the decrypted JSON
	var secrets map[string]interface{}
	if err := json.Unmarshal([]byte(result.Stdout), &secrets); err != nil {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to parse decrypted secrets"})
		return
	}

	s.writeJSON(w, http.StatusOK, apiResponse{
		Success: true,
		Data: map[string]interface{}{
			"exists":    true,
			"path":      secretsPath,
			"encrypted": true,
			"secrets":   secrets,
		},
	})
}

// SecretWriteRequest represents a request to write a secret
type SecretWriteRequest struct {
	Environment string `json:"environment"`
	Key         string `json:"key"`
	Value       string `json:"value"`
}

// handleSecretsWrite handles writing/updating SOPS-encrypted secrets
func (s *Server) handleSecretsWrite(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	var req SecretWriteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	if req.Environment == "" {
		req.Environment = "dev"
	}

	if req.Key == "" {
		s.writeAPIError(w, http.StatusBadRequest, "Secret key is required")
		return
	}

	// Construct path to secrets file
	secretsDir := filepath.Join(s.config.ProjectRoot, ".stack", "secrets")
	secretsPath := filepath.Join(secretsDir, fmt.Sprintf("%s.yaml", req.Environment))

	// Ensure directory exists
	if err := os.MkdirAll(secretsDir, 0755); err != nil {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to create secrets directory"})
		return
	}

	// Read existing secrets or create new file
	var secrets map[string]interface{}

	if _, err := os.Stat(secretsPath); !os.IsNotExist(err) {
		// File exists, decrypt it first
		result, err := s.exec.Run("sops", "-d", "--output-type", "json", secretsPath)
		if err == nil && result.ExitCode == 0 {
			if err := json.Unmarshal([]byte(result.Stdout), &secrets); err != nil {
				secrets = make(map[string]interface{})
			}
		} else {
			secrets = make(map[string]interface{})
		}
	} else {
		secrets = make(map[string]interface{})
	}

	// Update the secret
	secrets[req.Key] = req.Value

	// Write to temp file
	tempFile, err := os.CreateTemp("", "secrets-*.json")
	if err != nil {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to create temp file"})
		return
	}
	tempPath := tempFile.Name()
	defer os.Remove(tempPath)

	secretsJSON, err := json.MarshalIndent(secrets, "", "  ")
	if err != nil {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to marshal secrets"})
		return
	}

	if _, err := tempFile.Write(secretsJSON); err != nil {
		tempFile.Close()
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to write temp file"})
		return
	}
	tempFile.Close()

	// Encrypt with sops
	// First, check if .sops.yaml exists
	sopsConfigPath := filepath.Join(s.config.ProjectRoot, ".sops.yaml")
	var sopsArgs []string

	if _, err := os.Stat(sopsConfigPath); !os.IsNotExist(err) {
		// Use the config file
		sopsArgs = []string{"-e", "--input-type", "json", "--output-type", "yaml", tempPath}
	} else {
		// Try to get age recipients from users.yaml
		recipients := s.getAgeRecipients()
		if len(recipients) == 0 {
			s.writeJSON(w, http.StatusOK, apiResponse{
				Success: false,
				Error:   "No age recipients found. Ensure .stack/data/users.nix has public-keys defined, or configure .sops.yaml",
			})
			return
		}

		sopsArgs = []string{
			"-e",
			"--input-type", "json",
			"--output-type", "yaml",
			"--age", strings.Join(recipients, ","),
			tempPath,
		}
	}

	result, err := s.exec.Run("sops", sopsArgs...)
	if err != nil {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to run sops: " + err.Error()})
		return
	}

	if result.ExitCode != 0 {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to encrypt: " + result.Stderr})
		return
	}

	// Write encrypted content to the secrets file
	if err := os.WriteFile(secretsPath, []byte(result.Stdout), 0644); err != nil {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to write secrets file"})
		return
	}

	log.Info().
		Str("environment", req.Environment).
		Str("key", req.Key).
		Msg("Secret updated")

	s.writeJSON(w, http.StatusOK, apiResponse{
		Success: true,
		Data: map[string]interface{}{
			"path":        secretsPath,
			"environment": req.Environment,
			"key":         req.Key,
		},
	})
}

// getAgeRecipients collects recipient public keys, trying the Nix user-based
// system first and falling back to the serializable secrets config. Deduplicates keys.
func (s *Server) getAgeRecipients() []string {
	recipients, err := s.getAgenixRecipients(nil)
	if err != nil || len(recipients) == 0 {
		serializable, err := s.getSerializableSecretsConfig()
		if err == nil {
			keys := make([]string, 0, len(serializable.Recipients))
			seen := make(map[string]struct{}, len(serializable.Recipients))
			for _, recipient := range serializable.Recipients {
				key := strings.TrimSpace(recipient.PublicKey)
				if key == "" {
					continue
				}
				if _, exists := seen[key]; exists {
					continue
				}
				seen[key] = struct{}{}
				keys = append(keys, key)
			}
			return keys
		}
		return nil
	}
	return recipients
}

// handleSecretsDelete handles deleting a secret
func (s *Server) handleSecretsDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	env := r.URL.Query().Get("environment")
	key := r.URL.Query().Get("key")

	if env == "" {
		env = "dev"
	}

	if key == "" {
		s.writeAPIError(w, http.StatusBadRequest, "Secret key is required")
		return
	}

	secretsPath := filepath.Join(s.config.ProjectRoot, ".stack", "secrets", fmt.Sprintf("%s.yaml", env))

	// Decrypt existing secrets
	result, err := s.exec.Run("sops", "-d", "--output-type", "json", secretsPath)
	if err != nil || result.ExitCode != 0 {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to decrypt secrets"})
		return
	}

	var secrets map[string]interface{}
	if err := json.Unmarshal([]byte(result.Stdout), &secrets); err != nil {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to parse secrets"})
		return
	}

	// Delete the key
	if _, exists := secrets[key]; !exists {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Secret not found"})
		return
	}

	delete(secrets, key)

	// Write back encrypted
	tempFile, err := os.CreateTemp("", "secrets-*.json")
	if err != nil {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to create temp file"})
		return
	}
	tempPath := tempFile.Name()
	defer os.Remove(tempPath)

	secretsJSON, _ := json.MarshalIndent(secrets, "", "  ")
	tempFile.Write(secretsJSON)
	tempFile.Close()

	sopsArgs := []string{"-e", "--input-type", "json", "--output-type", "yaml", tempPath}
	result, err = s.exec.Run("sops", sopsArgs...)
	if err != nil || result.ExitCode != 0 {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to re-encrypt secrets"})
		return
	}

	if err := os.WriteFile(secretsPath, []byte(result.Stdout), 0644); err != nil {
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to write secrets file"})
		return
	}

	log.Info().
		Str("environment", env).
		Str("key", key).
		Msg("Secret deleted")

	s.writeJSON(w, http.StatusOK, apiResponse{Success: true})
}

// handleSecretsList lists all environments and their secret keys (not values)
func (s *Server) handleSecretsList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	secretsDir := filepath.Join(s.config.ProjectRoot, ".stack", "secrets")

	// List all .yaml files in the secrets directory
	entries, err := os.ReadDir(secretsDir)
	if err != nil {
		if os.IsNotExist(err) {
			s.writeJSON(w, http.StatusOK, apiResponse{
				Success: true,
				Data: map[string]interface{}{
					"environments": []string{},
				},
			})
			return
		}
		s.writeJSON(w, http.StatusOK, apiResponse{Success: false, Error: "Failed to read secrets directory"})
		return
	}

	environments := make(map[string][]string)

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".yaml") {
			continue
		}

		// Skip special files
		if entry.Name() == "users.yaml" || entry.Name() == "config.yaml" {
			continue
		}

		env := strings.TrimSuffix(entry.Name(), ".yaml")
		secretsPath := filepath.Join(secretsDir, entry.Name())

		// Try to decrypt and list keys
		result, err := s.exec.Run("sops", "-d", "--output-type", "json", secretsPath)
		if err == nil && result.ExitCode == 0 {
			var secrets map[string]interface{}
			if err := json.Unmarshal([]byte(result.Stdout), &secrets); err == nil {
				keys := make([]string, 0, len(secrets))
				for k := range secrets {
					// Skip sops metadata keys
					if strings.HasPrefix(k, "sops") {
						continue
					}
					keys = append(keys, k)
				}
				environments[env] = keys
			}
		} else {
			// File exists but couldn't be decrypted
			environments[env] = []string{}
		}
	}

	s.writeJSON(w, http.StatusOK, apiResponse{
		Success: true,
		Data: map[string]interface{}{
			"environments": environments,
		},
	})
}
