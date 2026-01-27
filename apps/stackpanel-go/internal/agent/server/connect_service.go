// Package server provides the HTTP/SSE server for the stackpanel agent.
package server

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"connectrpc.com/connect"
	gopb "github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
	"github.com/rs/zerolog/log"
)

// AgentServiceServer implements the Connect-RPC AgentService interface.
// This provides type-safe RPC handlers for all agent operations.
type AgentServiceServer struct {
	server *Server
}

// NewAgentServiceServer creates a new AgentServiceServer.
func NewAgentServiceServer(s *Server) *AgentServiceServer {
	return &AgentServiceServer{server: s}
}

// =============================================================================
// Project
// =============================================================================

func (s *AgentServiceServer) GetProject(
	ctx context.Context,
	req *connect.Request[gopb.GetProjectRequest],
) (*connect.Response[gopb.GetProjectResponse], error) {
	proj, err := s.server.projectMgr.CurrentProject()
	if err != nil || proj == nil {
		return nil, connect.NewError(connect.CodeNotFound, fmt.Errorf("no project selected"))
	}

	homeDir := filepath.Join(proj.Path, ".stackpanel")
	return connect.NewResponse(&gopb.GetProjectResponse{
		Project: &gopb.Project{
			Path:   proj.Path,
			Name:   proj.Name,
			Github: "", // TODO: Read from nix config
			Dirs: &gopb.Directories{
				Home:    homeDir,
				Data:    filepath.Join(homeDir, "data"),
				Gen:     filepath.Join(homeDir, "gen"),
				State:   filepath.Join(homeDir, "state"),
				Secrets: filepath.Join(homeDir, "secrets"),
			},
		},
	}), nil
}

// =============================================================================
// Config Entity CRUD - Now generated in connect_entities_gen.go
// =============================================================================
// The following methods are auto-generated from proto definitions:
// - GetConfig, SetConfig
// - GetSecrets, SetSecrets
// - GetUsers, SetUsers
// - GetAws, SetAws
// - GetApps, SetApps
// - GetVariables, SetVariables
//
// To add a new entity:
// 1. Add the Get/Set RPC methods to agent.proto
// 2. Run `./generate.sh` in packages/proto
// 3. The handlers will be auto-generated

// =============================================================================
// Age Identity Management
// =============================================================================

func (s *AgentServiceServer) GetAgeIdentity(
	ctx context.Context,
	req *connect.Request[gopb.GetAgeIdentityRequest],
) (*connect.Response[gopb.AgeIdentityResponse], error) {
	// When backend is chamber, AGE identity is not applicable
	if s.server.getVariablesBackend() == "chamber" {
		return connect.NewResponse(&gopb.AgeIdentityResponse{
			Type:      "not_applicable",
			Value:     "Variables backend is set to 'chamber' - AGE identity is not used",
			KeyPath:   "",
			PublicKey: "",
		}), nil
	}

	identityFile := s.server.getAgeIdentityPath()
	resp := &gopb.AgeIdentityResponse{
		Type:      "",
		Value:     "",
		KeyPath:   "",
		PublicKey: "",
	}

	data, err := os.ReadFile(identityFile)
	if err != nil {
		if os.IsNotExist(err) {
			return connect.NewResponse(resp), nil
		}
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to read identity: %w", err))
	}

	value := strings.TrimSpace(string(data))
	if value == "" {
		return connect.NewResponse(resp), nil
	}

	if isAgeKeyContent(value) {
		resp.Type = "key"
		resp.Value = "(key stored)"
		resp.KeyPath = s.server.getAgeIdentityKeyPath()
	} else {
		resp.Type = "path"
		resp.Value = value
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

	return connect.NewResponse(resp), nil
}

func (s *AgentServiceServer) SetAgeIdentity(
	ctx context.Context,
	req *connect.Request[gopb.SetAgeIdentityRequest],
) (*connect.Response[gopb.AgeIdentityResponse], error) {
	stateDir := filepath.Join(s.server.config.ProjectRoot, ".stackpanel", "state")
	if err := os.MkdirAll(stateDir, 0700); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to create state dir: %w", err))
	}

	identityFile := s.server.getAgeIdentityPath()
	keyFile := s.server.getAgeIdentityKeyPath()
	value := strings.TrimSpace(req.Msg.Value)

	resp := &gopb.AgeIdentityResponse{}

	if value == "" {
		os.Remove(identityFile)
		os.Remove(keyFile)
		return connect.NewResponse(resp), nil
	}

	if isAgeKeyContent(value) {
		if err := os.WriteFile(keyFile, []byte(value), 0600); err != nil {
			return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to write key: %w", err))
		}
		if err := os.WriteFile(identityFile, []byte("AGE-SECRET-KEY-..."), 0600); err != nil {
			return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to write identity: %w", err))
		}
		resp.Type = "key"
		resp.Value = "(key stored)"
		resp.KeyPath = keyFile
		log.Info().Str("keyPath", keyFile).Msg("Age identity key stored")
	} else {
		expandedPath := value
		if strings.HasPrefix(value, "~") {
			if home, err := os.UserHomeDir(); err == nil {
				expandedPath = filepath.Join(home, value[1:])
			}
		}

		if _, err := os.Stat(expandedPath); err != nil {
			return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("key file not found: %s", expandedPath))
		}

		if err := os.WriteFile(identityFile, []byte(value), 0600); err != nil {
			return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to write identity: %w", err))
		}
		os.Remove(keyFile)

		resp.Type = "path"
		resp.Value = value
		resp.KeyPath = expandedPath
		log.Info().Str("path", value).Str("expanded", expandedPath).Msg("Age identity path stored")
	}

	return connect.NewResponse(resp), nil
}

// =============================================================================
// KMS Configuration
// =============================================================================

func (s *AgentServiceServer) GetKMSConfig(
	ctx context.Context,
	req *connect.Request[gopb.GetKMSConfigRequest],
) (*connect.Response[gopb.KMSConfigResponse], error) {
	// When backend is chamber, KMS is always enabled (forced by Nix config)
	if s.server.getVariablesBackend() == "chamber" {
		resp := &gopb.KMSConfigResponse{
			Enable:     true,
			KeyArn:     "",
			AwsProfile: "",
			Source:     "chamber",
		}

		// Try to get the actual KMS ARN from state if available
		configFile := s.server.getKMSConfigPath()
		data, err := os.ReadFile(configFile)
		if err == nil {
			var stateConfig KMSConfigResponse
			if err := json.Unmarshal(data, &stateConfig); err == nil {
				resp.KeyArn = stateConfig.KeyArn
				resp.AwsProfile = stateConfig.AwsProfile
			}
		}

		return connect.NewResponse(resp), nil
	}

	configFile := s.server.getKMSConfigPath()
	resp := &gopb.KMSConfigResponse{
		Enable:     false,
		KeyArn:     "",
		AwsProfile: "",
		Source:     "",
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		if os.IsNotExist(err) {
			return connect.NewResponse(resp), nil
		}
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to read KMS config: %w", err))
	}

	var stateConfig KMSConfigResponse
	if err := json.Unmarshal(data, &stateConfig); err == nil {
		resp.Enable = stateConfig.Enable
		resp.KeyArn = stateConfig.KeyArn
		resp.AwsProfile = stateConfig.AwsProfile
	}

	resp.Source = "state"
	return connect.NewResponse(resp), nil
}

func (s *AgentServiceServer) SetKMSConfig(
	ctx context.Context,
	req *connect.Request[gopb.SetKMSConfigRequest],
) (*connect.Response[gopb.KMSConfigResponse], error) {
	// Validate KMS ARN format if provided
	if req.Msg.Enable && req.Msg.KeyArn != "" {
		if !strings.HasPrefix(req.Msg.KeyArn, "arn:aws:kms:") {
			return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("invalid KMS ARN format"))
		}
	}

	resp := &gopb.KMSConfigResponse{
		Enable:     req.Msg.Enable,
		KeyArn:     req.Msg.KeyArn,
		AwsProfile: req.Msg.AwsProfile,
		Source:     "state",
	}

	// TODO: Save to file
	log.Info().Bool("enable", req.Msg.Enable).Str("keyArn", req.Msg.KeyArn).Msg("KMS config saved")

	return connect.NewResponse(resp), nil
}

// =============================================================================
// File Operations
// =============================================================================

func (s *AgentServiceServer) ReadFile(
	ctx context.Context,
	req *connect.Request[gopb.ReadFileRequest],
) (*connect.Response[gopb.ReadFileResponse], error) {
	path := req.Msg.Path
	if !filepath.IsAbs(path) {
		path = filepath.Join(s.server.config.ProjectRoot, path)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return connect.NewResponse(&gopb.ReadFileResponse{Exists: false}), nil
		}
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to read file: %w", err))
	}

	return connect.NewResponse(&gopb.ReadFileResponse{
		Content: string(data),
		Exists:  true,
	}), nil
}

func (s *AgentServiceServer) WriteFile(
	ctx context.Context,
	req *connect.Request[gopb.WriteFileRequest],
) (*connect.Response[gopb.WriteFileResponse], error) {
	path := req.Msg.Path
	if !filepath.IsAbs(path) {
		path = filepath.Join(s.server.config.ProjectRoot, path)
	}

	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to create directory: %w", err))
	}

	mode := os.FileMode(req.Msg.Mode)
	if mode == 0 {
		mode = 0644
	}

	if err := os.WriteFile(path, []byte(req.Msg.Content), mode); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to write file: %w", err))
	}

	return connect.NewResponse(&gopb.WriteFileResponse{Success: true}), nil
}

func (s *AgentServiceServer) ListFiles(
	ctx context.Context,
	req *connect.Request[gopb.ListFilesRequest],
) (*connect.Response[gopb.ListFilesResponse], error) {
	path := req.Msg.Path
	if !filepath.IsAbs(path) {
		path = filepath.Join(s.server.config.ProjectRoot, path)
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to list directory: %w", err))
	}

	var files []*gopb.FileInfo
	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil {
			continue
		}
		files = append(files, &gopb.FileInfo{
			Name:    entry.Name(),
			Path:    filepath.Join(path, entry.Name()),
			IsDir:   entry.IsDir(),
			Size:    info.Size(),
			ModTime: info.ModTime().Unix(),
		})
	}

	return connect.NewResponse(&gopb.ListFilesResponse{Files: files}), nil
}

// =============================================================================
// Command Execution
// =============================================================================

func (s *AgentServiceServer) Exec(
	ctx context.Context,
	req *connect.Request[gopb.ExecRequest],
) (*connect.Response[gopb.ExecResponse], error) {
	cmd := exec.CommandContext(ctx, req.Msg.Command, req.Msg.Args...)

	if req.Msg.Cwd != "" {
		cmd.Dir = req.Msg.Cwd
	} else {
		cmd.Dir = s.server.config.ProjectRoot
	}

	// Set environment
	cmd.Env = os.Environ()
	for k, v := range req.Msg.Env {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	stdout, _ := cmd.Output()
	var stderr string
	if exitErr, ok := cmd.ProcessState.ExitCode(), cmd.ProcessState != nil; ok {
		_ = exitErr
	}

	exitCode := 0
	if cmd.ProcessState != nil {
		exitCode = cmd.ProcessState.ExitCode()
	}

	return connect.NewResponse(&gopb.ExecResponse{
		ExitCode: int32(exitCode),
		Stdout:   string(stdout),
		Stderr:   stderr,
	}), nil
}

// =============================================================================
// Nix Operations
// =============================================================================

func (s *AgentServiceServer) NixGenerate(
	ctx context.Context,
	req *connect.Request[gopb.NixGenerateRequest],
) (*connect.Response[gopb.NixGenerateResponse], error) {
	cmd := exec.CommandContext(ctx, "nix", "run", ".#gen")
	cmd.Dir = s.server.config.ProjectRoot

	output, err := cmd.CombinedOutput()
	if err != nil {
		return connect.NewResponse(&gopb.NixGenerateResponse{
			Success: false,
			Output:  string(output),
		}), nil
	}

	return connect.NewResponse(&gopb.NixGenerateResponse{
		Success: true,
		Output:  string(output),
	}), nil
}

func (s *AgentServiceServer) NixEval(
	ctx context.Context,
	req *connect.Request[gopb.NixEvalRequest],
) (*connect.Response[gopb.NixEvalResponse], error) {
	args := []string{"eval", "--impure"}
	if req.Msg.Json {
		args = append(args, "--json")
	}
	args = append(args, "--expr", req.Msg.Expression)

	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Dir = s.server.config.ProjectRoot

	output, err := cmd.Output()
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("nix eval failed: %w", err))
	}

	return connect.NewResponse(&gopb.NixEvalResponse{
		Result: string(output),
	}), nil
}

// =============================================================================
// Services (process-compose)
// =============================================================================

func (s *AgentServiceServer) GetServicesStatus(
	ctx context.Context,
	req *connect.Request[gopb.GetServicesStatusRequest],
) (*connect.Response[gopb.GetServicesStatusResponse], error) {
	resp := &gopb.GetServicesStatusResponse{
		Running:  false,
		Services: []*gopb.ServiceStatus{},
	}

	// Query process-compose for running processes
	res, err := s.server.exec.Run("process-compose", "process", "list", "-j")
	if err != nil || res.ExitCode != 0 {
		// process-compose not running or not available
		return connect.NewResponse(resp), nil
	}

	// Parse JSON output (try { data: [...] } format first, then plain array)
	type pcProcess struct {
		Name       string `json:"name"`
		Namespace  string `json:"namespace"`
		Status     string `json:"status"`
		PID        int    `json:"pid"`
		SystemTime string `json:"system_time"`
	}

	var processes []pcProcess

	var wrapped struct {
		Data []pcProcess `json:"data"`
	}
	if err := json.Unmarshal([]byte(res.Stdout), &wrapped); err == nil {
		processes = wrapped.Data
	} else {
		// Try plain array
		_ = json.Unmarshal([]byte(res.Stdout), &processes)
	}

	// Filter for processes in the "services" namespace
	anyRunning := false
	for _, p := range processes {
		if p.Namespace != "services" {
			continue
		}
		status := "stopped"
		if isProcessRunning(p.Status) {
			status = "running"
			anyRunning = true
		}
		resp.Services = append(resp.Services, &gopb.ServiceStatus{
			Name:   p.Name,
			Status: status,
			Pid:    int32(p.PID),
		})
	}
	resp.Running = anyRunning

	return connect.NewResponse(resp), nil
}

func (s *AgentServiceServer) StartService(
	ctx context.Context,
	req *connect.Request[gopb.ServiceRequest],
) (*connect.Response[gopb.ServiceResponse], error) {
	name := req.Msg.Name
	if name == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("service name required"))
	}

	res, err := s.server.exec.Run("process-compose", "process", "start", name)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to start service: %w", err))
	}
	if res.ExitCode != 0 {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("process-compose start failed: %s", res.Stderr))
	}

	log.Info().Str("service", name).Msg("Service started via process-compose")
	return connect.NewResponse(&gopb.ServiceResponse{
		Success: true,
		Message: fmt.Sprintf("Service %s started", name),
	}), nil
}

func (s *AgentServiceServer) StopService(
	ctx context.Context,
	req *connect.Request[gopb.ServiceRequest],
) (*connect.Response[gopb.ServiceResponse], error) {
	name := req.Msg.Name
	if name == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("service name required"))
	}

	res, err := s.server.exec.Run("process-compose", "process", "stop", name)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to stop service: %w", err))
	}
	if res.ExitCode != 0 {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("process-compose stop failed: %s", res.Stderr))
	}

	log.Info().Str("service", name).Msg("Service stopped via process-compose")
	return connect.NewResponse(&gopb.ServiceResponse{
		Success: true,
		Message: fmt.Sprintf("Service %s stopped", name),
	}), nil
}

func (s *AgentServiceServer) RestartService(
	ctx context.Context,
	req *connect.Request[gopb.ServiceRequest],
) (*connect.Response[gopb.ServiceResponse], error) {
	name := req.Msg.Name
	if name == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("service name required"))
	}

	res, err := s.server.exec.Run("process-compose", "process", "restart", name)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to restart service: %w", err))
	}
	if res.ExitCode != 0 {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("process-compose restart failed: %s", res.Stderr))
	}

	log.Info().Str("service", name).Msg("Service restarted via process-compose")
	return connect.NewResponse(&gopb.ServiceResponse{
		Success: true,
		Message: fmt.Sprintf("Service %s restarted", name),
	}), nil
}

// =============================================================================
// Devshell Management
// =============================================================================

func (s *AgentServiceServer) GetShellStatus(
	ctx context.Context,
	req *connect.Request[gopb.GetShellStatusRequest],
) (*connect.Response[gopb.ShellStatusResponse], error) {
	if s.server.shellManager == nil {
		return connect.NewResponse(&gopb.ShellStatusResponse{
			Stale:      false,
			Rebuilding: false,
		}), nil
	}

	status := s.server.shellManager.Status()

	var lastBuilt, lastNixChange string
	if !status.LastBuilt.IsZero() {
		lastBuilt = status.LastBuilt.Format("2006-01-02T15:04:05Z07:00")
	}
	if !status.LastNixChange.IsZero() {
		lastNixChange = status.LastNixChange.Format("2006-01-02T15:04:05Z07:00")
	}

	return connect.NewResponse(&gopb.ShellStatusResponse{
		Stale:         status.Stale,
		Rebuilding:    status.Rebuilding,
		LastBuilt:     lastBuilt,
		LastNixChange: lastNixChange,
		ChangedFiles:  status.ChangedFiles,
	}), nil
}

func (s *AgentServiceServer) RebuildShell(
	ctx context.Context,
	req *connect.Request[gopb.RebuildShellRequest],
	stream *connect.ServerStream[gopb.RebuildShellEvent],
) error {
	if s.server.shellManager == nil {
		return connect.NewError(connect.CodeFailedPrecondition, fmt.Errorf("no project is open"))
	}

	method := req.Msg.Method
	if method == "" {
		method = "devshell"
	}

	events := make(chan RebuildEvent, 100)

	// Start rebuild in goroutine
	go func() {
		defer close(events)
		if err := s.server.shellManager.Rebuild(ctx, method, events); err != nil {
			log.Warn().Err(err).Msg("Shell rebuild error")
		}
	}()

	// Stream events to client
	for event := range events {
		pbEvent := &gopb.RebuildShellEvent{
			Type:      event.Type,
			Output:    event.Output,
			ExitCode:  int32(event.ExitCode),
			Error:     event.Error,
			Timestamp: event.Timestamp.Format("2006-01-02T15:04:05Z07:00"),
		}

		if err := stream.Send(pbEvent); err != nil {
			return err
		}
	}

	return nil
}
