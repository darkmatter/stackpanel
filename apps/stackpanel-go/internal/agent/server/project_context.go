// project_context.go implements per-request project resolution for multi-project support.
// The web UI sends an X-Stackpanel-Project header to select which project each
// request operates on. This allows a single agent to manage multiple projects
// without requiring separate agent instances.
//
// Resolution priority: header > query param > default project > current project > none.

package server

import (
	"context"
	"net/http"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/rs/zerolog/log"
)

// contextKey is an unexported type to prevent collisions with context keys
// from other packages.
type contextKey string

const (
	// ProjectContextKey is the context key for the resolved project
	ProjectContextKey contextKey = "project"

	// ProjectPathContextKey is the context key for the project path
	ProjectPathContextKey contextKey = "project_path"

	// ProjectIDContextKey is the context key for the project ID
	ProjectIDContextKey contextKey = "project_id"
)

const (
	// ProjectHeader is the HTTP header used to specify a project
	ProjectHeader = "X-Stackpanel-Project"

	// ProjectQueryParam is the query parameter used to specify a project
	ProjectQueryParam = "project"
)

// ProjectContext holds the resolved project information for a request.
type ProjectContext struct {
	// Project is the resolved project (may be nil if no project)
	Project *userconfig.Project

	// Path is the absolute path to the project root
	Path string

	// ID is the project's unique identifier
	ID string

	// Source indicates how the project was determined
	// "header", "query", "default", "current", or "none"
	Source string
}

// withProjectContext is middleware that resolves the project for each request.
// It checks (in order):
// 1. X-Stackpanel-Project header
// 2. "project" query parameter
// 3. Default project from user config
// 4. Current project from user config
//
// The resolved project is stored in the request context.
func (s *Server) withProjectContext(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		projectCtx := s.resolveProjectForRequest(r)

		// Store in context
		ctx = context.WithValue(ctx, ProjectContextKey, projectCtx)
		if projectCtx.Project != nil {
			ctx = context.WithValue(ctx, ProjectPathContextKey, projectCtx.Path)
			ctx = context.WithValue(ctx, ProjectIDContextKey, projectCtx.ID)
		}

		next(w, r.WithContext(ctx))
	}
}

// resolveProjectForRequest determines which project to use for a request.
func (s *Server) resolveProjectForRequest(r *http.Request) *ProjectContext {
	ucm := s.projectMgr.UserConfigManager()
	if ucm == nil {
		return &ProjectContext{Source: "none"}
	}

	// Check header first
	if projectID := r.Header.Get(ProjectHeader); projectID != "" {
		projectID = strings.TrimSpace(projectID)
		if proj := ucm.ResolveProject(projectID); proj != nil {
			id := proj.ID
			if id == "" {
				id = userconfig.GenerateProjectID(proj.Path)
			}
			return &ProjectContext{
				Project: proj,
				Path:    proj.Path,
				ID:      id,
				Source:  "header",
			}
		}
		log.Debug().
			Str("project_id", projectID).
			Msg("Project from header not found, falling back")
	}

	// Check query parameter
	if projectID := r.URL.Query().Get(ProjectQueryParam); projectID != "" {
		projectID = strings.TrimSpace(projectID)
		if proj := ucm.ResolveProject(projectID); proj != nil {
			id := proj.ID
			if id == "" {
				id = userconfig.GenerateProjectID(proj.Path)
			}
			return &ProjectContext{
				Project: proj,
				Path:    proj.Path,
				ID:      id,
				Source:  "query",
			}
		}
		log.Debug().
			Str("project_id", projectID).
			Msg("Project from query not found, falling back")
	}

	// Try default project
	if proj := ucm.GetDefaultProject(); proj != nil {
		id := proj.ID
		if id == "" {
			id = userconfig.GenerateProjectID(proj.Path)
		}
		return &ProjectContext{
			Project: proj,
			Path:    proj.Path,
			ID:      id,
			Source:  "default",
		}
	}

	// Fall back to current project
	if proj := ucm.CurrentProject(); proj != nil {
		id := proj.ID
		if id == "" {
			id = userconfig.GenerateProjectID(proj.Path)
		}
		return &ProjectContext{
			Project: proj,
			Path:    proj.Path,
			ID:      id,
			Source:  "current",
		}
	}

	// No project available
	return &ProjectContext{
		Source: "none",
	}
}

// GetProjectContext retrieves the project context from a request context.
func GetProjectContext(ctx context.Context) *ProjectContext {
	if pc, ok := ctx.Value(ProjectContextKey).(*ProjectContext); ok {
		return pc
	}
	return &ProjectContext{Source: "none"}
}

// GetProjectPath retrieves the project path from a request context.
func GetProjectPath(ctx context.Context) string {
	if path, ok := ctx.Value(ProjectPathContextKey).(string); ok {
		return path
	}
	return ""
}

// GetProjectID retrieves the project ID from a request context.
func GetProjectID(ctx context.Context) string {
	if id, ok := ctx.Value(ProjectIDContextKey).(string); ok {
		return id
	}
	return ""
}

// requireProjectContext is middleware that requires a valid project in the request context.
// This should be used after withProjectContext.
func (s *Server) requireProjectContext(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		pc := GetProjectContext(r.Context())
		if pc.Project == nil {
			s.writeAPI(w, http.StatusPreconditionRequired, map[string]any{
				"error":   "no_project",
				"message": "No project specified. Use X-Stackpanel-Project header, 'project' query parameter, or set a default project.",
				"hint":    "GET /api/project/list to see available projects",
			})
			return
		}

		// Validate the project still exists on disk
		if err := project.QuickValidate(pc.Path); err != nil {
			s.writeAPI(w, http.StatusPreconditionFailed, map[string]any{
				"error":   "project_invalid",
				"message": "The specified project is no longer valid",
				"path":    pc.Path,
				"details": err.Error(),
			})
			return
		}

		next(w, r)
	}
}

// getProjectForRequest returns the project path for the current request.
// Falls back to config.ProjectRoot for backwards compatibility with clients
// that don't send X-Stackpanel-Project (e.g., the CLI or older UI versions).
func (s *Server) getProjectForRequest(r *http.Request) string {
	// Try context first (new per-request project support)
	if path := GetProjectPath(r.Context()); path != "" {
		return path
	}

	// Fall back to server's current project (backwards compatibility)
	return s.config.ProjectRoot
}
