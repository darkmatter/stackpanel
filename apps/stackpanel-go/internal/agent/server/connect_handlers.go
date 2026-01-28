// Package server provides additional Connect-RPC handlers for the stackpanel agent.
// These handlers wrap existing HTTP handler logic to provide type-safe RPC access.
package server

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"connectrpc.com/connect"
	gopb "github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
)

// =============================================================================
// SST Infrastructure Handlers
// =============================================================================

// GetSSTStatus returns the current SST deployment status.
func (s *AgentServiceServer) GetSSTStatus(
	ctx context.Context,
	req *connect.Request[gopb.GetSSTStatusRequest],
) (*connect.Response[gopb.SSTStatusResponse], error) {
	resp := &gopb.SSTStatusResponse{
		Configured:  false,
		Deployed:    false,
		Stage:       "dev",
		ConfigPath:  "",
		ConfigValid: false,
	}

	// Get SST config from nix eval
	res, err := s.server.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst")
	if err != nil {
		resp.Error = err.Error()
		return connect.NewResponse(resp), nil
	}

	if res.ExitCode == 0 {
		var cfg SSTConfig
		if err := json.Unmarshal([]byte(res.Stdout), &cfg); err == nil && cfg.Enable {
			resp.Configured = true
			resp.ConfigPath = cfg.ConfigPath

			// Check if config file exists
			configFullPath := filepath.Join(s.server.config.ProjectRoot, cfg.ConfigPath)
			if _, err := os.Stat(configFullPath); err == nil {
				resp.ConfigValid = true
			}

			// Try to get outputs from SST
			sstDir := filepath.Dir(configFullPath)
			outRes, err := s.server.exec.RunWithOptions("bunx", sstDir, nil, "sst", "outputs", "--json")
			if err == nil && outRes.ExitCode == 0 {
				var outputs map[string]interface{}
				if json.Unmarshal([]byte(outRes.Stdout), &outputs) == nil && len(outputs) > 0 {
					resp.Deployed = true
				}
			}
		}
	}

	return connect.NewResponse(resp), nil
}

// GetSSTConfig returns the SST configuration from Nix.
func (s *AgentServiceServer) GetSSTConfig(
	ctx context.Context,
	req *connect.Request[gopb.GetSSTConfigRequest],
) (*connect.Response[gopb.Sst], error) {
	// Get SST config from nix eval
	res, err := s.server.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst")
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	if res.ExitCode != 0 {
		// SST may not be configured, return empty config
		return connect.NewResponse(&gopb.Sst{Enable: false}), nil
	}

	var cfg SSTConfig
	if err := json.Unmarshal([]byte(res.Stdout), &cfg); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to parse SST config: %w", err))
	}

	// Convert to proto message
	return connect.NewResponse(&gopb.Sst{
		Enable:      cfg.Enable,
		ProjectName: cfg.ProjectName,
		Region:      cfg.Region,
		AccountId:   cfg.AccountID,
		ConfigPath:  cfg.ConfigPath,
		Kms: &gopb.SstKms{
			Enable: cfg.KMS.Enable,
			Alias:  cfg.KMS.Alias,
		},
		Oidc: &gopb.SstOidc{
			Provider: cfg.OIDC.Provider,
			GithubActions: &gopb.SstGithubActions{
				Org:  cfg.OIDC.GithubActions.Org,
				Repo: cfg.OIDC.GithubActions.Repo,
			},
			Flyio: &gopb.SstFlyio{
				OrgId:   cfg.OIDC.Flyio.OrgID,
				AppName: cfg.OIDC.Flyio.AppName,
			},
			RolesAnywhere: &gopb.SstRolesAnywhere{
				TrustAnchorArn: cfg.OIDC.RolesAnywhere.TrustAnchorARN,
			},
		},
		Iam: &gopb.SstIam{
			RoleName: cfg.IAM.RoleName,
		},
	}), nil
}

// DeploySST triggers an SST deployment.
func (s *AgentServiceServer) DeploySST(
	ctx context.Context,
	req *connect.Request[gopb.DeploySSTRequest],
) (*connect.Response[gopb.DeploySSTResponse], error) {
	stage := req.Msg.Stage
	if stage == "" {
		stage = "dev"
	}

	// Get SST config path
	cfgRes, err := s.server.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst.config-path")
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	if cfgRes.ExitCode != 0 {
		return nil, connect.NewError(connect.CodeFailedPrecondition, fmt.Errorf("SST not configured"))
	}

	var configPath string
	if err := json.Unmarshal([]byte(cfgRes.Stdout), &configPath); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to parse config path: %w", err))
	}

	// Run SST deploy
	sstDir := filepath.Join(s.server.config.ProjectRoot, filepath.Dir(configPath))
	res, err := s.server.exec.RunWithOptions("bunx", sstDir, nil, "sst", "deploy", "--stage", stage)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	response := &gopb.DeploySSTResponse{
		Success: res.ExitCode == 0,
		Output:  res.Stdout + res.Stderr,
		Outputs: make(map[string]string),
	}

	if res.ExitCode != 0 {
		response.Error = strings.TrimSpace(res.Stderr)
	} else {
		// Try to get outputs after successful deploy
		outRes, err := s.server.exec.RunWithOptions("bunx", sstDir, nil, "sst", "outputs", "--json")
		if err == nil && outRes.ExitCode == 0 {
			var outputs map[string]interface{}
			if json.Unmarshal([]byte(outRes.Stdout), &outputs) == nil {
				for k, v := range outputs {
					if str, ok := v.(string); ok {
						response.Outputs[k] = str
					} else {
						// Convert non-string values to JSON
						if data, err := json.Marshal(v); err == nil {
							response.Outputs[k] = string(data)
						}
					}
				}
			}
		}
	}

	return connect.NewResponse(response), nil
}

// RemoveSST removes the SST deployment.
func (s *AgentServiceServer) RemoveSST(
	ctx context.Context,
	req *connect.Request[gopb.RemoveSSTRequest],
) (*connect.Response[gopb.RemoveSSTResponse], error) {
	stage := req.Msg.Stage
	if stage == "" {
		stage = "dev"
	}

	// Get SST config path
	cfgRes, err := s.server.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst.config-path")
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	if cfgRes.ExitCode != 0 {
		return nil, connect.NewError(connect.CodeFailedPrecondition, fmt.Errorf("SST not configured"))
	}

	var configPath string
	if err := json.Unmarshal([]byte(cfgRes.Stdout), &configPath); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to parse config path: %w", err))
	}

	// Run SST remove
	sstDir := filepath.Join(s.server.config.ProjectRoot, filepath.Dir(configPath))
	res, err := s.server.exec.RunWithOptions("bunx", sstDir, nil, "sst", "remove", "--stage", stage)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	return connect.NewResponse(&gopb.RemoveSSTResponse{
		Success: res.ExitCode == 0,
		Output:  res.Stdout + res.Stderr,
		Error:   strings.TrimSpace(res.Stderr),
	}), nil
}

// GetSSTOutputs returns the SST stack outputs.
func (s *AgentServiceServer) GetSSTOutputs(
	ctx context.Context,
	req *connect.Request[gopb.GetSSTOutputsRequest],
) (*connect.Response[gopb.SSTOutputsResponse], error) {
	// Get SST config path
	cfgRes, err := s.server.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst.config-path")
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	if cfgRes.ExitCode != 0 {
		return connect.NewResponse(&gopb.SSTOutputsResponse{Outputs: make(map[string]string)}), nil
	}

	var configPath string
	if err := json.Unmarshal([]byte(cfgRes.Stdout), &configPath); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to parse config path: %w", err))
	}

	// Run SST outputs
	sstDir := filepath.Join(s.server.config.ProjectRoot, filepath.Dir(configPath))
	res, err := s.server.exec.RunWithOptions("bunx", sstDir, nil, "sst", "outputs", "--json")
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	outputs := make(map[string]string)
	if res.ExitCode == 0 {
		var rawOutputs map[string]interface{}
		if json.Unmarshal([]byte(res.Stdout), &rawOutputs) == nil {
			for k, v := range rawOutputs {
				if str, ok := v.(string); ok {
					outputs[k] = str
				} else {
					if data, err := json.Marshal(v); err == nil {
						outputs[k] = string(data)
					}
				}
			}
		}
	}

	return connect.NewResponse(&gopb.SSTOutputsResponse{Outputs: outputs}), nil
}

// GetSSTResources returns the deployed SST resources.
func (s *AgentServiceServer) GetSSTResources(
	ctx context.Context,
	req *connect.Request[gopb.GetSSTResourcesRequest],
) (*connect.Response[gopb.SSTResourcesResponse], error) {
	// Get SST config path
	cfgRes, err := s.server.exec.RunNix("eval", "--json", ".#stackpanelConfig.sst.config-path")
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	if cfgRes.ExitCode != 0 {
		return connect.NewResponse(&gopb.SSTResourcesResponse{Resources: []*gopb.SSTResource{}}), nil
	}

	var configPath string
	if err := json.Unmarshal([]byte(cfgRes.Stdout), &configPath); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to parse config path: %w", err))
	}

	// Check .sst directory for state
	sstDir := filepath.Join(s.server.config.ProjectRoot, filepath.Dir(configPath))
	sstStateDir := filepath.Join(sstDir, ".sst")

	var resources []*gopb.SSTResource

	// If state directory exists, try to list resources from state
	if info, err := os.Stat(sstStateDir); err == nil && info.IsDir() {
		stateFiles, err := os.ReadDir(sstStateDir)
		if err == nil {
			for _, file := range stateFiles {
				if strings.HasSuffix(file.Name(), ".json") && strings.HasPrefix(file.Name(), "state") {
					statePath := filepath.Join(sstStateDir, file.Name())
					stateData, err := os.ReadFile(statePath)
					if err == nil {
						var state map[string]interface{}
						if json.Unmarshal(stateData, &state) == nil {
							if resourcesData, ok := state["resources"].([]interface{}); ok {
								for _, r := range resourcesData {
									if resMap, ok := r.(map[string]interface{}); ok {
										res := &gopb.SSTResource{}
										if t, ok := resMap["type"].(string); ok {
											res.Type = t
										}
										if u, ok := resMap["urn"].(string); ok {
											res.Urn = u
										}
										if id, ok := resMap["id"].(string); ok {
											res.Id = id
										}
										resources = append(resources, res)
									}
								}
							}
						}
					}
				}
			}
		}
	}

	return connect.NewResponse(&gopb.SSTResourcesResponse{Resources: resources}), nil
}

// =============================================================================
// Nixpkgs Package Management Handlers
// =============================================================================

// SearchNixpkgs searches for packages in nixpkgs.
func (s *AgentServiceServer) SearchNixpkgs(
	ctx context.Context,
	req *connect.Request[gopb.SearchNixpkgsRequest],
) (*connect.Response[gopb.SearchNixpkgsResponse], error) {
	query := strings.TrimSpace(req.Msg.Query)
	if query == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("query is required"))
	}

	limit := int(req.Msg.Limit)
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}

	// Check if executor is available
	if s.server.exec == nil {
		return nil, connect.NewError(connect.CodeUnavailable, fmt.Errorf("no project is open"))
	}

	// Get installed packages for marking
	installedSet := s.server.getInstalledPackageSet()

	// Run nix search with JSON output
	res, err := s.server.exec.RunNix("search", "nixpkgs", query, "--json")
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	var packages []*gopb.NixpkgsPackage

	if res.ExitCode == 0 {
		stdout := strings.TrimSpace(res.Stdout)
		if stdout != "" && stdout != "{}" && stdout != "null" {
			var searchResults map[string]struct {
				Pname       string `json:"pname"`
				Version     string `json:"version"`
				Description string `json:"description"`
			}

			if err := json.Unmarshal([]byte(stdout), &searchResults); err == nil {
				for attrPath, pkg := range searchResults {
					// Extract just the package name from the full attr path
					parts := strings.Split(attrPath, ".")
					shortAttr := attrPath
					if len(parts) >= 3 {
						shortAttr = strings.Join(parts[2:], ".")
					}

					// Check if installed
					installed := installedSet[strings.ToLower(pkg.Pname)] ||
						installedSet[strings.ToLower(shortAttr)]

					packages = append(packages, &gopb.NixpkgsPackage{
						Name:        pkg.Pname,
						AttrPath:    shortAttr,
						Version:     pkg.Version,
						Description: pkg.Description,
						Installed:   installed,
						NixpkgsUrl:  "https://search.nixos.org/packages?channel=unstable&show=" + shortAttr,
					})

					if len(packages) >= limit {
						break
					}
				}
			}
		}
	}

	return connect.NewResponse(&gopb.SearchNixpkgsResponse{Packages: packages}), nil
}

// GetInstalledPackages returns the list of installed packages from devenv/stackpanel config.
func (s *AgentServiceServer) GetInstalledPackages(
	ctx context.Context,
	req *connect.Request[gopb.GetInstalledPackagesRequest],
) (*connect.Response[gopb.InstalledPackagesResponse], error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	var packages []*gopb.InstalledPackage

	// Try FlakeWatcher first (preferred - has file watching and smart caching)
	if s.server.flakeWatcher != nil {
		flakePackages, err := s.server.flakeWatcher.GetPackages(ctx)
		if err == nil {
			for _, pkg := range flakePackages {
				packages = append(packages, &gopb.InstalledPackage{
					Name:     pkg.Name,
					Version:  pkg.Version,
					AttrPath: pkg.AttrPath,
					Source:   pkg.Source,
				})
			}
			return connect.NewResponse(&gopb.InstalledPackagesResponse{
				Packages: packages,
				Count:    int32(len(packages)),
			}), nil
		}
	}

	// Return empty list on error
	return connect.NewResponse(&gopb.InstalledPackagesResponse{
		Packages: packages,
		Count:    0,
	}), nil
}

// =============================================================================
// Process-Compose Handlers
// =============================================================================

// GetProcesses returns the list of processes from process-compose.
func (s *AgentServiceServer) GetProcesses(
	ctx context.Context,
	req *connect.Request[gopb.GetProcessesRequest],
) (*connect.Response[gopb.GetProcessesResponse], error) {
	resp := &gopb.GetProcessesResponse{
		Available: false,
		Running:   false,
		Processes: []*gopb.ProcessInfo{},
	}

	// Check if process-compose is available
	whichRes, err := s.server.exec.Run("which", "process-compose")
	if err != nil || whichRes.ExitCode != 0 {
		resp.Error = "process-compose not found in PATH"
		return connect.NewResponse(resp), nil
	}

	resp.Available = true

	// Try to get process list from process-compose
	res, err := s.server.exec.Run("process-compose", "process", "list", "-j")
	if err != nil {
		resp.Error = err.Error()
		return connect.NewResponse(resp), nil
	}

	if res.ExitCode != 0 {
		if strings.Contains(res.Stderr, "connection refused") ||
			strings.Contains(res.Stderr, "dial") ||
			strings.Contains(res.Stderr, "connect") {
			resp.Error = "process-compose server not running"
		} else {
			resp.Error = strings.TrimSpace(res.Stderr)
		}
		return connect.NewResponse(resp), nil
	}

	// Parse the JSON output
	var pcOutput struct {
		Data []struct {
			Name       string `json:"name"`
			Namespace  string `json:"namespace"`
			Status     string `json:"status"`
			PID        int    `json:"pid"`
			ExitCode   int    `json:"exit_code"`
			Restarts   int    `json:"restarts"`
			SystemTime string `json:"system_time"`
		} `json:"data"`
	}

	if err := json.Unmarshal([]byte(res.Stdout), &pcOutput); err != nil {
		// Try parsing as a plain array
		var processes []struct {
			Name       string `json:"name"`
			Namespace  string `json:"namespace"`
			Status     string `json:"status"`
			PID        int    `json:"pid"`
			ExitCode   int    `json:"exit_code"`
			Restarts   int    `json:"restarts"`
			SystemTime string `json:"system_time"`
		}
		if err := json.Unmarshal([]byte(res.Stdout), &processes); err != nil {
			resp.Error = "failed to parse process-compose output"
			return connect.NewResponse(resp), nil
		}

		for _, p := range processes {
			resp.Processes = append(resp.Processes, &gopb.ProcessInfo{
				Name:       p.Name,
				Namespace:  p.Namespace,
				Status:     p.Status,
				Pid:        int32(p.PID),
				ExitCode:   int32(p.ExitCode),
				IsRunning:  isProcessRunning(p.Status),
				Restarts:   int32(p.Restarts),
				SystemTime: p.SystemTime,
			})
		}
	} else {
		for _, p := range pcOutput.Data {
			resp.Processes = append(resp.Processes, &gopb.ProcessInfo{
				Name:       p.Name,
				Namespace:  p.Namespace,
				Status:     p.Status,
				Pid:        int32(p.PID),
				ExitCode:   int32(p.ExitCode),
				IsRunning:  isProcessRunning(p.Status),
				Restarts:   int32(p.Restarts),
				SystemTime: p.SystemTime,
			})
		}
	}

	resp.Running = len(resp.Processes) > 0 || res.ExitCode == 0

	return connect.NewResponse(resp), nil
}

// =============================================================================
// Healthchecks Handler
// =============================================================================

// GetHealthchecks returns the current health status.
func (s *AgentServiceServer) GetHealthchecks(
	ctx context.Context,
	req *connect.Request[gopb.GetHealthchecksRequest],
) (*connect.Response[gopb.HealthchecksResponse], error) {
	// Get healthcheck definitions from config
	healthchecks, err := s.server.getHealthcheckDefinitions()
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to get healthcheck definitions: %w", err))
	}

	var results []*gopb.HealthcheckInfo
	allHealthy := true

	for _, check := range healthchecks {
		if !check.Enabled {
			continue
		}

		result := s.server.runHealthcheck(ctx, check)

		healthy := result.Status == HealthStatusHealthy
		if !healthy {
			allHealthy = false
		}

		msg := ""
		if result.Message != nil {
			msg = *result.Message
		}
		details := ""
		if result.Output != nil {
			details = *result.Output
		}

		results = append(results, &gopb.HealthcheckInfo{
			Name:    check.Name,
			Type:    string(check.Type),
			Healthy: healthy,
			Message: msg,
			Details: details,
		})
	}

	return connect.NewResponse(&gopb.HealthchecksResponse{
		AllHealthy: allHealthy,
		Checks:     results,
	}), nil
}

// =============================================================================
// Full Nix Config Handlers
// =============================================================================

// GetNixConfig returns the full Nix configuration.
func (s *AgentServiceServer) GetNixConfig(
	ctx context.Context,
	req *connect.Request[gopb.GetNixConfigRequest],
) (*connect.Response[gopb.NixConfigResponse], error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	forceRefresh := req.Msg.Refresh

	// Try FlakeWatcher first (preferred - has file watching and smart caching)
	if s.server.flakeWatcher != nil {
		if forceRefresh {
			s.server.flakeWatcher.InvalidateAll()
		}

		config, err := s.server.flakeWatcher.GetConfig(ctx)
		if err == nil {
			updated, cached := s.server.flakeWatcher.ConfigStatus()

			// Convert config to JSON string
			configJSON, err := json.Marshal(config)
			if err != nil {
				return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to marshal config: %w", err))
			}

			return connect.NewResponse(&gopb.NixConfigResponse{
				ConfigJson:  string(configJSON),
				LastUpdated: updated.Format(time.RFC3339),
				Cached:      cached,
				Source:      "flake_watcher",
			}), nil
		}
	}

	// Fallback to legacy evaluation
	config, err := s.server.evaluateConfig()
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to evaluate config: %w", err))
	}

	configJSON, err := json.Marshal(config)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to marshal config: %w", err))
	}

	return connect.NewResponse(&gopb.NixConfigResponse{
		ConfigJson:  string(configJSON),
		LastUpdated: time.Now().Format(time.RFC3339),
		Cached:      false,
		Source:      "fresh_eval",
	}), nil
}

// RefreshNixConfig forces a config refresh by re-evaluating the flake.
func (s *AgentServiceServer) RefreshNixConfig(
	ctx context.Context,
	req *connect.Request[gopb.RefreshNixConfigRequest],
) (*connect.Response[gopb.NixConfigResponse], error) {
	// 5 minutes allows time for Nix to download packages from caches
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	// Try FlakeWatcher first
	if s.server.flakeWatcher != nil {
		if err := s.server.flakeWatcher.ForceRefresh(ctx); err == nil {
			config, _ := s.server.flakeWatcher.GetConfig(ctx)

			configJSON, err := json.Marshal(config)
			if err != nil {
				return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to marshal config: %w", err))
			}

			// Notify SSE subscribers that config has changed
			s.server.broadcastSSE(SSEEvent{
				Event: "config.refreshed",
				Data: map[string]any{
					"timestamp": time.Now().Format(time.RFC3339),
				},
			})

			return connect.NewResponse(&gopb.NixConfigResponse{
				ConfigJson:  string(configJSON),
				LastUpdated: time.Now().Format(time.RFC3339),
				Cached:      false,
				Source:      "flake_watcher",
			}), nil
		}
	}

	// Fallback to legacy evaluation
	config, err := s.server.evaluateConfig()
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to evaluate config: %w", err))
	}

	configJSON, err := json.Marshal(config)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to marshal config: %w", err))
	}

	// Notify SSE subscribers that config has changed
	s.server.broadcastSSE(SSEEvent{
		Event: "config.refreshed",
		Data: map[string]any{
			"timestamp": time.Now().Format(time.RFC3339),
		},
	})

	return connect.NewResponse(&gopb.NixConfigResponse{
		ConfigJson:  string(configJSON),
		LastUpdated: time.Now().Format(time.RFC3339),
		Cached:      false,
		Source:      "fresh_eval",
	}), nil
}
