package server

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"connectrpc.com/connect"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
)

// TestProjectInterceptorRunsRequestsAgainstTheResolvedProject mounts
// ShellService behind the project interceptor. Each fake runtime reports its
// own root as a changed file, so the response shows which project ran.
func TestProjectInterceptorRunsRequestsAgainstTheResolvedProject(t *testing.T) {
	registry, _ := newTestRegistry()
	scope := projectInterceptor{
		runtimes: registry,
		resolve: func(id string) (string, error) {
			switch id {
			case "":
				return "/p/current", nil
			case "other":
				return "/p/other", nil
			default:
				return "", connect.NewError(connect.CodeNotFound, fmt.Errorf("unknown project %q", id))
			}
		},
	}
	shells := map[string]devshell{}
	svc := shellService{shellFor: func(ctx context.Context) devshell {
		root := runtimeFor(ctx).root
		if shells[root] == nil {
			shells[root] = &fakeShell{status: ShellStatus{ChangedFiles: []string{root}}}
		}
		return shells[root]
	}}

	mux := http.NewServeMux()
	mux.Handle(agentv1connect.NewShellServiceHandler(svc, connect.WithInterceptors(scope)))
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	client := agentv1connect.NewShellServiceClient(srv.Client(), srv.URL)

	status := func(projectID string) (string, error) {
		req := connect.NewRequest(&agentv1.GetShellStatusRequest{})
		if projectID != "" {
			req.Header().Set(projectHeader, projectID)
		}
		res, err := client.GetShellStatus(context.Background(), req)
		if err != nil {
			return "", err
		}
		return res.Msg.GetChangedFiles()[0], nil
	}

	if got, err := status(""); err != nil || got != "/p/current" {
		t.Errorf("no header: got %q, %v; want the current project", got, err)
	}
	if got, err := status("other"); err != nil || got != "/p/other" {
		t.Errorf("header other: got %q, %v; want /p/other", got, err)
	}
	if _, err := status("missing"); connect.CodeOf(err) != connect.CodeNotFound {
		t.Errorf("unknown project: code %v, want NotFound", connect.CodeOf(err))
	}
	if n := len(registry.runtimes); n != 2 {
		t.Errorf("registry holds %d runtimes, want one per resolved project", n)
	}
}

func TestResolveProjectRootFallsBackToCurrentThenDefault(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	mgr, err := project.NewManager(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	registry := mgr.UserConfigManager()
	def, err := registry.AddProject(filepath.Join(t.TempDir(), "default"), "")
	if err != nil {
		t.Fatal(err)
	}
	s := &Server{config: &config.Config{}, projectMgr: mgr}

	if _, err := s.resolveProjectRoot(""); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Errorf("nothing selected: code %v, want FailedPrecondition", connect.CodeOf(err))
	}
	if _, err := s.resolveProjectRoot("no-such-id"); connect.CodeOf(err) != connect.CodeNotFound {
		t.Errorf("unknown id: code %v, want NotFound", connect.CodeOf(err))
	}

	if err := registry.SetDefaultProject(def.Path); err != nil {
		t.Fatal(err)
	}
	if got, err := s.resolveProjectRoot(""); err != nil || got != def.Path {
		t.Errorf("no header, default set: got %q, %v; want %q", got, err, def.Path)
	}

	s.config.ProjectRoot = "/p/current"
	if got, err := s.resolveProjectRoot(""); err != nil || got != "/p/current" {
		t.Errorf("no header, current set: got %q, %v; want the current project first", got, err)
	}
}
