package server

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"connectrpc.com/connect"
	"github.com/rs/zerolog/log"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/reflect/protoregistry"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
)

// mountV1 serves the v1 Connect services (ADR 0004). CORS and the origin
// allowlist stay at the HTTP layer; authentication is part of the Connect
// interceptor chain so no procedure can be mounted without it.
func (s *Server) mountV1(mux *http.ServeMux) {
	routes := newV1Routes(s.config.Version, s.isValidToken, project.NewConnectHandler(s.projectMgr))
	for _, r := range routes {
		mux.Handle(r.path, s.withCORS(s.withAllowedOrigin(r.handler.ServeHTTP)))
	}
}

type v1Route struct {
	path    string
	handler http.Handler
}

// Connect reads and decompresses the body before interceptors run, so the limit must apply before auth.
const v1ReadMaxBytes = 2 << 20 // same 2 MiB cap as REST request bodies

// newV1Routes builds every v1 service behind one interceptor chain and
// reports exactly the procedures they serve through GetAgentInfo.
func newV1Routes(
	version string,
	validToken func(token string) bool,
	projects agentv1connect.ProjectServiceHandler,
) []v1Route {
	opts := connect.WithHandlerOptions(
		connect.WithReadMaxBytes(v1ReadMaxBytes),
		connect.WithInterceptors(authInterceptor{valid: validToken}),
		connect.WithRecover(recoverRPC),
	)
	info := &agentInfoService{version: version}

	routes := make([]v1Route, 0, 2)
	add := func(path string, handler http.Handler) {
		routes = append(routes, v1Route{path: path, handler: handler})
	}
	add(agentv1connect.NewAgentServiceHandler(info, opts))
	add(agentv1connect.NewProjectServiceHandler(projects, opts))

	info.procedures = procedurePaths(routes)
	return routes
}

// procedurePaths lists the procedures behind each mounted service path
// ("/<package>.<Service>/"), read from the registered descriptors so the
// list cannot drift from what is actually served.
func procedurePaths(routes []v1Route) []string {
	var out []string
	for _, r := range routes {
		name := protoreflect.FullName(strings.Trim(r.path, "/"))
		desc, err := protoregistry.GlobalFiles.FindDescriptorByName(name)
		if err != nil {
			// Generated handlers register their descriptors at init, so a
			// miss means the route table itself is wrong.
			panic("v1 route without a registered service descriptor: " + r.path)
		}
		methods := desc.(protoreflect.ServiceDescriptor).Methods()
		for i := range methods.Len() {
			out = append(out, r.path+string(methods.Get(i).Name()))
		}
	}
	return out
}

// agentInfoService implements stackpanel.agent.v1.AgentService.
type agentInfoService struct {
	version    string
	procedures []string
}

func (a *agentInfoService) GetAgentInfo(
	context.Context,
	*connect.Request[agentv1.GetAgentInfoRequest],
) (*connect.Response[agentv1.GetAgentInfoResponse], error) {
	return connect.NewResponse(&agentv1.GetAgentInfoResponse{
		Version:    a.version,
		Procedures: a.procedures,
	}), nil
}

var errUnauthenticated = errors.New("missing or invalid token")

// authInterceptor requires a valid agent token as an Authorization Bearer
// credential on every procedure except GetAgentInfo, which the Studio calls
// before pairing to learn whether this agent build supports it.
type authInterceptor struct {
	valid func(token string) bool
}

func (a authInterceptor) WrapUnary(next connect.UnaryFunc) connect.UnaryFunc {
	return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
		if err := a.check(req.Spec().Procedure, req.Header()); err != nil {
			return nil, err
		}
		return next(ctx, req)
	}
}

func (a authInterceptor) WrapStreamingClient(next connect.StreamingClientFunc) connect.StreamingClientFunc {
	return next
}

func (a authInterceptor) WrapStreamingHandler(next connect.StreamingHandlerFunc) connect.StreamingHandlerFunc {
	return func(ctx context.Context, conn connect.StreamingHandlerConn) error {
		if err := a.check(conn.Spec().Procedure, conn.RequestHeader()); err != nil {
			return err
		}
		return next(ctx, conn)
	}
}

func (a authInterceptor) check(procedure string, header http.Header) error {
	if procedure == agentv1connect.AgentServiceGetAgentInfoProcedure {
		return nil
	}
	const scheme = "bearer "
	auth := strings.TrimSpace(header.Get("Authorization"))
	if len(auth) <= len(scheme) || !strings.EqualFold(auth[:len(scheme)], scheme) {
		return connect.NewError(connect.CodeUnauthenticated, errUnauthenticated)
	}
	if !a.valid(strings.TrimSpace(auth[len(scheme):])) {
		return connect.NewError(connect.CodeUnauthenticated, errUnauthenticated)
	}
	return nil
}

// recoverRPC reports a handler panic to the caller as Internal and logs it
// with the procedure, instead of dropping the connection.
func recoverRPC(_ context.Context, spec connect.Spec, _ http.Header, p any) error {
	log.Error().Str("procedure", spec.Procedure).Interface("panic", p).Msg("v1 handler panicked")
	return connect.NewError(connect.CodeInternal, errors.New("internal error"))
}
