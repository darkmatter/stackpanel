package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/rs/zerolog/log"
)

// Recipient represents an AGE public key recipient.
type Recipient struct {
	Name      string `json:"name"`
	PublicKey string `json:"publicKey"`
}

// RecipientRequest is the body for adding a new recipient.
type RecipientRequest struct {
	Name         string `json:"name"`
	PublicKey    string `json:"publicKey,omitempty"`
	SSHPublicKey string `json:"sshPublicKey,omitempty"`
}

// RekeyWorkflowStatus describes the state of the GitHub Actions rekey workflow.
type RekeyWorkflowStatus struct {
	Exists bool `json:"exists"`
}

// SecretsVerifyRequest asks to verify encrypt/decrypt for a group.
type SecretsVerifyRequest struct {
	Group string `json:"group"`
}

// SecretsVerifyResponse reports the result of the verification.
type SecretsVerifyResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}

// recipientNameRegex allows alphanumeric, hyphens, underscores, and dots.
var recipientNameRegex = regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)

// getRecipientsDir returns the absolute path to the recipients directory.
func (s *Server) getRecipientsDir() (string, error) {
	secretsCfg, err := s.getSecretsConfig()
	if err != nil {
		return "", fmt.Errorf("failed to get secrets config: %w", err)
	}
	return filepath.Join(s.config.ProjectRoot, secretsCfg.SecretsDir, "keys", "recipients"), nil
}

// handleRecipientsRoute dispatches GET/POST/DELETE to sub-handlers.
func (s *Server) handleRecipientsRoute(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleListRecipients(w, r)
	case http.MethodPost:
		s.handleAddRecipient(w, r)
	case http.MethodDelete:
		s.handleDeleteRecipient(w, r)
	case http.MethodOptions:
		w.WriteHeader(http.StatusNoContent)
	default:
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// handleListRecipients returns all recipients in the recipients directory.
func (s *Server) handleListRecipients(w http.ResponseWriter, _ *http.Request) {
	recipientsDir, err := s.getRecipientsDir()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	entries, err := os.ReadDir(recipientsDir)
	if err != nil {
		if os.IsNotExist(err) {
			s.writeAPI(w, http.StatusOK, map[string]any{
				"success": true,
				"data":    map[string]any{"recipients": []Recipient{}},
			})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to read recipients dir: %v", err))
		return
	}

	recipients := []Recipient{}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".pub") {
			continue
		}
		name := strings.TrimSuffix(entry.Name(), ".pub")
		content, err := os.ReadFile(filepath.Join(recipientsDir, entry.Name()))
		if err != nil {
			log.Warn().Err(err).Str("file", entry.Name()).Msg("failed to read recipient pub file")
			continue
		}
		pubKey := strings.TrimSpace(string(content))
		if pubKey != "" {
			recipients = append(recipients, Recipient{
				Name:      name,
				PublicKey: pubKey,
			})
		}
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    map[string]any{"recipients": recipients},
	})
}

// handleAddRecipient adds a new recipient .pub file.
func (s *Server) handleAddRecipient(w http.ResponseWriter, r *http.Request) {
	var req RecipientRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Name == "" {
		s.writeAPIError(w, http.StatusBadRequest, "name is required")
		return
	}
	if !recipientNameRegex.MatchString(req.Name) {
		s.writeAPIError(w, http.StatusBadRequest, "name must be alphanumeric (hyphens, underscores, dots allowed)")
		return
	}

	var pubKey string

	if req.SSHPublicKey != "" {
		// Convert SSH public key to AGE public key via ssh-to-age
		// Write SSH key to a temp file since we can't pipe stdin
		sshTmp, tmpErr := os.CreateTemp("", "sp-ssh-*.pub")
		if tmpErr != nil {
			s.writeAPIError(w, http.StatusInternalServerError, "failed to create temp file for SSH key")
			return
		}
		sshTmpPath := sshTmp.Name()
		defer os.Remove(sshTmpPath)
		if _, tmpErr = sshTmp.WriteString(req.SSHPublicKey); tmpErr != nil {
			sshTmp.Close()
			s.writeAPIError(w, http.StatusInternalServerError, "failed to write SSH key to temp file")
			return
		}
		sshTmp.Close()

		res, err := s.exec.RunWithOptions("ssh-to-age", s.config.ProjectRoot, nil, "-i", sshTmpPath)
		if err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("ssh-to-age conversion failed: %v", err))
			return
		}
		if res.ExitCode != 0 {
			s.writeAPIError(w, http.StatusBadRequest, fmt.Sprintf("ssh-to-age conversion failed: %s", strings.TrimSpace(res.Stderr)))
			return
		}
		pubKey = strings.TrimSpace(res.Stdout)
		if pubKey == "" || !strings.HasPrefix(pubKey, "age1") {
			s.writeAPIError(w, http.StatusBadRequest, "ssh-to-age conversion produced invalid output")
			return
		}
	} else if req.PublicKey != "" {
		pubKey = strings.TrimSpace(req.PublicKey)
		if !strings.HasPrefix(pubKey, "age1") {
			s.writeAPIError(w, http.StatusBadRequest, "public key must start with 'age1'")
			return
		}
	} else {
		s.writeAPIError(w, http.StatusBadRequest, "either publicKey or sshPublicKey is required")
		return
	}

	recipientsDir, err := s.getRecipientsDir()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	// Ensure directory exists
	if err := os.MkdirAll(recipientsDir, 0o755); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to create recipients dir: %v", err))
		return
	}

	pubFile := filepath.Join(recipientsDir, req.Name+".pub")
	if err := os.WriteFile(pubFile, []byte(pubKey+"\n"), 0o644); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to write recipient file: %v", err))
		return
	}

	log.Info().Str("name", req.Name).Str("pubKey", pubKey).Msg("added recipient")

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
		"data": Recipient{
			Name:      req.Name,
			PublicKey: pubKey,
		},
	})
}

// handleDeleteRecipient removes a recipient .pub file.
func (s *Server) handleDeleteRecipient(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	if name == "" {
		s.writeAPIError(w, http.StatusBadRequest, "name query parameter is required")
		return
	}
	if !recipientNameRegex.MatchString(name) {
		s.writeAPIError(w, http.StatusBadRequest, "invalid recipient name")
		return
	}

	recipientsDir, err := s.getRecipientsDir()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	pubFile := filepath.Join(recipientsDir, name+".pub")
	if _, err := os.Stat(pubFile); os.IsNotExist(err) {
		s.writeAPIError(w, http.StatusNotFound, fmt.Sprintf("recipient '%s' not found", name))
		return
	}

	if err := os.Remove(pubFile); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to remove recipient: %v", err))
		return
	}

	log.Info().Str("name", name).Msg("removed recipient")

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    map[string]any{"name": name, "deleted": true},
	})
}

// handleRekeyWorkflowStatus checks if the rekey workflow exists.
func (s *Server) handleRekeyWorkflowStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	workflowPath := filepath.Join(s.config.ProjectRoot, ".github", "workflows", "secrets-rekey.yml")
	exists := false
	if _, err := os.Stat(workflowPath); err == nil {
		exists = true
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    RekeyWorkflowStatus{Exists: exists},
	})
}

// handleSecretsVerify does an encrypt/decrypt round-trip to verify secrets work.
func (s *Server) handleSecretsVerify(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req SecretsVerifyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Group == "" {
		s.writeAPIError(w, http.StatusBadRequest, "group is required")
		return
	}

	safeGroup := strings.ReplaceAll(req.Group, "/", "")
	safeGroup = strings.ReplaceAll(safeGroup, "..", "")

	// Get recipients for this group
	recipients, err := s.getGroupRecipients(safeGroup)
	if err != nil {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"data": SecretsVerifyResponse{
				Success: false,
				Error:   fmt.Sprintf("failed to get recipients: %v", err),
			},
		})
		return
	}

	if len(recipients) == 0 {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"data": SecretsVerifyResponse{
				Success: false,
				Error:   "no recipients configured for this group",
			},
		})
		return
	}

	// Create temp file with test content
	tmpFile, err := os.CreateTemp("", "sp-verify-*.yaml")
	if err != nil {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"data": SecretsVerifyResponse{
				Success: false,
				Error:   fmt.Sprintf("failed to create temp file: %v", err),
			},
		})
		return
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)

	testContent := "_verify_test: stackpanel-verify-ok\n"
	if _, err := tmpFile.WriteString(testContent); err != nil {
		tmpFile.Close()
		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"data": SecretsVerifyResponse{
				Success: false,
				Error:   fmt.Sprintf("failed to write test content: %v", err),
			},
		})
		return
	}
	tmpFile.Close()

	// Encrypt with sops
	encryptArgs := []string{"--encrypt", "--input-type", "yaml", "--output-type", "yaml"}
	for _, r := range recipients {
		encryptArgs = append(encryptArgs, "--age", r)
	}
	encryptArgs = append(encryptArgs, tmpPath)

	encRes, err := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, encryptArgs...)
	if err != nil || encRes.ExitCode != 0 {
		errMsg := "encryption failed"
		if err != nil {
			errMsg = fmt.Sprintf("encryption failed: %v", err)
		} else if encRes.Stderr != "" {
			errMsg = fmt.Sprintf("encryption failed: %s", encRes.Stderr)
		}
		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"data":    SecretsVerifyResponse{Success: false, Error: errMsg},
		})
		return
	}

	// Write encrypted content to a temp file for decryption
	encTmp, err := os.CreateTemp("", "sp-verify-enc-*.yaml")
	if err != nil {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"data": SecretsVerifyResponse{
				Success: false,
				Error:   fmt.Sprintf("failed to create encrypted temp file: %v", err),
			},
		})
		return
	}
	encTmpPath := encTmp.Name()
	defer os.Remove(encTmpPath)

	if _, err := encTmp.WriteString(encRes.Stdout); err != nil {
		encTmp.Close()
		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"data":    SecretsVerifyResponse{Success: false, Error: "failed to write encrypted content"},
		})
		return
	}
	encTmp.Close()

	// Decrypt with sops
	decRes, err := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, "--decrypt", encTmpPath)
	if err != nil || decRes.ExitCode != 0 {
		errMsg := "decryption failed"
		if err != nil {
			errMsg = fmt.Sprintf("decryption failed: %v", err)
		} else if decRes.Stderr != "" {
			errMsg = fmt.Sprintf("decryption failed: %s", strings.TrimSpace(decRes.Stderr))
		}
		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"data":    SecretsVerifyResponse{Success: false, Error: errMsg},
		})
		return
	}

	// Verify the decrypted content matches
	if !strings.Contains(decRes.Stdout, "stackpanel-verify-ok") {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"data":    SecretsVerifyResponse{Success: false, Error: "decrypted content does not match original"},
		})
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    SecretsVerifyResponse{Success: true},
	})
}
