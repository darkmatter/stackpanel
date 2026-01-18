// Package server provides SST infrastructure management handlers.
package server

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// SSTConfig represents the SST configuration from Nix.
type SSTConfig struct {
	Enable      bool   `json:"enable"`
	ProjectName string `json:"project-name"`
	Region      string `json:"region"`
	AccountID   string `json:"account-id"`
	ConfigPath  string `json:"config-path"`
	KMS         struct {
		Enable bool   `json:"enable"`
		Alias  string `json:"alias"`
	} `json:"kms"`
	OIDC struct {
		Provider      string `json:"provider"`
		GithubActions struct {
			Org    string `json:"org"`
			Repo   string `json:"repo"`
			Branch string `json:"branch"`
		} `json:"github-actions"`
		Flyio struct {
			OrgID   string `json:"org-id"`
			AppName string `json:"app-name"`
		} `json:"flyio"`
		RolesAnywhere struct {
			TrustAnchorARN string `json:"trust-anchor-arn"`
		} `json:"roles-anywhere"`
	} `json:"oidc"`
	IAM struct {
		RoleName string `json:"role-name"`
	} `json:"iam"`
}

// SSTStatus represents the current SST deployment status.
type SSTStatus struct {
	Configured  bool                   `json:"configured"`
	ConfigPath  string                 `json:"configPath"`
	ConfigValid bool                   `json:"configValid"`
	Deployed    bool                   `json:"deployed"`
	Stage       string                 `json:"stage"`
	LastDeploy  string                 `json:"lastDeploy,omitempty"`
	Outputs     map[string]interface{} `json:"outputs,omitempty"`
	Error       string                 `json:"error,omitempty"`
}

// SSTDeployRequest represents a deploy request.
type SSTDeployRequest struct {
	Stage string `json:"stage"`
}

// SSTDeployResponse represents a deploy response.
type SSTDeployResponse struct {
	Success bool                   `json:"success"`
	Output  string                 `json:"output"`
	Error   string                 `json:"error,omitempty"`
	Outputs map[string]interface{} `json:"outputs,omitempty"`
}

// handleSSTConfig returns the SST configuration from Nix.
func (s *Server) handleSSTConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Get SST config from nix eval
	res, err := s.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst")
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if res.ExitCode != 0 {
		// SST may not be configured, return empty config
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data": SSTConfig{
				Enable: false,
			},
		})
		return
	}

	var cfg SSTConfig
	if err := json.Unmarshal([]byte(res.Stdout), &cfg); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse SST config")
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    cfg,
	})
}

// handleSSTStatus returns the current SST deployment status.
func (s *Server) handleSSTStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	status := SSTStatus{
		Configured: false,
		Deployed:   false,
		Stage:      "dev",
	}

	// Get SST config from nix eval
	res, err := s.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst")
	if err != nil {
		status.Error = err.Error()
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    status,
		})
		return
	}

	if res.ExitCode == 0 {
		var cfg SSTConfig
		if err := json.Unmarshal([]byte(res.Stdout), &cfg); err == nil && cfg.Enable {
			status.Configured = true
			status.ConfigPath = cfg.ConfigPath

			// Check if config file exists
			configFullPath := filepath.Join(s.config.ProjectRoot, cfg.ConfigPath)
			if _, err := os.Stat(configFullPath); err == nil {
				status.ConfigValid = true
			}

			// Try to get outputs from SST
			sstDir := filepath.Dir(configFullPath)
			outRes, err := s.exec.RunWithOptions("bunx", sstDir, nil, "sst", "outputs", "--json")
			if err == nil && outRes.ExitCode == 0 {
				var outputs map[string]interface{}
				if json.Unmarshal([]byte(outRes.Stdout), &outputs) == nil && len(outputs) > 0 {
					status.Deployed = true
					status.Outputs = outputs
				}
			}
		}
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    status,
	})
}

// handleSSTDeploy triggers an SST deployment.
func (s *Server) handleSSTDeploy(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req SSTDeployRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	stage := req.Stage
	if stage == "" {
		stage = "dev"
	}

	// Get SST config path
	cfgRes, err := s.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst.config-path")
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if cfgRes.ExitCode != 0 {
		s.writeAPIError(w, http.StatusBadRequest, "SST not configured")
		return
	}

	var configPath string
	if err := json.Unmarshal([]byte(cfgRes.Stdout), &configPath); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse config path")
		return
	}

	// Run SST deploy
	sstDir := filepath.Join(s.config.ProjectRoot, filepath.Dir(configPath))
	res, err := s.exec.RunWithOptions("bunx", sstDir, nil, "sst", "deploy", "--stage", stage)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	response := SSTDeployResponse{
		Success: res.ExitCode == 0,
		Output:  res.Stdout + res.Stderr,
	}

	if res.ExitCode != 0 {
		response.Error = strings.TrimSpace(res.Stderr)
	} else {
		// Try to get outputs after successful deploy
		outRes, err := s.exec.RunWithOptions("bunx", sstDir, nil, "sst", "outputs", "--json")
		if err == nil && outRes.ExitCode == 0 {
			var outputs map[string]interface{}
			if json.Unmarshal([]byte(outRes.Stdout), &outputs) == nil {
				response.Outputs = outputs
			}
		}
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": response.Success,
		"data":    response,
	})
}

// handleSSTOutputs returns the SST stack outputs.
func (s *Server) handleSSTOutputs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Get SST config path
	cfgRes, err := s.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst.config-path")
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if cfgRes.ExitCode != 0 {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    map[string]interface{}{},
		})
		return
	}

	var configPath string
	if err := json.Unmarshal([]byte(cfgRes.Stdout), &configPath); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse config path")
		return
	}

	// Run SST outputs
	sstDir := filepath.Join(s.config.ProjectRoot, filepath.Dir(configPath))
	res, err := s.exec.RunWithOptions("bunx", sstDir, nil, "sst", "outputs", "--json")
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if res.ExitCode != 0 {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    map[string]interface{}{},
		})
		return
	}

	var outputs map[string]interface{}
	if err := json.Unmarshal([]byte(res.Stdout), &outputs); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse outputs")
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    outputs,
	})
}

// handleSSTResources returns the deployed SST resources.
func (s *Server) handleSSTResources(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Get SST config path
	cfgRes, err := s.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst.config-path")
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if cfgRes.ExitCode != 0 {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    []interface{}{},
		})
		return
	}

	var configPath string
	if err := json.Unmarshal([]byte(cfgRes.Stdout), &configPath); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse config path")
		return
	}

	// Check .sst directory for state
	sstDir := filepath.Join(s.config.ProjectRoot, filepath.Dir(configPath))
	sstStateDir := filepath.Join(sstDir, ".sst")

	resources := []map[string]interface{}{}

	// If state directory exists, try to list resources from state
	if info, err := os.Stat(sstStateDir); err == nil && info.IsDir() {
		// Read state files to extract resource information
		stateFiles, err := os.ReadDir(sstStateDir)
		if err == nil {
			for _, file := range stateFiles {
				if strings.HasSuffix(file.Name(), ".json") && strings.HasPrefix(file.Name(), "state") {
					statePath := filepath.Join(sstStateDir, file.Name())
					stateData, err := os.ReadFile(statePath)
					if err == nil {
						var state map[string]interface{}
						if json.Unmarshal(stateData, &state) == nil {
							// Extract resources from state
							if resourcesData, ok := state["resources"].([]interface{}); ok {
								for _, r := range resourcesData {
									if resMap, ok := r.(map[string]interface{}); ok {
										resources = append(resources, map[string]interface{}{
											"type": resMap["type"],
											"urn":  resMap["urn"],
											"id":   resMap["id"],
										})
									}
								}
							}
						}
					}
				}
			}
		}
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    resources,
	})
}

// handleSSTRemove removes the SST deployment.
func (s *Server) handleSSTRemove(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req struct {
		Stage string `json:"stage"`
	}
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	stage := req.Stage
	if stage == "" {
		stage = "dev"
	}

	// Get SST config path
	cfgRes, err := s.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst.config-path")
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if cfgRes.ExitCode != 0 {
		s.writeAPIError(w, http.StatusBadRequest, "SST not configured")
		return
	}

	var configPath string
	if err := json.Unmarshal([]byte(cfgRes.Stdout), &configPath); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse config path")
		return
	}

	// Run SST remove
	sstDir := filepath.Join(s.config.ProjectRoot, filepath.Dir(configPath))
	res, err := s.exec.RunWithOptions("bunx", sstDir, nil, "sst", "remove", "--stage", stage)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": res.ExitCode == 0,
		"data": map[string]interface{}{
			"output": res.Stdout + res.Stderr,
			"error":  strings.TrimSpace(res.Stderr),
		},
	})
}
