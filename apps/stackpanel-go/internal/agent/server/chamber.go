// chamber.go implements the secrets backend dispatch layer and the AWS SSM
// Parameter Store ("chamber") backend.
//
// The dispatch handlers (handleSecretsWriteDispatch, etc.) route secret
// operations to either the SOPS/agenix backend or the chamber backend based
// on the stackpanel.variables.backend config setting ("vals" or "chamber").
//
// Chamber maps variable IDs to SSM paths:
//
//	/{env}/{KEY}  →  chamber service: {servicePrefix}/{env}, key: {KEY}
package server

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/rs/zerolog/log"
)

// ==============================================================================
// Backend Dispatch
//
// These handlers route to either the agenix (vals) or chamber backend based
// on the configured stackpanel.variables.backend setting.
// ==============================================================================

// handleSecretsWriteDispatch dispatches to agenix or chamber based on backend
func (s *Server) handleSecretsWriteDispatch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if s.getVariablesBackend() == "chamber" {
		s.handleChamberSecretWrite(w, r)
	} else {
		s.handleAgenixSecretWrite(w, r)
	}
}

// handleSecretsReadDispatch dispatches to agenix or chamber based on backend
func (s *Server) handleSecretsReadDispatch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if s.getVariablesBackend() == "chamber" {
		s.handleChamberSecretRead(w, r)
	} else {
		s.handleAgenixSecretRead(w, r)
	}
}

// handleSecretsDeleteDispatch dispatches to agenix or chamber based on backend
func (s *Server) handleSecretsDeleteDispatch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if s.getVariablesBackend() == "chamber" {
		s.handleChamberSecretDelete(w, r)
	} else {
		s.handleAgenixSecretDelete(w, r)
	}
}

// handleSecretsListDispatch dispatches to agenix or chamber based on backend
func (s *Server) handleSecretsListDispatch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if s.getVariablesBackend() == "chamber" {
		s.handleChamberSecretsList(w, r)
	} else {
		s.handleAgenixSecretsList(w, r)
	}
}

// handleSecretsBackend returns the configured variables backend
func (s *Server) handleSecretsBackend(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	backend := s.getVariablesBackend()
	resp := map[string]any{
		"backend": backend,
	}

	if backend == "chamber" {
		resp["chamber"] = map[string]any{
			"servicePrefix": s.getChamberServicePrefix(),
		}
	}

	s.writeAPI(w, http.StatusOK, resp)
}

// ==============================================================================
// Chamber Backend
//
// When stackpanel.variables.backend = "chamber", the agent uses the chamber
// CLI to read/write secrets from AWS SSM Parameter Store.
//
// Chamber service paths are derived from:
//   {servicePrefix}/{environment}
//
// For example: stackpanel/dev, stackpanel/prod
// ==============================================================================

// ChamberWriteRequest represents a request to write a secret via chamber
type ChamberWriteRequest struct {
	// ID is the variable identifier (e.g., "/dev/DATABASE_URL")
	ID string `json:"id"`

	// Key is the environment variable name (e.g., "DATABASE_URL")
	Key string `json:"key"`

	// Value is the plaintext secret value
	Value string `json:"value"`

	// Description is an optional description
	Description string `json:"description,omitempty"`
}

// ChamberWriteResponse is the response after writing a secret via chamber
type ChamberWriteResponse struct {
	ID      string `json:"id"`
	Key     string `json:"key"`
	Service string `json:"service"`
}

// ChamberReadRequest represents a request to read a secret via chamber
type ChamberReadRequest struct {
	// ID is the variable identifier (e.g., "/dev/DATABASE_URL")
	ID string `json:"id"`
}

// ChamberReadResponse is the response after reading a secret via chamber
type ChamberReadResponse struct {
	ID    string `json:"id"`
	Key   string `json:"key"`
	Value string `json:"value"`
}

// getVariablesBackend returns the configured variables backend ("vals" or "chamber").
// It reads from the serialized Nix config (FlakeWatcher cache or direct nix eval).
func (s *Server) getVariablesBackend() string {
	// Try reading from FlakeWatcher cache first
	if s.flakeWatcher != nil {
		ctx := context.Background()
		config, err := s.flakeWatcher.GetConfig(ctx)
		if err == nil && config != nil {
			if variables, ok := config["variables"].(map[string]any); ok {
				if backend, ok := variables["backend"].(string); ok && backend != "" {
					return backend
				}
			}
		}
	}

	return "vals" // default
}

// getChamberServicePrefix returns the chamber service prefix from config.
func (s *Server) getChamberServicePrefix() string {
	if s.flakeWatcher != nil {
		ctx := context.Background()
		config, err := s.flakeWatcher.GetConfig(ctx)
		if err == nil && config != nil {
			if variables, ok := config["variables"].(map[string]any); ok {
				if chamber, ok := variables["chamber"].(map[string]any); ok {
					if prefix, ok := chamber["servicePrefix"].(string); ok && prefix != "" {
						return prefix
					}
				}
			}
		}
	}

	return "" // unknown
}

// parseChamberService extracts the environment and key from a variable ID.
// "/dev/DATABASE_URL" -> env="dev", key="DATABASE_URL"
func parseChamberService(id string, servicePrefix string) (service string, key string, err error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return "", "", fmt.Errorf("empty id")
	}

	// Remove leading slash
	cleaned := strings.TrimPrefix(id, "/")
	parts := strings.SplitN(cleaned, "/", 2)
	if len(parts) < 2 {
		return "", "", fmt.Errorf("invalid variable id format: expected /<env>/<KEY>, got %q", id)
	}

	env := parts[0]
	key = parts[1]

	if servicePrefix == "" {
		return "", "", fmt.Errorf("chamber service prefix not configured")
	}

	service = servicePrefix + "/" + env
	return service, key, nil
}

// handleChamberSecretWrite writes a secret to AWS SSM via chamber
func (s *Server) handleChamberSecretWrite(w http.ResponseWriter, r *http.Request) {
	var req ChamberWriteRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	if strings.TrimSpace(req.ID) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "id is required")
		return
	}
	if strings.TrimSpace(req.Key) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "key is required")
		return
	}

	servicePrefix := s.getChamberServicePrefix()
	service, key, err := parseChamberService(req.ID, servicePrefix)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	// Write the secret using chamber
	// chamber write <service> <key> -- <value>
	// Chamber reads the value from stdin when using -
	args := []string{"write", service, key, "--", req.Value}
	res, execErr := s.exec.Run("chamber", args...)
	if execErr != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to run chamber: "+execErr.Error())
		return
	}
	if res.ExitCode != 0 {
		s.writeAPIError(w, http.StatusInternalServerError, "chamber write failed: "+strings.TrimSpace(res.Stderr))
		return
	}

	// Update variables.nix with metadata (value stays empty since it's in SSM)
	if err := s.updateVariableEntry(req.ID, req.Key, req.Description, nil); err != nil {
		log.Warn().Err(err).Msg("Failed to update variables.nix")
	}

	log.Info().
		Str("id", req.ID).
		Str("key", key).
		Str("service", service).
		Msg("Secret written via chamber")

	s.writeAPI(w, http.StatusOK, ChamberWriteResponse{
		ID:      req.ID,
		Key:     key,
		Service: service,
	})
}

// handleChamberSecretRead reads a secret from AWS SSM via chamber
func (s *Server) handleChamberSecretRead(w http.ResponseWriter, r *http.Request) {
	var req ChamberReadRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	if strings.TrimSpace(req.ID) == "" {
		s.writeAPIError(w, http.StatusBadRequest, "id is required")
		return
	}

	servicePrefix := s.getChamberServicePrefix()
	service, key, err := parseChamberService(req.ID, servicePrefix)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	// Read the secret using chamber
	// chamber read <service> <key>
	res, execErr := s.exec.Run("chamber", "read", "-q", service, key)
	if execErr != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to run chamber: "+execErr.Error())
		return
	}
	if res.ExitCode != 0 {
		errMsg := strings.TrimSpace(res.Stderr)
		if strings.Contains(errMsg, "ParameterNotFound") || strings.Contains(errMsg, "not found") {
			s.writeAPIError(w, http.StatusNotFound, "secret not found")
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, "chamber read failed: "+errMsg)
		return
	}

	log.Info().
		Str("id", req.ID).
		Str("service", service).
		Str("key", key).
		Msg("Secret read via chamber")

	s.writeAPI(w, http.StatusOK, ChamberReadResponse{
		ID:    req.ID,
		Key:   key,
		Value: strings.TrimSpace(res.Stdout),
	})
}

// handleChamberSecretDelete deletes a secret from AWS SSM via chamber
func (s *Server) handleChamberSecretDelete(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		s.writeAPIError(w, http.StatusBadRequest, "id is required")
		return
	}

	servicePrefix := s.getChamberServicePrefix()
	service, key, err := parseChamberService(id, servicePrefix)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	// Delete the secret using chamber
	// chamber delete <service> <key>
	res, execErr := s.exec.Run("chamber", "delete", service, key)
	if execErr != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to run chamber: "+execErr.Error())
		return
	}
	if res.ExitCode != 0 {
		s.writeAPIError(w, http.StatusInternalServerError, "chamber delete failed: "+strings.TrimSpace(res.Stderr))
		return
	}

	// Remove from variables.nix
	if err := s.removeVariableEntry(id); err != nil {
		log.Warn().Err(err).Msg("Failed to remove from variables.nix")
	}

	log.Info().Str("id", id).Str("service", service).Str("key", key).Msg("Secret deleted via chamber")
	s.writeAPI(w, http.StatusOK, map[string]any{"deleted": true, "id": id})
}

// handleChamberSecretsList lists all secrets in a chamber service
func (s *Server) handleChamberSecretsList(w http.ResponseWriter, r *http.Request) {
	servicePrefix := s.getChamberServicePrefix()
	if servicePrefix == "" {
		s.writeAPIError(w, http.StatusBadRequest, "chamber service prefix not configured")
		return
	}

	// List secrets for each environment
	envs := []string{"dev", "staging", "prod"}
	var allSecrets []map[string]any

	for _, env := range envs {
		service := servicePrefix + "/" + env

		// chamber list <service>
		res, err := s.exec.Run("chamber", "list", service)
		if err != nil || res.ExitCode != 0 {
			// Service may not exist yet, that's OK
			continue
		}

		// Parse chamber list output (one key per line)
		for _, line := range strings.Split(strings.TrimSpace(res.Stdout), "\n") {
			key := strings.TrimSpace(line)
			if key == "" || key == "Key" {
				continue // skip header
			}
			allSecrets = append(allSecrets, map[string]any{
				"id":      "/" + env + "/" + key,
				"key":     key,
				"service": service,
				"env":     env,
			})
		}
	}

	s.writeAPI(w, http.StatusOK, map[string]any{"secrets": allSecrets})
}
