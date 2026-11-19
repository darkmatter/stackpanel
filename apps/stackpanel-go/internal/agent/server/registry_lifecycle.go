package server

import (
	"context"
	"errors"
	"fmt"
	"slices"

	"connectrpc.com/connect"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/registry"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

func registrySelection(
	m *registry.Module,
	version, ref string,
) (*registry.Version, flakeedit.FlakeInput, []flakeedit.FlakeInput, error) {
	if version == "" {
		version = m.LatestVersion
	}
	for i := range m.Versions {
		v := &m.Versions[i]
		if v.Version != version {
			continue
		}
		input := flakeedit.FlakeInput{
			Name:           m.Slug,
			URL:            v.FlakeURL,
			Ref:            v.Ref,
			Rev:            v.Rev,
			FollowsNixpkgs: v.FollowsNixpkgs,
		}
		if ref != "" && ref != v.Ref {
			// An explicit ref intentionally selects a different commit of
			// the same source, not another release's dependencies/import.
			input.Ref, input.Rev = ref, ""
		}
		if _, err := input.PinnedURL(); err != nil {
			return nil, input, nil, connect.NewError(connect.CodeInvalidArgument, err)
		}
		deps := make([]flakeedit.FlakeInput, 0, len(v.FlakeInputs))
		for _, dep := range v.FlakeInputs {
			deps = append(
				deps,
				flakeedit.FlakeInput{
					Name:           dep.Name,
					URL:            dep.URL,
					Ref:            dep.Ref,
					FollowsNixpkgs: dep.FollowsNixpkgs,
				},
			)
		}
		return v, input, deps, nil
	}
	return nil, flakeedit.FlakeInput{}, nil, connect.NewError(
		connect.CodeInvalidArgument,
		fmt.Errorf("unknown version %q of %s", version, m.ID),
	)
}

// Use exact releases when possible. For a user-selected ref, the source is
// still known but only operations safe for every matching release are allowed.
func installedCandidates(
	node registryLockedInput,
	m *registry.Module,
) []*registry.Version {
	var source, exact []*registry.Version
	for i := range m.Versions {
		v := &m.Versions[i]
		if node.matchesSource(v.FlakeURL) {
			source = append(source, v)
			if node.matchesPin(v.FlakeURL, v.Ref, v.Rev) {
				exact = append(exact, v)
			}
		}
	}
	if len(exact) != 0 {
		return exact
	}
	return source
}

// Match the *previous* source and explicit import to a catalog release. In a
// custom-ref checkout there may be no exact pin. Such an input is editable
// only if all matching catalog entries agree which import would be removed.
func installedRelease(
	lock *registryLock,
	m *registry.Module,
) (*registry.Version, error) {
	node, exists, err := lock.input(m.Slug)
	if err != nil {
		return nil, connect.NewError(connect.CodeFailedPrecondition, err)
	}
	if !exists {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			fmt.Errorf("no locked root input %q", m.Slug),
		)
	}
	candidates := installedCandidates(node, m)
	if len(candidates) == 0 {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			fmt.Errorf("root input %q is not owned by catalog module %q", m.Slug, m.ID),
		)
	}
	for _, other := range candidates[1:] {
		if other.FlakePath != candidates[0].FlakePath {
			return nil, connect.NewError(
				connect.CodeFailedPrecondition,
				fmt.Errorf(
					"cannot identify installed import for %q; check the pin in flake.nix",
					m.Slug,
				),
			)
		}
	}
	return candidates[0], nil
}

// Another installed catalog entry may use this root input even if its module
// is disabled and doesn't force it during evaluation. Never break a satisfied
// dependency when updating/uninstalling its provider.
func (op registryOperation) checkDependents(after *registryLock) error {
	name := op.module.Slug
	before, occupied, err := op.view.lock.input(name)
	if err != nil || !occupied {
		return err
	}
	now, exists, err := after.input(name)
	if err != nil {
		return err
	}
	for i := range op.view.modules {
		m := &op.view.modules[i]
		if m.Slug == name {
			continue
		}
		node, occupied, err := op.view.lock.input(m.Slug)
		if err != nil {
			return err
		}
		if !occupied {
			continue
		}
		for _, v := range installedCandidates(node, m) {
			for _, dep := range v.FlakeInputs {
				if dep.Name == name && before.matchesPin(dep.URL, dep.Ref, "") &&
					(!exists || !now.matchesPin(dep.URL, dep.Ref, "")) {
					return fmt.Errorf(
						"installed module %q requires the existing pin of input %q",
						m.ID,
						name,
					)
				}
			}
		}
	}
	return nil
}

// A linked local module is useful for preview, but cannot prove that the
// installed catalog release itself exports a valid module.
func lockedModuleState(ctx context.Context, root string) (map[string]any, error) {
	return loadModuleState(
		ctx,
		&projectRuntime{root: root, evalModuleState: nixeval.EvalLockedModuleState},
	)
}

// Verify Nix locked the requested direct inputs, *and* that the expected
// module can actually be discovered. A valid flake isn't necessarily a
// module. Validation runs inside flakeedit's rollback boundary.
func (op registryOperation) validateInstall(
	ctx context.Context,
	input flakeedit.FlakeInput,
	deps []flakeedit.FlakeInput,
) (map[string]any, error) {
	rt := op.rt
	lock, err := readRegistryLock(rt.root)
	if err != nil {
		return nil, err
	}
	if err := op.checkDependents(lock); err != nil {
		return nil, err
	}
	check := func(dep flakeedit.FlakeInput) error {
		node, exists, err := lock.input(dep.Name)
		if err != nil {
			return err
		}
		if !exists || !node.matchesPin(dep.URL, dep.Ref, dep.Rev) {
			return fmt.Errorf(
				"flake.lock does not contain the requested pin for %q",
				dep.Name,
			)
		}
		return nil
	}
	if err := check(input); err != nil {
		return nil, err
	}
	for _, dep := range deps {
		if err := check(dep); err != nil {
			return nil, err
		}
	}
	return lockedRegistration(ctx, rt.root, input.Name)
}

func lockedRegistration(ctx context.Context, root, id string) (map[string]any, error) {
	state, err := lockedModuleState(ctx, root)
	if err != nil {
		return nil, err
	}
	module, err := findModule(state, id)
	if err != nil {
		if connect.CodeOf(err) == connect.CodeNotFound {
			return nil, fmt.Errorf("locked input %q does not register the catalog module", id)
		}
		return nil, err
	}
	// The catalog is the list of inputs the consumer agreed to add. A stale
	// listing must not silently install a module whose requirements are unmet.
	if missing := module["missingFlakeInputs"]; missing != nil {
		inputs, ok := missing.([]any)
		if !ok || len(inputs) != 0 {
			return nil, fmt.Errorf(
				"locked module %q still requires flake inputs; check its registry version's flakeInputs",
				id,
			)
		}
	}
	return module, nil
}

type registryOperation struct {
	rt     *projectRuntime
	view   *registryView
	module *registry.Module
}

func (s *moduleService) mutateRegistry(
	ctx context.Context,
	id string,
	lockedView bool,
	apply func(context.Context, registryOperation) error,
) (string, error) {
	rt := runtimeFor(ctx)
	if rt == nil || rt.store == nil {
		return "", invalidModuleState("no project config store")
	}
	rt.moduleMu.Lock()
	defer rt.moduleMu.Unlock()
	var slug string
	err := flakeedit.WithModuleProject(ctx, rt.root, func(ctx context.Context) error {
		project := rt
		if lockedView {
			// Resolve removal against installed sources, not an authoring
			// override (which itself might no longer evaluate).
			project = &projectRuntime{
				root:            rt.root,
				evalModuleState: nixeval.EvalLockedModuleState,
			}
		}
		view, err := s.loadRegistry(ctx, project)
		if err != nil {
			return err
		}
		m, err := view.lookup(id)
		if err != nil {
			return err
		}
		slug = m.Slug
		return apply(ctx, registryOperation{rt: rt, view: view, module: m})
	})
	if err != nil {
		if ctx.Err() != nil {
			return "", moduleEvalError(ctx, err)
		}
		var rpcError *connect.Error
		if errors.As(err, &rpcError) {
			return "", err
		}
		return "", connect.NewError(connect.CodeFailedPrecondition, err)
	}
	if rt.flake != nil {
		rt.flake.InvalidateAll()
	}
	return slug, nil
}

func (s *moduleService) InstallModule(
	ctx context.Context,
	req *connect.Request[agentv1.InstallModuleRequest],
) (*connect.Response[agentv1.InstallModuleResponse], error) {
	slug, err := s.mutateRegistry(
		ctx,
		req.Msg.ModuleId,
		false,
		func(ctx context.Context, op registryOperation) error {
			return op.applyVersion(ctx, req.Msg.Version, req.Msg.Ref, false)
		},
	)
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(
		&agentv1.InstallModuleResponse{
			ModuleId: slug,
			Message:  "Installed " + slug + "; preview before enabling it",
		},
	), nil
}

func (s *moduleService) UpdateModule(
	ctx context.Context,
	req *connect.Request[agentv1.UpdateModuleRequest],
) (*connect.Response[agentv1.UpdateModuleResponse], error) {
	slug, err := s.mutateRegistry(
		ctx,
		req.Msg.ModuleId,
		false,
		func(ctx context.Context, op registryOperation) error {
			return op.applyVersion(ctx, req.Msg.Version, req.Msg.Ref, true)
		},
	)
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(
		&agentv1.UpdateModuleResponse{Message: "Updated " + slug},
	), nil
}

func (op registryOperation) applyVersion(
	ctx context.Context,
	version, ref string,
	update bool,
) error {
	m, rt, view := op.module, op.rt, op.view
	v, input, deps, err := registrySelection(m, version, ref)
	if err != nil {
		return err
	}
	if auto, ok := view.state["autoImportInputs"].(bool); ok {
		input.ExplicitImport = !auto
	}
	if update {
		previous, err := installedRelease(view.lock, m)
		if err != nil {
			return err
		}
		input.PreviousURL = previous.FlakeURL
		if err := op.authorizeDependencyUpdates(previous, deps); err != nil {
			return err
		}
		validate := func() error {
			_, err := op.validateInstall(ctx, input, deps)
			return err
		}
		return flakeedit.UpdateModuleWithImports(
			ctx,
			rt.root,
			input,
			previous.FlakePath,
			v.FlakePath,
			deps,
			validate,
		)
	}
	if _, exists, err := view.lock.input(m.Slug); err != nil {
		return err
	} else if exists {
		return connect.NewError(
			connect.CodeAlreadyExists,
			fmt.Errorf("project already has a locked input %q", m.Slug),
		)
	}
	if _, err := findModule(view.state, m.Slug); err == nil {
		return connect.NewError(
			connect.CodeAlreadyExists,
			fmt.Errorf("project already defines module %q", m.Slug),
		)
	} else if connect.CodeOf(err) != connect.CodeNotFound {
		return err
	}
	// Discovered modules can default to enabled. Defer adoption even for
	// these modules, without changing defaults for manual flake consumers.
	var undo func() error
	err = flakeedit.InstallModule(ctx, rt.root, input, v.FlakePath, deps, func() error {
		module, err := op.validateInstall(ctx, input, deps)
		if err != nil {
			return err
		}
		enabled, ok := module["enabled"].(bool)
		if !ok {
			return fmt.Errorf("module %q does not declare its enabled state", m.Slug)
		}
		if !enabled {
			return nil
		}
		path, err := moduleOptionPath(module, "enablePath")
		if err != nil {
			return err
		}
		undo, err = rt.store.PatchModuleDataReversible(path, false)
		if err != nil {
			return err
		}
		module, err = lockedRegistration(ctx, rt.root, m.Slug)
		if err != nil {
			return err
		}
		if module["enabled"] != false {
			return fmt.Errorf(
				"could not install %q in a disabled state; check its declared enablePath",
				m.Slug,
			)
		}
		return nil
	})
	if err != nil && undo != nil {
		return errors.Join(err, undo())
	}
	return err
}

func (s *moduleService) UninstallModule(
	ctx context.Context,
	req *connect.Request[agentv1.UninstallModuleRequest],
) (*connect.Response[agentv1.UninstallModuleResponse], error) {
	slug, err := s.mutateRegistry(
		ctx,
		req.Msg.ModuleId,
		true,
		func(ctx context.Context, op registryOperation) error { return op.uninstall(ctx) },
	)
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(
		&agentv1.UninstallModuleResponse{Message: "Uninstalled " + slug},
	), nil
}

func (op registryOperation) uninstall(ctx context.Context) error {
	m, rt, view := op.module, op.rt, op.view
	links, err := userconfig.LoadLinkedModules(rt.root)
	if err != nil {
		return err
	}
	if _, linked := links[m.Slug]; linked {
		return fmt.Errorf(
			"module %q is linked in this project; run `stack module unlink %s` before uninstalling",
			m.Slug,
			m.Slug,
		)
	}
	previous, err := installedRelease(view.lock, m)
	if err != nil {
		return err
	}
	module, err := findModule(view.state, m.Slug)
	if err != nil {
		return err
	}
	// Setting enable=false alone would leave an unknown option behind once
	// the declaring module disappears. Remove both persisted option roots.
	paths := [][]string{{"modules", m.Slug}}
	for _, field := range []string{"enablePath", "configPath"} {
		path, err := moduleOptionPath(module, field)
		if err != nil {
			return err
		}
		if path[0] == "modules" {
			continue // own namespace is already removed as a unit
		}
		if field == "enablePath" || slices.Contains(path, m.Slug) {
			paths = append(paths, path)
			continue
		}
		// A module's configPath can be a shared namespace. Remove only the
		// settings declared by the module, not adjacent user data.
		settings, _ := module["settings"].(map[string]any)
		for key := range settings {
			paths = append(paths, append(slices.Clip(path), key))
		}
	}
	rollback, err := rt.store.RemoveModuleData(paths)
	if err != nil {
		return err
	}
	input := flakeedit.FlakeInput{Name: m.Slug, URL: previous.FlakeURL}
	err = flakeedit.UninstallRegistryModule(
		ctx,
		rt.root,
		input,
		previous.FlakePath,
		func() error {
			lock, err := readRegistryLock(rt.root)
			if err != nil {
				return err
			}
			if err := op.checkDependents(lock); err != nil {
				return err
			}
			if _, exists, err := lock.input(m.Slug); err != nil {
				return err
			} else if exists {
				return fmt.Errorf("removed input %q is still in flake.lock", m.Slug)
			}
			// User-written .nix files can still refer to this module, including
			// app-specific options. Refuse removal rather than editing arbitrary
			// files or leaving the project in a state it cannot evaluate.
			state, err := lockedModuleState(ctx, rt.root)
			if err != nil {
				return err
			}
			_, err = findModule(state, m.Slug)
			if connect.CodeOf(err) == connect.CodeNotFound {
				return nil
			}
			if err == nil {
				return fmt.Errorf(
					"project still defines module %q after removing its input",
					m.Slug,
				)
			}
			return err
		},
	)
	if err != nil {
		return errors.Join(err, rollback())
	}
	return nil
}
