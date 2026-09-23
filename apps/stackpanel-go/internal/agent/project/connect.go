package project

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"sort"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

var _ agentv1connect.ProjectServiceHandler = (*ConnectHandler)(nil)

// ConnectHandler serves stackpanel.agent.v1.ProjectService over the
// user-level project registry.
//
// Projects are selected per request (ADR 0005), so this service only
// maintains the registry; it never changes which project other requests
// run against.
type ConnectHandler struct {
	registry *userconfig.Manager

	// checkListed reports whether a listed project is still usable; it runs
	// for every project on every list, so it must stay cheap.
	checkListed func(path string) error

	// checkAdded fully validates a project before it is registered.
	checkAdded func(path string) error
}

// NewConnectHandler returns a ProjectService backed by the manager's registry.
func NewConnectHandler(m *Manager) *ConnectHandler {
	return &ConnectHandler{
		registry:    m.UserConfigManager(),
		checkListed: QuickValidate,
		checkAdded:  ValidateProject,
	}
}

func (h *ConnectHandler) ListProjects(
	_ context.Context,
	_ *connect.Request[agentv1.ListProjectsRequest],
) (*connect.Response[agentv1.ListProjectsResponse], error) {
	projects := h.registry.ListProjects()
	sort.SliceStable(projects, func(i, j int) bool {
		return projects[i].LastOpened.After(projects[j].LastOpened)
	})

	res := &agentv1.ListProjectsResponse{
		Projects: make([]*agentv1.Project, 0, len(projects)),
	}
	for _, p := range projects {
		res.Projects = append(res.Projects, h.toProto(p))
	}
	if def := h.registry.GetDefaultProject(); def != nil {
		res.DefaultProjectId = projectID(*def)
	}
	return connect.NewResponse(res), nil
}

func (h *ConnectHandler) AddProject(
	_ context.Context,
	req *connect.Request[agentv1.AddProjectRequest],
) (*connect.Response[agentv1.AddProjectResponse], error) {
	path := req.Msg.GetPath()
	if !filepath.IsAbs(path) {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("path must be absolute: %q", path))
	}
	path = filepath.Clean(path)
	if err := h.checkAdded(path); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}

	p, err := h.registry.AddProject(path, "")
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	return connect.NewResponse(&agentv1.AddProjectResponse{Project: h.toProto(*p)}), nil
}

func (h *ConnectHandler) RemoveProject(
	_ context.Context,
	req *connect.Request[agentv1.RemoveProjectRequest],
) (*connect.Response[agentv1.RemoveProjectResponse], error) {
	p, err := h.lookup(req.Msg.GetProjectId())
	if err != nil {
		return nil, err
	}
	if err := h.registry.RemoveProject(p.Path); err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	return connect.NewResponse(&agentv1.RemoveProjectResponse{}), nil
}

func (h *ConnectHandler) SetDefaultProject(
	_ context.Context,
	req *connect.Request[agentv1.SetDefaultProjectRequest],
) (*connect.Response[agentv1.SetDefaultProjectResponse], error) {
	if req.Msg.GetProjectId() == "" {
		if err := h.registry.ClearDefaultProject(); err != nil {
			return nil, connect.NewError(connect.CodeInternal, err)
		}
		return connect.NewResponse(&agentv1.SetDefaultProjectResponse{}), nil
	}

	p, err := h.lookup(req.Msg.GetProjectId())
	if err != nil {
		return nil, err
	}
	if err := h.registry.SetDefaultProject(p.Path); err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	return connect.NewResponse(&agentv1.SetDefaultProjectResponse{}), nil
}

func (h *ConnectHandler) lookup(id string) (*userconfig.Project, error) {
	if id == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("project_id is required"))
	}
	p := h.registry.GetProjectByID(id)
	if p == nil {
		return nil, connect.NewError(connect.CodeNotFound, fmt.Errorf("unknown project %q", id))
	}
	return p, nil
}

func (h *ConnectHandler) toProto(p userconfig.Project) *agentv1.Project {
	out := &agentv1.Project{
		Id:    projectID(p),
		Name:  p.Name,
		Path:  p.Path,
		Valid: true,
	}
	if !p.LastOpened.IsZero() {
		out.LastOpenedAt = timestamppb.New(p.LastOpened)
	}
	if err := h.checkListed(p.Path); err != nil {
		out.Valid = false
		out.InvalidReason = err.Error()
	}
	return out
}

// projectID is the identifier clients send in the Stackpanel-Project header.
// Older registry entries have no stored ID, so it falls back to the one
// derived from the path, matching userconfig.Manager.GetProjectByID.
func projectID(p userconfig.Project) string {
	if p.ID != "" {
		return p.ID
	}
	return userconfig.GenerateProjectID(p.Path)
}
