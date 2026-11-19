package server

import (
	"context"
	"path/filepath"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
	sharedexec "github.com/darkmatter/stackpanel/stackpanel-go/pkg/exec"
)

// LocalModules runs the agent's module operations directly for the trusted
// local CLI. There is no listener, pairing token, or saved active project.
type LocalModules struct {
	*moduleService
}

func NewLocalModules(
	ctx context.Context,
	projectRoot string,
) (context.Context, *LocalModules, error) {
	root, err := filepath.Abs(projectRoot)
	if err != nil {
		return nil, nil, err
	}
	cfg := config.DefaultConfig()
	cfg.ProjectRoot = root
	mgr, err := project.NewManager(cfg.DataDir)
	if err != nil {
		return nil, nil, err
	}
	s := &Server{config: cfg, projectMgr: mgr}
	// Registry reads and config patches do not need an eager, potentially
	// minutes-long nix print-dev-env; actions resolve their declared executables.
	exec, err := sharedexec.NewWithoutDevshell(root, cfg.AllowedCommands)
	if err != nil {
		return nil, nil, err
	}
	rt := s.newProjectRuntime(root, exec)
	return context.WithValue(
			ctx,
			runtimeKey{},
			rt,
		), &LocalModules{
			&moduleService{s: s},
		}, nil
}

// ExecuteAction delivers the same event stream as RunModuleAction without
// serializing through a loopback HTTP connection.
func (m *LocalModules) ExecuteAction(
	ctx context.Context,
	req *agentv1.RunModuleActionRequest,
	send func(*agentv1.RunModuleActionResponse) error,
) error {
	return m.runModuleAction(ctx, req, send)
}
