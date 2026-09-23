package server

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"connectrpc.com/connect"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
)

// projectHeader names the project a request runs against (ADR 0005). It is
// the header the Studio already sends and the CORS policy already allows.
const projectHeader = "X-Stackpanel-Project"

type runtimeKey struct{}

// runtimeFor returns the project runtime attached by projectInterceptor.
// Only project-scoped services are mounted behind that interceptor.
func runtimeFor(ctx context.Context) *projectRuntime {
	rt, _ := ctx.Value(runtimeKey{}).(*projectRuntime)
	return rt
}

// projectInterceptor resolves the project for project-scoped v1 services and
// attaches its runtime to the request context. Runtimes come from the same
// registry the legacy handlers use, so both act on shared instances.
type projectInterceptor struct {
	// resolve maps the request's project header (possibly empty) to a
	// project root, returning a Connect error when it cannot.
	resolve  func(projectID string) (string, error)
	runtimes *runtimeRegistry
}

func (p projectInterceptor) WrapUnary(next connect.UnaryFunc) connect.UnaryFunc {
	return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
		ctx, err := p.attach(ctx, req.Header())
		if err != nil {
			return nil, err
		}
		return next(ctx, req)
	}
}

func (p projectInterceptor) WrapStreamingClient(next connect.StreamingClientFunc) connect.StreamingClientFunc {
	return next
}

func (p projectInterceptor) WrapStreamingHandler(next connect.StreamingHandlerFunc) connect.StreamingHandlerFunc {
	return func(ctx context.Context, conn connect.StreamingHandlerConn) error {
		ctx, err := p.attach(ctx, conn.RequestHeader())
		if err != nil {
			return err
		}
		return next(ctx, conn)
	}
}

func (p projectInterceptor) attach(ctx context.Context, header http.Header) (context.Context, error) {
	root, err := p.resolve(strings.TrimSpace(header.Get(projectHeader)))
	if err != nil {
		return nil, err
	}
	rt, err := p.runtimes.get(root)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("start project runtime: %w", err))
	}
	return context.WithValue(ctx, runtimeKey{}, rt), nil
}

// resolveProjectRoot maps a request's project ID to a project root. Without
// an ID it uses the agent's current project, then the registry's default:
// current comes first so header-less v1 calls act on the same project as the
// legacy REST routes during the migration (ADR 0005).
func (s *Server) resolveProjectRoot(projectID string) (string, error) {
	registry := s.projectMgr.UserConfigManager()

	if projectID != "" {
		p := registry.GetProjectByID(projectID)
		if p == nil {
			return "", connect.NewError(connect.CodeNotFound, fmt.Errorf("unknown project %q", projectID))
		}
		if err := project.QuickValidate(p.Path); err != nil {
			return "", connect.NewError(connect.CodeFailedPrecondition,
				fmt.Errorf("project %q is not usable: %w", projectID, err))
		}
		return p.Path, nil
	}

	if root := s.config.ProjectRoot; root != "" {
		return root, nil
	}
	if def := registry.GetDefaultProject(); def != nil {
		return def.Path, nil
	}
	return "", connect.NewError(connect.CodeFailedPrecondition,
		errors.New("no project selected: send "+projectHeader+" or open a project"))
}
