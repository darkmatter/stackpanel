package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Recipient represents an AGE public key recipient.
type Recipient struct {
	Name      string   `json:"name"`
	PublicKey string   `json:"publicKey"`
	Tags      []string `json:"tags,omitempty"`
	Source    string   `json:"source,omitempty"`
	CanDelete bool     `json:"canDelete,omitempty"`
}

// RecipientRequest is the body for adding a new recipient.
type RecipientRequest struct {
	Name         string   `json:"name"`
	PublicKey    string   `json:"publicKey,omitempty"`
	SSHPublicKey string   `json:"sshPublicKey,omitempty"`
	Tags         []string `json:"tags,omitempty"`
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

func normalizeRecipientTags(tags []string) []string {
	seen := make(map[string]struct{}, len(tags))
	normalized := make([]string, 0, len(tags))
	for _, tag := range tags {
		trimmed := strings.TrimSpace(tag)
		if trimmed == "" {
			continue
		}
		if _, exists := seen[trimmed]; exists {
			continue
		}
		seen[trimmed] = struct{}{}
		normalized = append(normalized, trimmed)
	}
	sort.Strings(normalized)
	return normalized
}

func normalizeRecipientPublicKey(req RecipientRequest) (string, error) {
	publicKey := strings.TrimSpace(req.PublicKey)
	sshPublicKey := strings.TrimSpace(req.SSHPublicKey)

	if publicKey != "" && sshPublicKey != "" {
		return "", fmt.Errorf("provide either publicKey or sshPublicKey, not both")
	}

	key := publicKey
	if key == "" {
		key = sshPublicKey
	}
	if key == "" {
		return "", fmt.Errorf("either publicKey or sshPublicKey is required")
	}

	if strings.HasPrefix(key, "age1") || strings.HasPrefix(key, "ssh-") {
		return key, nil
	}

	return "", fmt.Errorf("public key must start with 'age1' or 'ssh-'")
}

func (s *Server) explicitSecretsRecipients() (map[string]map[string]any, error) {
	data, err := s.readConsolidatedData()
	if err != nil {
		return nil, fmt.Errorf("read config.nix: %w", err)
	}

	secretsRaw, ok := data["secrets"]
	if !ok {
		return map[string]map[string]any{}, nil
	}
	secrets, ok := secretsRaw.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("config secrets is not an attribute set")
	}

	recipientsRaw, ok := secrets["recipients"]
	if !ok {
		return map[string]map[string]any{}, nil
	}
	recipientsMap, ok := recipientsRaw.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("config secrets.recipients is not an attribute set")
	}

	result := make(map[string]map[string]any, len(recipientsMap))
	for name, raw := range recipientsMap {
		recipientMap, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		result[name] = recipientMap
	}
	return result, nil
}

func (s *Server) mutableSecretsRecipientsConfig() (map[string]any, map[string]any, map[string]any, error) {
	data, err := s.readConsolidatedData()
	if err != nil {
		return nil, nil, nil, fmt.Errorf("read config.nix: %w", err)
	}

	secrets, ok := data["secrets"].(map[string]any)
	if !ok {
		secrets = map[string]any{}
		data["secrets"] = secrets
	}

	recipients, ok := secrets["recipients"].(map[string]any)
	if !ok {
		recipients = map[string]any{}
		secrets["recipients"] = recipients
	}

	return data, secrets, recipients, nil
}

func (s *Server) notifyRecipientConfigChange(path string, action string) {
	if s.flakeWatcher != nil {
		s.flakeWatcher.InvalidateConfig()
	}

	s.broadcastSSE(SSEEvent{
		Event: "config.changed",
		Data: map[string]any{
			"entity": "config",
			"path":   path,
			"source": action,
		},
	})
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

// handleListRecipients returns all recipients from the Nix-configured secrets state.
func (s *Server) handleListRecipients(w http.ResponseWriter, _ *http.Request) {
	serializable, err := s.getSerializableSecretsConfig()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to read secrets config: %v", err))
		return
	}
	explicitRecipients, err := s.explicitSecretsRecipients()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to read config recipients: %v", err))
		return
	}
	recipients := make([]Recipient, 0, len(serializable.Recipients))
	for name, recipient := range serializable.Recipients {
		_, explicit := explicitRecipients[name]
		source := "users"
		if explicit {
			source = "secrets"
		}
		recipients = append(recipients, Recipient{
			Name:      name,
			PublicKey: recipient.PublicKey,
			Tags:      normalizeRecipientTags(recipient.Tags),
			Source:    source,
			CanDelete: explicit,
		})
	}
	sort.Slice(recipients, func(i, j int) bool {
		return recipients[i].Name < recipients[j].Name
	})

	s.writeAPI(w, http.StatusOK, map[string]any{"recipients": recipients})
}

func (s *Server) handleAddRecipient(w http.ResponseWriter, r *http.Request) {
	var req RecipientRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	name := strings.TrimSpace(req.Name)
	if name == "" {
		s.writeAPIError(w, http.StatusBadRequest, "name is required")
		return
	}
	if !recipientNameRegex.MatchString(name) {
		s.writeAPIError(w, http.StatusBadRequest, "name must be alphanumeric (hyphens, underscores, dots allowed)")
		return
	}

	publicKey, err := normalizeRecipientPublicKey(req)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	tags := normalizeRecipientTags(req.Tags)
	if len(tags) == 0 {
		s.writeAPIError(w, http.StatusBadRequest, "at least one tag is required")
		return
	}

	existingRecipients, err := s.getSerializableSecretsConfig()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to read secrets config: %v", err))
		return
	}
	explicitRecipients, err := s.explicitSecretsRecipients()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to read config recipients: %v", err))
		return
	}
	if _, exists := existingRecipients.Recipients[name]; exists {
		if _, explicit := explicitRecipients[name]; explicit {
			s.writeAPIError(w, http.StatusConflict, fmt.Sprintf("recipient %q already exists", name))
			return
		}
		s.writeAPIError(w, http.StatusConflict, fmt.Sprintf("recipient %q is managed by stackpanel.users; choose a different name or edit that user entry", name))
		return
	}

	configData, _, recipientsMap, err := s.mutableSecretsRecipientsConfig()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}
	recipientsMap[name] = map[string]any{
		"public-key": publicKey,
		"tags":       tags,
	}

	if err := s.writeConsolidatedData(configData); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to update config.nix: %v", err))
		return
	}
	s.notifyRecipientConfigChange("stackpanel.secrets.recipients."+name, "recipient.add")

	s.writeAPI(w, http.StatusOK, Recipient{
		Name:      name,
		PublicKey: publicKey,
		Tags:      tags,
		Source:    "secrets",
		CanDelete: true,
	})
}

func (s *Server) handleDeleteRecipient(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimSpace(r.URL.Query().Get("name"))
	if name == "" {
		s.writeAPIError(w, http.StatusBadRequest, "name query parameter is required")
		return
	}
	if !recipientNameRegex.MatchString(name) {
		s.writeAPIError(w, http.StatusBadRequest, "invalid recipient name")
		return
	}

	configData, secretsMap, recipientsMap, err := s.mutableSecretsRecipientsConfig()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if _, exists := recipientsMap[name]; !exists {
		serializable, serr := s.getSerializableSecretsConfig()
		if serr == nil {
			if _, derived := serializable.Recipients[name]; derived {
				s.writeAPIError(w, http.StatusBadRequest, fmt.Sprintf("recipient %q is managed by stackpanel.users and must be removed there", name))
				return
			}
		}
		s.writeAPIError(w, http.StatusNotFound, fmt.Sprintf("recipient %q not found", name))
		return
	}

	delete(recipientsMap, name)
	if len(recipientsMap) == 0 {
		delete(secretsMap, "recipients")
	}

	if err := s.writeConsolidatedData(configData); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to update config.nix: %v", err))
		return
	}
	s.notifyRecipientConfigChange("stackpanel.secrets.recipients."+name, "recipient.remove")

	s.writeAPI(w, http.StatusOK, map[string]any{"name": name, "deleted": true})
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

	s.writeAPI(w, http.StatusOK, RekeyWorkflowStatus{Exists: exists})
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
		s.writeAPI(w, http.StatusOK, SecretsVerifyResponse{
			Success: false,
			Error:   fmt.Sprintf("failed to get recipients: %v", err),
		})
		return
	}

	if len(recipients) == 0 {
		s.writeAPI(w, http.StatusOK, SecretsVerifyResponse{
			Success: false,
			Error:   "no recipients configured for this group",
		})
		return
	}

	// Create temp file with test content
	tmpFile, err := os.CreateTemp("", "sp-verify-*.yaml")
	if err != nil {
		s.writeAPI(w, http.StatusOK, SecretsVerifyResponse{
			Success: false,
			Error:   fmt.Sprintf("failed to create temp file: %v", err),
		})
		return
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)

	testContent := "_verify_test: stackpanel-verify-ok\n"
	if _, err := tmpFile.WriteString(testContent); err != nil {
		tmpFile.Close()
		s.writeAPI(w, http.StatusOK, SecretsVerifyResponse{
			Success: false,
			Error:   fmt.Sprintf("failed to write test content: %v", err),
		})
		return
	}
	tmpFile.Close()

	// Encrypt with sops
	encryptArgs := []string{"--encrypt", "--input-type", "yaml", "--output-type", "yaml", "--age", strings.Join(recipients, ",")}
	encryptArgs = append(encryptArgs, tmpPath)

	encRes, err := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, encryptArgs...)
	if err != nil || encRes.ExitCode != 0 {
		errMsg := "encryption failed"
		if err != nil {
			errMsg = fmt.Sprintf("encryption failed: %v", err)
		} else if encRes.Stderr != "" {
			errMsg = fmt.Sprintf("encryption failed: %s", encRes.Stderr)
		}
		s.writeAPI(w, http.StatusOK, SecretsVerifyResponse{Success: false, Error: errMsg})
		return
	}

	// Write encrypted content to a temp file for decryption
	encTmp, err := os.CreateTemp("", "sp-verify-enc-*.yaml")
	if err != nil {
		s.writeAPI(w, http.StatusOK, SecretsVerifyResponse{
			Success: false,
			Error:   fmt.Sprintf("failed to create encrypted temp file: %v", err),
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
		s.writeAPI(w, http.StatusOK, SecretsVerifyResponse{Success: false, Error: errMsg})
		return
	}

	// Verify the decrypted content matches
	if !strings.Contains(decRes.Stdout, "stackpanel-verify-ok") {
		s.writeAPI(w, http.StatusOK, SecretsVerifyResponse{Success: false, Error: "decrypted content does not match original"})
		return
	}

	s.writeAPI(w, http.StatusOK, SecretsVerifyResponse{Success: true})
}
