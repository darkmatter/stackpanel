// connect_service.go implements the core Connect-RPC AgentService handlers for
// project info, command execution, and devshell status and rebuild streaming.

package server

import (
	"context"
	"fmt"
	"path/filepath"

	"connectrpc.com/connect"
	gopb "github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
	"github.com/rs/zerolog/log"
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

// =============================================================================
// Devshell Management
// =============================================================================

// GetShellStatus reports whether the Nix devshell is stale (nix files changed
// since last build) or currently rebuilding. The web UI uses this to show a
// "rebuild needed" banner.
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

// RebuildShell triggers a devshell rebuild and streams progress events to the client.
// This is a server-streaming RPC — the client receives events as the build progresses
// (output lines, completion status, errors) rather than waiting for the full result.
func (s *AgentServiceServer) RebuildShell(
	ctx context.Context,
	req *connect.Request[gopb.RebuildShellRequest],
	stream *connect.ServerStream[gopb.RebuildShellEvent],
) error {
	if s.server.shellManager == nil {
		return connect.NewError(
			connect.CodeFailedPrecondition,
			fmt.Errorf("no project is open"),
		)
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
