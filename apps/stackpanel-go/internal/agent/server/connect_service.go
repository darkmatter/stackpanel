// connect_service.go implements the core Connect-RPC AgentService handlers for
// project info and command execution.

package server

import (
	"context"
	"fmt"
	"path/filepath"

	"connectrpc.com/connect"
	gopb "github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
)

// AgentServiceServer implements the Connect-RPC AgentService interface.
// It delegates to the underlying *Server for all state and I/O, acting as a
// thin proto-to-Go translation layer. The REST handlers in api_handlers.go
// provide equivalent functionality for simpler endpoints.
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

// GetProject returns the currently active project and its well-known directory paths.
// The .stack/ subdirectories follow a fixed layout: data/, gen/, state/, secrets/.
func (s *AgentServiceServer) GetProject(
	ctx context.Context,
	req *connect.Request[gopb.GetProjectRequest],
) (*connect.Response[gopb.GetProjectResponse], error) {
	proj, err := s.server.projectMgr.CurrentProject()
	if err != nil || proj == nil {
		return nil, connect.NewError(
			connect.CodeNotFound,
			fmt.Errorf("no project selected"),
		)
	}

	homeDir := filepath.Join(proj.Path, ".stack")
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
// Config Entity Reads - generated in connect_entities_gen.go
// =============================================================================
// GetSecrets, GetUsers, GetApps, GetVariables, and GetModuleOutputs are
// generated from agent.proto by protoc-gen-connect-handlers.

// =============================================================================
// Command Execution
// =============================================================================

func (s *AgentServiceServer) Exec(
	ctx context.Context,
	req *connect.Request[gopb.ExecRequest],
) (*connect.Response[gopb.ExecResponse], error) {
	cwd := s.server.config.ProjectRoot
	if req.Msg.Cwd != "" {
		cwd = req.Msg.Cwd
	}

	// Proto uses map[string]string; the executor expects KEY=value slices
	var env []string
	for k, v := range req.Msg.Env {
		env = append(env, fmt.Sprintf("%s=%s", k, v))
	}

	res, err := s.server.exec.RunWithOptions(req.Msg.Command, cwd, env, req.Msg.Args...)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	return connect.NewResponse(&gopb.ExecResponse{
		ExitCode: int32(res.ExitCode),
		Stdout:   res.Stdout,
		Stderr:   res.Stderr,
	}), nil
}
