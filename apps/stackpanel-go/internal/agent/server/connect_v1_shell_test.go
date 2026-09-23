package server

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"
	"time"

	"connectrpc.com/connect"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
)

// fakeShell replays scripted rebuild events and records the method it got.
type fakeShell struct {
	status ShellStatus
	events []RebuildEvent
	err    error
	method string
}

func (f *fakeShell) Status() ShellStatus { return f.status }

func (f *fakeShell) Rebuild(_ context.Context, method string, events chan<- RebuildEvent) error {
	f.method = method
	for _, ev := range f.events {
		events <- ev
	}
	return f.err
}

func newShellTestClient(t *testing.T, shell devshell) agentv1connect.ShellServiceClient {
	t.Helper()
	mux := http.NewServeMux()
	mux.Handle(agentv1connect.NewShellServiceHandler(shellService{
		shellFor: func(context.Context) devshell { return shell },
	}))
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return agentv1connect.NewShellServiceClient(srv.Client(), srv.URL)
}

// collect reads the whole rebuild stream.
func collect(t *testing.T, client agentv1connect.ShellServiceClient, method agentv1.RebuildMethod) ([]*agentv1.RebuildShellResponse, error) {
	t.Helper()
	stream, err := client.RebuildShell(context.Background(), connect.NewRequest(&agentv1.RebuildShellRequest{Method: method}))
	if err != nil {
		return nil, err
	}
	var got []*agentv1.RebuildShellResponse
	for stream.Receive() {
		got = append(got, stream.Msg())
	}
	return got, stream.Err()
}

func TestGetShellStatusReportsTheProjectShell(t *testing.T) {
	built := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	client := newShellTestClient(t, &fakeShell{status: ShellStatus{
		Stale:        true,
		LastBuilt:    built,
		ChangedFiles: []string{"flake.nix", ".stack/config.nix"},
	}})

	res, err := client.GetShellStatus(context.Background(), connect.NewRequest(&agentv1.GetShellStatusRequest{}))
	if err != nil {
		t.Fatalf("GetShellStatus: %v", err)
	}
	msg := res.Msg
	if !msg.GetStale() || msg.GetRebuilding() {
		t.Errorf("stale=%v rebuilding=%v, want true/false", msg.GetStale(), msg.GetRebuilding())
	}
	if got := msg.GetLastBuiltAt().AsTime(); !got.Equal(built) {
		t.Errorf("last_built_at = %v, want %v", got, built)
	}
	if msg.GetLastNixChangeAt() != nil {
		t.Error("last_nix_change_at should be unset when the shell never saw a change")
	}
	if !slices.Equal(msg.GetChangedFiles(), []string{"flake.nix", ".stack/config.nix"}) {
		t.Errorf("changed_files = %v", msg.GetChangedFiles())
	}
}

func TestRebuildShellStreamsStartedOutputAndCompleted(t *testing.T) {
	shell := &fakeShell{events: []RebuildEvent{
		{Type: "started"},
		{Type: "output", Output: "building devshell"},
		{Type: "completed", ExitCode: 3},
	}}
	client := newShellTestClient(t, shell)

	got, err := collect(t, client, agentv1.RebuildMethod_REBUILD_METHOD_UNSPECIFIED)
	if err != nil {
		t.Fatalf("stream error: %v", err)
	}
	if len(got) != 3 || got[0].GetStarted() == nil ||
		got[1].GetOutputLine() != "building devshell" ||
		got[2].GetCompleted().GetExitCode() != 3 {
		t.Fatalf("unexpected stream: %v", got)
	}
	if shell.method != "devshell" {
		t.Errorf("unspecified method ran %q, want devshell", shell.method)
	}
}

func TestRebuildShellEndsWithAnErrorAfterEarlierOutput(t *testing.T) {
	shell := &fakeShell{
		events: []RebuildEvent{
			{Type: "started"},
			{Type: "output", Output: "evaluating"},
			{Type: "error", Error: "nix develop exited early"},
			{Type: "output", Output: "never delivered"},
		},
		err: errors.New("nix develop exited early"),
	}
	client := newShellTestClient(t, shell)

	got, err := collect(t, client, agentv1.RebuildMethod_REBUILD_METHOD_NIX_DEVELOP)
	if connect.CodeOf(err) != connect.CodeInternal {
		t.Fatalf("stream error code = %v (%v), want Internal", connect.CodeOf(err), err)
	}
	if len(got) != 2 || got[1].GetOutputLine() != "evaluating" {
		t.Errorf("messages before the error = %v, want started and the first output", got)
	}
	if shell.method != "nix" {
		t.Errorf("NIX_DEVELOP ran %q, want nix", shell.method)
	}
}

func TestRebuildShellRejectsAConcurrentRebuild(t *testing.T) {
	client := newShellTestClient(t, &fakeShell{err: &RebuildInProgressError{}})

	if _, err := collect(t, client, agentv1.RebuildMethod_REBUILD_METHOD_DEVSHELL); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Errorf("code = %v (%v), want FailedPrecondition", connect.CodeOf(err), err)
	}
}
