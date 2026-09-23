package project

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"connectrpc.com/connect"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

var errGone = errors.New("project not found")

// newTestClient serves a ProjectService over a registry in a temp config dir.
// Validity is decided by the `invalid` set so tests don't depend on the real
// validators (which reject temp dirs as suspicious and evaluate Nix).
func newTestClient(t *testing.T, invalid map[string]bool) (agentv1connect.ProjectServiceClient, *userconfig.Manager) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	reg, err := userconfig.NewManager()
	if err != nil {
		t.Fatalf("userconfig.NewManager: %v", err)
	}

	check := func(path string) error {
		if invalid[path] {
			return errGone
		}
		return nil
	}
	mux := http.NewServeMux()
	mux.Handle(agentv1connect.NewProjectServiceHandler(&ConnectHandler{
		registry:    reg,
		checkListed: check,
		checkAdded:  check,
	}))
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return agentv1connect.NewProjectServiceClient(srv.Client(), srv.URL), reg
}

func TestListProjectsReportsValidityAndDefault(t *testing.T) {
	good := filepath.Join(t.TempDir(), "good")
	gone := filepath.Join(t.TempDir(), "gone")
	client, reg := newTestClient(t, map[string]bool{gone: true})

	goodProject, err := reg.AddProject(good, "")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := reg.AddProject(gone, ""); err != nil {
		t.Fatal(err)
	}
	if err := reg.SetDefaultProject(goodProject.Path); err != nil {
		t.Fatal(err)
	}

	res, err := client.ListProjects(context.Background(), connect.NewRequest(&agentv1.ListProjectsRequest{}))
	if err != nil {
		t.Fatalf("ListProjects: %v", err)
	}

	byPath := map[string]*agentv1.Project{}
	for _, p := range res.Msg.GetProjects() {
		byPath[p.GetPath()] = p
	}
	if len(byPath) != 2 {
		t.Fatalf("got %d projects, want 2", len(byPath))
	}
	if p := byPath[goodProject.Path]; !p.GetValid() || p.GetInvalidReason() != "" {
		t.Errorf("good project: valid=%v reason=%q, want valid", p.GetValid(), p.GetInvalidReason())
	}
	if p := byPath[filepath.Clean(gone)]; p.GetValid() || p.GetInvalidReason() != errGone.Error() {
		t.Errorf("gone project: valid=%v reason=%q, want invalid with reason", p.GetValid(), p.GetInvalidReason())
	}
	if got, want := res.Msg.GetDefaultProjectId(), byPath[goodProject.Path].GetId(); got != want {
		t.Errorf("default project id = %q, want %q", got, want)
	}
}

func TestAddProjectValidatesBeforeRegistering(t *testing.T) {
	bad := filepath.Join(t.TempDir(), "bad")
	client, reg := newTestClient(t, map[string]bool{bad: true})
	ctx := context.Background()

	for _, path := range []string{"relative/dir", bad} {
		_, err := client.AddProject(ctx, connect.NewRequest(&agentv1.AddProjectRequest{Path: path}))
		if connect.CodeOf(err) != connect.CodeInvalidArgument {
			t.Errorf("AddProject(%q) code = %v, want InvalidArgument", path, connect.CodeOf(err))
		}
	}
	if n := len(reg.ListProjects()); n != 0 {
		t.Fatalf("rejected paths were registered: %d projects", n)
	}

	dir := filepath.Join(t.TempDir(), "app")
	first, err := client.AddProject(ctx, connect.NewRequest(&agentv1.AddProjectRequest{Path: dir}))
	if err != nil {
		t.Fatalf("AddProject: %v", err)
	}
	again, err := client.AddProject(ctx, connect.NewRequest(&agentv1.AddProjectRequest{Path: dir}))
	if err != nil {
		t.Fatalf("AddProject again: %v", err)
	}
	if first.Msg.GetProject().GetId() != again.Msg.GetProject().GetId() || len(reg.ListProjects()) != 1 {
		t.Errorf("re-adding a registered path should return the existing project")
	}
}

func TestDefaultAndRemoveResolveProjectsByID(t *testing.T) {
	client, reg := newTestClient(t, nil)
	ctx := context.Background()

	p, err := reg.AddProject(filepath.Join(t.TempDir(), "app"), "")
	if err != nil {
		t.Fatal(err)
	}
	id := projectID(*p)

	if _, err := client.SetDefaultProject(ctx, connect.NewRequest(&agentv1.SetDefaultProjectRequest{ProjectId: id})); err != nil {
		t.Fatalf("SetDefaultProject: %v", err)
	}
	if got := reg.GetDefaultProjectPath(); got != p.Path {
		t.Errorf("default path = %q, want %q", got, p.Path)
	}
	if _, err := client.SetDefaultProject(ctx, connect.NewRequest(&agentv1.SetDefaultProjectRequest{})); err != nil {
		t.Fatalf("clear default: %v", err)
	}
	if reg.GetDefaultProject() != nil {
		t.Error("default project was not cleared")
	}

	_, err = client.RemoveProject(ctx, connect.NewRequest(&agentv1.RemoveProjectRequest{ProjectId: "no-such-id"}))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Errorf("RemoveProject(unknown) code = %v, want NotFound", connect.CodeOf(err))
	}
	if _, err := client.RemoveProject(ctx, connect.NewRequest(&agentv1.RemoveProjectRequest{ProjectId: id})); err != nil {
		t.Fatalf("RemoveProject: %v", err)
	}
	if n := len(reg.ListProjects()); n != 0 {
		t.Errorf("project still registered after RemoveProject: %d", n)
	}
}
