package server

import (
	"context"
	"errors"
	"fmt"

	"connectrpc.com/connect"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/registry"
)

// registryView couples the catalog selected by this project's configuration to
// this project's lock. Neither is derived from the agent's current shell.
type registryView struct {
	client  *registry.Client
	modules []registry.Module
	lock    *registryLock
	state   map[string]any
}

func (s *moduleService) loadRegistry(
	ctx context.Context,
	rt *projectRuntime,
) (*registryView, error) {
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return nil, err
	}
	var projectURLs []string
	if value, ok := state["registries"]; ok {
		urls, ok := value.([]any)
		if !ok {
			return nil, connect.NewError(
				connect.CodeFailedPrecondition,
				errors.New("stackpanel.registries must be a list of URLs"),
			)
		}
		for _, item := range urls {
			u, ok := item.(string)
			if !ok || u == "" {
				return nil, connect.NewError(
					connect.CodeFailedPrecondition,
					errors.New("invalid URL in stackpanel.registries"),
				)
			}
			projectURLs = append(projectURLs, u)
		}
	}
	var machineURLs []string
	var headers map[string]map[string]string
	if s.s != nil && s.s.projectMgr != nil {
		mgr := s.s.projectMgr.UserConfigManager()
		machineURLs, headers = mgr.RegistrySources(), mgr.RegistryHeaders()
	}
	client := registry.NewClient(projectURLs, machineURLs, headers)
	modules, err := client.List(ctx)
	if err != nil {
		return nil, connect.NewError(
			connect.CodeUnavailable,
			fmt.Errorf("read module catalog: %w", err),
		)
	}
	lock, err := readRegistryLock(rt.root)
	if err != nil {
		return nil, connect.NewError(connect.CodeFailedPrecondition, err)
	}
	return &registryView{client: client, modules: modules, lock: lock, state: state}, nil
}

func (v *registryView) lookup(id string) (*registry.Module, error) {
	if id == "" {
		return nil, connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("module_id is required"),
		)
	}
	for i := range v.modules {
		m := &v.modules[i]
		if m.ID == id || m.Slug == id {
			return m, nil
		}
	}
	return nil, connect.NewError(
		connect.CodeNotFound,
		fmt.Errorf("module %q is not in the configured registries", id),
	)
}

// Normally only one catalog release has this pin. Do not invent a version
// when several releases share the same floating source, or a user pinned a
// different branch of the same module.
func registryProjection(
	m *registry.Module,
	lock *registryLock,
) (*agentv1.RegistryModule, error) {
	input, exists, err := lock.input(m.Slug)
	if err != nil {
		return nil, connect.NewError(connect.CodeFailedPrecondition, err)
	}
	out := &agentv1.RegistryModule{
		Id: m.ID, Slug: m.Slug, Name: m.Name, Description: m.Description,
		Category: m.Category, Icon: m.Icon, Author: m.Author, Tier: m.Tier,
		LatestVersion: m.LatestVersion, Features: m.Features, UiSlots: m.UISlots,
		Tags: m.Tags, ReadmeUrl: m.ReadmeURL, Homepage: m.Homepage,
	}
	matches := 0
	for i := range m.Versions {
		v := &m.Versions[i]
		release := &agentv1.RegistryModuleVersion{
			Version: v.Version, FlakeUrl: v.FlakeURL, Ref: v.Ref, Rev: v.Rev,
			FollowsNixpkgs: v.FollowsNixpkgs, FlakePath: v.FlakePath,
		}
		for _, dep := range v.FlakeInputs {
			d := &agentv1.ModuleFlakeInput{
				Name:           dep.Name,
				Url:            dep.URL,
				FollowsNixpkgs: dep.FollowsNixpkgs,
			}
			if dep.Ref != "" {
				d.Ref = &dep.Ref
			}
			release.FlakeInputs = append(release.FlakeInputs, d)
		}
		out.Versions = append(out.Versions, release)
		if exists && input.matchesSource(v.FlakeURL) {
			out.Installed = true
			if input.matchesPin(v.FlakeURL, v.Ref, v.Rev) {
				out.InstalledVersion = &v.Version
				matches++
			}
		}
	}
	if matches != 1 {
		out.InstalledVersion = nil
	}
	return out, nil
}

func (s *moduleService) ListRegistryModules(
	ctx context.Context,
	req *connect.Request[agentv1.ListRegistryModulesRequest],
) (*connect.Response[agentv1.ListRegistryModulesResponse], error) {
	rt := runtimeFor(ctx)
	if rt == nil {
		return nil, invalidModuleState("no project selected")
	}
	rt.moduleMu.Lock()
	defer rt.moduleMu.Unlock()
	view, err := s.loadRegistry(ctx, rt)
	if err != nil {
		return nil, err
	}
	out := &agentv1.ListRegistryModulesResponse{}
	for i := range view.modules {
		m := &view.modules[i]
		if m.Matches(req.Msg.Query, req.Msg.Category, req.Msg.Tag) {
			item, err := registryProjection(m, view.lock)
			if err != nil {
				return nil, err
			}
			out.Modules = append(out.Modules, item)
		}
	}
	return connect.NewResponse(out), nil
}

func (s *moduleService) GetRegistryModule(
	ctx context.Context,
	req *connect.Request[agentv1.GetRegistryModuleRequest],
) (*connect.Response[agentv1.GetRegistryModuleResponse], error) {
	rt := runtimeFor(ctx)
	if rt == nil {
		return nil, invalidModuleState("no project selected")
	}
	rt.moduleMu.Lock()
	defer rt.moduleMu.Unlock()
	view, err := s.loadRegistry(ctx, rt)
	if err != nil {
		return nil, err
	}
	m, err := view.lookup(req.Msg.ModuleId)
	if err != nil {
		return nil, err
	}
	item, err := registryProjection(m, view.lock)
	if err != nil {
		return nil, err
	}
	readme, err := view.client.Readme(ctx, *m)
	if err != nil {
		return nil, connect.NewError(
			connect.CodeUnavailable,
			fmt.Errorf("read README for %s: %w", m.ID, err),
		)
	}
	return connect.NewResponse(
		&agentv1.GetRegistryModuleResponse{Module: item, Readme: readme},
	), nil
}
