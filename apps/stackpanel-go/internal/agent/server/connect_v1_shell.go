package server

import (
	"context"
	"errors"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
)

var _ agentv1connect.ShellServiceHandler = shellService{}

// devshell is the part of ShellManager that ShellService uses.
type devshell interface {
	Status() ShellStatus
	Rebuild(ctx context.Context, method string, events chan<- RebuildEvent) error
}

// shellService implements stackpanel.agent.v1.ShellService against the
// request's project runtime.
type shellService struct {
	shellFor func(ctx context.Context) devshell
}

func newShellService() shellService {
	return shellService{shellFor: func(ctx context.Context) devshell { return runtimeFor(ctx).shell }}
}

func (s shellService) GetShellStatus(
	ctx context.Context,
	_ *connect.Request[agentv1.GetShellStatusRequest],
) (*connect.Response[agentv1.GetShellStatusResponse], error) {
	st := s.shellFor(ctx).Status()
	res := &agentv1.GetShellStatusResponse{
		Stale:        st.Stale,
		Rebuilding:   st.Rebuilding,
		ChangedFiles: st.ChangedFiles,
	}
	if !st.LastBuilt.IsZero() {
		res.LastBuiltAt = timestamppb.New(st.LastBuilt)
	}
	if !st.LastNixChange.IsZero() {
		res.LastNixChangeAt = timestamppb.New(st.LastNixChange)
	}
	return connect.NewResponse(res), nil
}

func (s shellService) RebuildShell(
	ctx context.Context,
	req *connect.Request[agentv1.RebuildShellRequest],
	stream *connect.ServerStream[agentv1.RebuildShellResponse],
) error {
	method := "devshell"
	if req.Msg.GetMethod() == agentv1.RebuildMethod_REBUILD_METHOD_NIX_DEVELOP {
		method = "nix"
	}

	events := make(chan RebuildEvent, 100)
	done := make(chan error, 1)
	shell := s.shellFor(ctx)
	go func() {
		defer close(events)
		done <- shell.Rebuild(ctx, method, events)
	}()

	// Keep draining after a failure so the rebuild goroutine never blocks on
	// a full channel; report the failure once the stream of events ends.
	var failure error
	for ev := range events {
		if failure != nil {
			continue
		}
		msg, err := rebuildEventToProto(ev)
		if err != nil {
			failure = err
			continue
		}
		if msg == nil {
			continue
		}
		if err := stream.Send(msg); err != nil {
			failure = err
		}
	}

	if err := <-done; err != nil {
		var inProgress *RebuildInProgressError
		if errors.As(err, &inProgress) {
			return connect.NewError(connect.CodeFailedPrecondition, err)
		}
		if failure == nil {
			return connect.NewError(connect.CodeInternal, err)
		}
	}
	return failure
}

// rebuildEventToProto maps a ShellManager event onto the stream. Error events
// become the stream's terminal error rather than a message; unknown event
// types are skipped.
func rebuildEventToProto(ev RebuildEvent) (*agentv1.RebuildShellResponse, error) {
	switch ev.Type {
	case "started":
		return &agentv1.RebuildShellResponse{
			Event: &agentv1.RebuildShellResponse_Started{Started: &agentv1.RebuildStarted{}},
		}, nil
	case "output":
		return &agentv1.RebuildShellResponse{
			Event: &agentv1.RebuildShellResponse_OutputLine{OutputLine: ev.Output},
		}, nil
	case "completed":
		return &agentv1.RebuildShellResponse{
			Event: &agentv1.RebuildShellResponse_Completed{
				Completed: &agentv1.RebuildCompleted{ExitCode: int32(ev.ExitCode)},
			},
		}, nil
	case "error":
		return nil, connect.NewError(connect.CodeInternal, errors.New(ev.Error))
	default:
		return nil, nil
	}
}
