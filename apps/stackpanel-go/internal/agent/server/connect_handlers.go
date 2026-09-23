// connect_handlers.go contains Connect-RPC handlers for installed devshell
// packages, process-compose process listing, and the full evaluated Nix config.
// These read from the FlakeWatcher cache or the process-compose HTTP API.

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"time"

	"connectrpc.com/connect"
	gopb "github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
)

// =============================================================================
// Nixpkgs Package Management Handlers
// =============================================================================

// GetInstalledPackages returns packages from the FlakeWatcher cache, which tracks
// the evaluated devshell packages and invalidates on flake.nix changes.
// Falls back to an empty list rather than erroring — the UI handles this gracefully.
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

// GetProcesses returns all process-compose processes across every namespace
// for the process management UI panel.
func (s *AgentServiceServer) GetProcesses(
	ctx context.Context,
	req *connect.Request[gopb.GetProcessesRequest],
) (*connect.Response[gopb.GetProcessesResponse], error) {
	resp := &gopb.GetProcessesResponse{
		Available: false,
		Running:   false,
		Processes: []*gopb.ProcessInfo{},
	}

	// Use HTTP API instead of CLI for better performance
	client := getProcessComposeClient()
	apiURL := getProcessComposeBaseURL() + "/processes"

	httpResp, err := client.Get(apiURL)
	if err != nil {
		resp.Error = "process-compose server not running"
		return connect.NewResponse(resp), nil
	}
	defer httpResp.Body.Close()

	body, err := io.ReadAll(httpResp.Body)
	if err != nil {
		resp.Error = "failed to read response"
		return connect.NewResponse(resp), nil
	}

	if httpResp.StatusCode < 200 || httpResp.StatusCode >= 300 {
		resp.Error = fmt.Sprintf("process-compose returned status %d", httpResp.StatusCode)
		return connect.NewResponse(resp), nil
	}

	// Parse the JSON output from the HTTP API
	var pcOutput struct {
		Data []struct {
			Name       string  `json:"name"`
			Namespace  string  `json:"namespace"`
			Status     string  `json:"status"`
			PID        int     `json:"pid"`
			ExitCode   int     `json:"exit_code"`
			Restarts   int     `json:"restarts"`
			SystemTime string  `json:"system_time"`
			IsRunning  bool    `json:"is_running"`
			IsReady    string  `json:"is_ready"`
			Mem        int64   `json:"mem"`
			CPU        float64 `json:"cpu"`
		} `json:"data"`
	}

	if err := json.Unmarshal(body, &pcOutput); err != nil {
		resp.Error = "failed to parse process-compose output"
		return connect.NewResponse(resp), nil
	}

	resp.Available = true

	for _, p := range pcOutput.Data {
		resp.Processes = append(resp.Processes, &gopb.ProcessInfo{
			Name:       p.Name,
			Namespace:  p.Namespace,
			Status:     p.Status,
			Pid:        int32(p.PID),
			ExitCode:   int32(p.ExitCode),
			IsRunning:  p.IsRunning,
			Restarts:   int32(p.Restarts),
			SystemTime: p.SystemTime,
		})
	}

	resp.Running = len(resp.Processes) > 0

	return connect.NewResponse(resp), nil
}

// =============================================================================
// Full Nix Config Handlers
// =============================================================================

// GetNixConfig returns the full evaluated Nix configuration as JSON.
// Prefers the FlakeWatcher cache (invalidated by fsnotify on .nix file changes)
// and falls back to a fresh `nix eval` if unavailable. The "source" field in the
// response lets the UI indicate whether data is cached or freshly evaluated.
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
				return nil, connect.NewError(
					connect.CodeInternal,
					fmt.Errorf("failed to marshal config: %w", err),
				)
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
		return nil, connect.NewError(
			connect.CodeInternal,
			fmt.Errorf("failed to evaluate config: %w", err),
		)
	}

	configJSON, err := json.Marshal(config)
	if err != nil {
		return nil, connect.NewError(
			connect.CodeInternal,
			fmt.Errorf("failed to marshal config: %w", err),
		)
	}

	return connect.NewResponse(&gopb.NixConfigResponse{
		ConfigJson:  string(configJSON),
		LastUpdated: time.Now().Format(time.RFC3339),
		Cached:      false,
		Source:      "fresh_eval",
	}), nil
}
