package server

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync/atomic"
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

// recordingProjects is a ProjectService whose AddProject records that it ran,
// so a request rejected before the handler is distinguishable from one that
// reached it.
type recordingProjects struct {
	agentv1connect.UnimplementedProjectServiceHandler
	called atomic.Bool
}

func (p *recordingProjects) AddProject(
	context.Context,
	*connect.Request[agentv1.AddProjectRequest],
) (*connect.Response[agentv1.AddProjectResponse], error) {
	p.called.Store(true)
	return connect.NewResponse(&agentv1.AddProjectResponse{}), nil
}

// countingBody counts the request bytes the server reads off the wire.
type countingBody struct {
	io.ReadCloser
	n *atomic.Int64
}

func (b countingBody) Read(p []byte) (int, error) {
	n, err := b.ReadCloser.Read(p)
	b.n.Add(int64(n))
	return n, err
}

func TestV1RejectsOversizedRequestsBeforeAuth(t *testing.T) {
	var authRan atomic.Bool
	var wireBytes atomic.Int64
	projects := &recordingProjects{}
	mux := http.NewServeMux()
	routes := newV1Routes("1.2.3", func(string) bool { authRan.Store(true); return false }, projects)
	for _, r := range routes {
		mux.Handle(r.path, http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			req.Body = countingBody{req.Body, &wireBytes}
			r.handler.ServeHTTP(w, req)
		}))
	}
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	// Just over the limit, and compressible enough that the gzip case sends a
	// few KiB that only inflate past it on the server.
	path := strings.Repeat("a", v1ReadMaxBytes+1024)
	cases := []struct {
		name         string
		opts         []connect.ClientOption
		maxWireBytes int64
	}{
		{"uncompressed", nil, 0},
		{"gzip inflates past the limit", []connect.ClientOption{connect.WithSendGzip()}, 64 << 10},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			wireBytes.Store(0)
			client := agentv1connect.NewProjectServiceClient(srv.Client(), srv.URL, tc.opts...)
			// An invalid token: if auth ran first, the call would fail with
			// Unauthenticated instead.
			req := connect.NewRequest(&agentv1.AddProjectRequest{Path: path})
			req.Header().Set("Authorization", "Bearer bad")
			_, err := client.AddProject(context.Background(), req)
			if got := connect.CodeOf(err); got != connect.CodeResourceExhausted {
				t.Fatalf("code = %v, want %v (err: %v)", got, connect.CodeResourceExhausted, err)
			}
			if tc.maxWireBytes > 0 && wireBytes.Load() > tc.maxWireBytes {
				t.Errorf("sent %d bytes; the gzip case must fail on the inflated size", wireBytes.Load())
			}
		})
	}
	if authRan.Load() {
		t.Error("token validation ran for an oversized request")
	}
	if projects.called.Load() {
		t.Error("AddProject ran for an oversized request")
	}
}
