package server

import (
	"context"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"

	"connectrpc.com/connect"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
)

// newV1TestServer serves the v1 routes with a token validator that accepts
// only "good" and a ProjectService whose methods all return Unimplemented,
// so reaching a handler is distinguishable from being rejected by auth.
func newV1TestServer(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	routes := newV1Routes("1.2.3", func(token string) bool { return token == "good" },
		agentv1connect.UnimplementedProjectServiceHandler{})
	for _, r := range routes {
		mux.Handle(r.path, r.handler)
	}
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func TestGetAgentInfoIsPublicAndListsServedProcedures(t *testing.T) {
	srv := newV1TestServer(t)
	client := agentv1connect.NewAgentServiceClient(srv.Client(), srv.URL)

	res, err := client.GetAgentInfo(context.Background(), connect.NewRequest(&agentv1.GetAgentInfoRequest{}))
	if err != nil {
		t.Fatalf("GetAgentInfo without a token: %v", err)
	}
	if got := res.Msg.GetVersion(); got != "1.2.3" {
		t.Errorf("version = %q, want 1.2.3", got)
	}
	for _, want := range []string{
		agentv1connect.AgentServiceGetAgentInfoProcedure,
		agentv1connect.ProjectServiceListProjectsProcedure,
		agentv1connect.ProjectServiceAddProjectProcedure,
		agentv1connect.ProjectServiceRemoveProjectProcedure,
		agentv1connect.ProjectServiceSetDefaultProjectProcedure,
	} {
		if !slices.Contains(res.Msg.GetProcedures(), want) {
			t.Errorf("procedures missing %s; got %v", want, res.Msg.GetProcedures())
		}
	}
}

func TestV1ProceduresRequireBearerToken(t *testing.T) {
	srv := newV1TestServer(t)
	client := agentv1connect.NewProjectServiceClient(srv.Client(), srv.URL)

	cases := []struct {
		name          string
		authorization string
		want          connect.Code
	}{
		{"no header", "", connect.CodeUnauthenticated},
		{"wrong scheme", "Token good", connect.CodeUnauthenticated},
		{"invalid token", "Bearer bad", connect.CodeUnauthenticated},
		// A valid token reaches the (unimplemented) handler.
		{"valid token", "Bearer good", connect.CodeUnimplemented},
		{"scheme is case-insensitive", "bearer good", connect.CodeUnimplemented},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := connect.NewRequest(&agentv1.ListProjectsRequest{})
			if tc.authorization != "" {
				req.Header().Set("Authorization", tc.authorization)
			}
			_, err := client.ListProjects(context.Background(), req)
			if got := connect.CodeOf(err); got != tc.want {
				t.Errorf("code = %v, want %v (err: %v)", got, tc.want, err)
			}
		})
	}
}
