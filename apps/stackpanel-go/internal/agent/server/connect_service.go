// Package server provides the HTTP/SSE server for the stackpanel agent.
package server

import (
	"context"
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
// Config Entity CRUD
// =============================================================================

func (s *AgentServiceServer) GetConfig(
	ctx context.Context,
	req *connect.Request[gopb.GetConfigRequest],
) (*connect.Response[gopb.Config], error) {
	// TODO: Read from .stackpanel/data/config.nix and parse
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) SetConfig(
	ctx context.Context,
	req *connect.Request[gopb.Config],
) (*connect.Response[gopb.Config], error) {
	// TODO: Write to .stackpanel/data/config.nix
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) GetSecrets(
	ctx context.Context,
	req *connect.Request[gopb.GetSecretsRequest],
) (*connect.Response[gopb.Secrets], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) SetSecrets(
	ctx context.Context,
	req *connect.Request[gopb.Secrets],
) (*connect.Response[gopb.Secrets], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) GetUsers(
	ctx context.Context,
	req *connect.Request[gopb.GetUsersRequest],
) (*connect.Response[gopb.Users], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) SetUsers(
	ctx context.Context,
	req *connect.Request[gopb.Users],
) (*connect.Response[gopb.Users], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) GetAws(
	ctx context.Context,
	req *connect.Request[gopb.GetAwsRequest],
) (*connect.Response[gopb.Aws], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) SetAws(
	ctx context.Context,
	req *connect.Request[gopb.Aws],
) (*connect.Response[gopb.Aws], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) GetApps(
	ctx context.Context,
	req *connect.Request[gopb.GetAppsRequest],
) (*connect.Response[gopb.Apps], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) SetApps(
	ctx context.Context,
	req *connect.Request[gopb.Apps],
) (*connect.Response[gopb.Apps], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) GetVariables(
	ctx context.Context,
	req *connect.Request[gopb.GetVariablesRequest],
) (*connect.Response[gopb.Variables], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) SetVariables(
	ctx context.Context,
	req *connect.Request[gopb.Variables],
) (*connect.Response[gopb.Variables], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

// =============================================================================
// Age Identity Management
// =============================================================================

func (s *AgentServiceServer) GetAgeIdentity(
	ctx context.Context,
	req *connect.Request[gopb.GetAgeIdentityRequest],
) (*connect.Response[gopb.AgeIdentityResponse], error) {
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

	// Parse JSON config
	// For now, return the basic structure - we can add JSON parsing later
	_ = data
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
	// TODO: Implement process-compose status check
	return connect.NewResponse(&gopb.GetServicesStatusResponse{
		Running:  false,
		Services: nil,
	}), nil
}

func (s *AgentServiceServer) StartService(
	ctx context.Context,
	req *connect.Request[gopb.ServiceRequest],
) (*connect.Response[gopb.ServiceResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) StopService(
	ctx context.Context,
	req *connect.Request[gopb.ServiceRequest],
) (*connect.Response[gopb.ServiceResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}

func (s *AgentServiceServer) RestartService(
	ctx context.Context,
	req *connect.Request[gopb.ServiceRequest],
) (*connect.Response[gopb.ServiceResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, fmt.Errorf("not implemented"))
}
