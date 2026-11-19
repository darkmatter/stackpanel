package server

import (
	"context"
	"errors"
	"net/http"
	"reflect"
	"slices"

	"connectrpc.com/connect"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

type moduleService struct{ s *Server }

func moduleInfo(
	data map[string]any,
	links map[string]userconfig.LinkedModule,
) (*agentv1.Module, error) {
	var mod agentv1.Module
	if err := decodeModuleProjection(data, &mod); err != nil {
		return nil, err
	}
	if mod.Id == "" {
		return nil, invalidModuleState("module metadata missing id")
	}
	if readme, ok := data["readme"].(string); ok {
		mod.ReadmeContent = &readme
	}
	// Linking and dev origins are machine-local authority; never honor these
	// claims from Nix (including protobuf's alternate snake_case spelling).
	link, linked := links[mod.Id]
	mod.Linked, mod.UiDevUrl = linked, nil
	if linked && link.UIDevURL != "" {
		mod.UiDevUrl = &link.UIDevURL
	}
	return &mod, nil
}

func (s *moduleService) ListModules(
	ctx context.Context,
	_ *connect.Request[agentv1.ListModulesRequest],
) (*connect.Response[agentv1.ListModulesResponse], error) {
	rt := runtimeFor(ctx)
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return nil, err
	}
	list, err := evaluatedModules(state)
	if err != nil {
		return nil, err
	}
	links := userconfig.LinkedModules(rt.root)
	resp := &agentv1.ListModulesResponse{Modules: make([]*agentv1.Module, 0, len(list))}
	for _, item := range list {
		data, _ := item.(map[string]any)
		mod, err := moduleInfo(data, links)
		if err != nil {
			return nil, err
		}
		resp.Modules = append(resp.Modules, mod)
	}
	return connect.NewResponse(resp), nil
}

func (s *moduleService) GetModule(
	ctx context.Context,
	req *connect.Request[agentv1.GetModuleRequest],
) (*connect.Response[agentv1.GetModuleResponse], error) {
	rt := runtimeFor(ctx)
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return nil, err
	}
	data, err := findModule(state, req.Msg.GetModuleId())
	if err != nil {
		return nil, err
	}
	mod, err := moduleInfo(data, userconfig.LinkedModules(rt.root))
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(&agentv1.GetModuleResponse{Module: mod}), nil
}

func (s *moduleService) GetModuleOutputs(
	ctx context.Context,
	req *connect.Request[agentv1.GetModuleOutputsRequest],
) (*connect.Response[agentv1.GetModuleOutputsResponse], error) {
	out, err := moduleOutputData(ctx, runtimeFor(ctx), req.Msg.GetModuleId())
	if err != nil {
		return nil, err
	}
	var result agentv1.ModuleOutputs
	if err := decodeModuleProjection(out, &result); err != nil {
		return nil, err
	}
	return connect.NewResponse(&agentv1.GetModuleOutputsResponse{Outputs: &result}), nil
}

func (s *moduleService) EnableModule(
	ctx context.Context,
	req *connect.Request[agentv1.EnableModuleRequest],
) (*connect.Response[agentv1.EnableModuleResponse], error) {
	var err error
	if answers := req.Msg.GetAnswers(); len(answers) != 0 {
		rt := runtimeFor(ctx)
		err = withModuleConfigLock(ctx, rt, func(ctx context.Context) error {
			plan, err := prepareModuleAdoption(ctx, rt, req.Msg.GetModuleId(), answers)
			if err != nil {
				return err
			}
			return plan.commit(ctx, rt, req.Msg.GetModuleId())
		})
	} else {
		err = s.patchModuleOption(
			ctx,
			req.Header(),
			req.Msg.GetModuleId(),
			"enablePath",
			true,
		)
	}
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(
		&agentv1.EnableModuleResponse{Message: "Module enabled in project config."},
	), nil
}

func (s *moduleService) DisableModule(
	ctx context.Context,
	req *connect.Request[agentv1.DisableModuleRequest],
) (*connect.Response[agentv1.DisableModuleResponse], error) {
	if err := s.patchModuleOption(
		ctx,
		req.Header(),
		req.Msg.GetModuleId(),
		"enablePath",
		false,
	); err != nil {
		return nil, err
	}
	return connect.NewResponse(
		&agentv1.DisableModuleResponse{Message: "Module disabled in project config."},
	), nil
}

func (s *moduleService) UpdateModuleConfig(
	ctx context.Context,
	req *connect.Request[agentv1.UpdateModuleConfigRequest],
) (*connect.Response[agentv1.UpdateModuleConfigResponse], error) {
	if req.Msg.Settings == nil {
		return nil, connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("settings must be an object"),
		)
	}
	if err := s.patchModuleOption(
		ctx,
		req.Header(),
		req.Msg.GetModuleId(),
		"configPath",
		req.Msg.Settings.AsMap(),
	); err != nil {
		return nil, err
	}
	return connect.NewResponse(
		&agentv1.UpdateModuleConfigResponse{
			Message: "Module settings saved in project config.",
		},
	), nil
}

func (s *moduleService) patchModuleOption(
	ctx context.Context,
	header http.Header,
	id, field string,
	value any,
) error {
	rt := runtimeFor(ctx)
	return withModuleConfigLock(ctx, rt, func(ctx context.Context) error {
		return s.applyModuleOption(ctx, rt, header, id, field, value)
	})
}

func withModuleConfigLock(
	ctx context.Context,
	rt *projectRuntime,
	fn func(context.Context) error,
) error {
	if rt == nil || rt.store == nil {
		return invalidModuleState("no project config store")
	}
	rt.moduleMu.Lock()
	defer rt.moduleMu.Unlock()
	err := flakeedit.WithModuleProject(ctx, rt.root, fn)
	if err != nil && connect.CodeOf(err) == connect.CodeUnknown {
		if ctx.Err() != nil {
			return moduleEvalError(ctx, ctx.Err())
		}
		return invalidModuleState("could not lock project config for module edit")
	}
	return err
}

func (s *moduleService) applyModuleOption(
	ctx context.Context,
	rt *projectRuntime,
	header http.Header,
	id, field string,
	value any,
) error {
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return err
	}
	var appPath []string
	if field == "configPath" {
		var public map[string]any
		appPath, public, err = s.s.moduleUIConfigPatchScope(header, rt, state, id)
		if err != nil {
			return err
		}
		if appPath != nil && !appPatchIsProjected(public, value) {
			return uiGrantDenied()
		}
	}
	module, err := findModule(state, id)
	if err != nil {
		return err
	}
	path := appPath
	if path == nil {
		path, err = moduleOptionPath(module, field)
		if err != nil {
			return err
		}
	}
	if err := ctx.Err(); err != nil {
		return moduleEvalError(ctx, err)
	}
	check := func() error {
		state, err := loadModuleState(ctx, rt)
		if err != nil {
			return err
		}
		if ctx.Err() != nil {
			return moduleEvalError(ctx, ctx.Err())
		}
		if appPath != nil {
			// Revalidate the original panel's authority, not just the write
			// location. A patch can disable an app or revoke its own grant.
			verified, public, err := s.s.moduleUIConfigPatchScope(header, rt, state, id)
			if err != nil {
				return err
			}
			if !slices.Equal(verified, appPath) {
				return uiGrantDenied()
			}
			if !moduleSettingsMatch(public, value) {
				return invalidModuleState("app settings did not apply to the selected panel")
			}
			if ctx.Err() != nil {
				return moduleEvalError(ctx, ctx.Err())
			}
			return nil
		}
		updated, err := findModule(state, id)
		if err != nil {
			return err
		}
		if field == "enablePath" && updated["enabled"] == value {
			return nil
		}
		if field == "configPath" && moduleSettingsMatch(updated["settings"], value) {
			return nil
		}
		return invalidModuleState(
			"project flake did not apply the module option; verify the option is declared and the config file is tracked",
		)
	}
	if err := rt.store.PatchModuleDataChecked(path, value, check); err != nil {
		var rpcErr *connect.Error
		if errors.As(err, &rpcErr) {
			return rpcErr
		}
		if errors.Is(err, nixdata.ErrInvalidModuleData) {
			return connect.NewError(connect.CodeInvalidArgument, nixdata.ErrInvalidModuleData)
		}
		return invalidModuleState("could not patch the declared option in project config")
	}
	if rt.flake != nil {
		rt.flake.InvalidateAll()
	}
	return nil
}

// Object patches merge literal keys. An object projection may omit private
// siblings: never allow their replacement through a scalar or an ancestor.
func appPatchIsProjected(public any, patch any) bool {
	fields, object := public.(map[string]any)
	updates, merge := patch.(map[string]any)
	if object != merge {
		return false
	}
	for key, value := range updates {
		v, ok := fields[key]
		if !ok || !appPatchIsProjected(v, value) {
			return false
		}
	}
	return true
}

// A patch only constrains the leaves supplied by the caller. Defaults and
// unrelated evaluated settings need not be written back to disk.
func moduleSettingsMatch(actual, patch any) bool {
	if fields, ok := patch.(map[string]any); ok {
		data, _ := actual.(map[string]any)
		for key, value := range fields {
			v, present := data[key]
			if !present || !moduleSettingsMatch(v, value) {
				return false
			}
		}
		return true
	}
	return reflect.DeepEqual(actual, patch)
}
