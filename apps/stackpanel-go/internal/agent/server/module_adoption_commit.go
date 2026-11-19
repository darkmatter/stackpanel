package server

import (
	"context"
	"encoding/json"
	"reflect"
	"slices"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	nixser "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// commit runs under the same project lock as resolution of the answers. No
// decision is recorded until all edits (including enable) have evaluated
// successfully in this project's pure flake. Undo in reverse source order: a
// single config.nix can contain several mutations and imports can split them.
func (p *moduleAdoptionPlan) commit(
	ctx context.Context,
	rt *projectRuntime,
	id string,
) (err error) {
	patches := make([]nixdata.ModulePatch, 1, 1+len(p.mutations))
	patches[0] = nixdata.ModulePatch{Path: p.enablePath, Value: true}
	for _, m := range p.mutations {
		path := nixdata.SplitConfigPath(m.Path)
		if slices.Equal(path, p.enablePath) {
			continue
		} // already validated as true
		patches = append(patches, nixdata.ModulePatch{Path: path, Value: m.Value})
	}
	if ctx.Err() != nil {
		return moduleEvalError(ctx, ctx.Err())
	}
	rollback, err := rt.store.ApplyModulePatches(patches)
	if err != nil {
		return invalidModuleState("could not apply the module's declared adoption settings")
	}
	defer func() {
		if err != nil && rollback() != nil {
			err = invalidModuleState(
				"project config changed during adoption rollback; inspect the affected files",
			)
		}
		if rt.flake != nil {
			rt.flake.InvalidateAll()
		}
	}()
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return err
	}
	mod, err := findModule(state, id)
	if err != nil {
		return err
	}
	if mod["enabled"] != true {
		return invalidModuleState("module did not enable in the selected project")
	}
	if err := verifyAdoptedValues(ctx, rt, p.mutations); err != nil {
		return err
	}
	if ctx.Err() != nil {
		return moduleEvalError(ctx, ctx.Err())
	}
	if err := p.ledger.SaveDecisions(rt.root, p.records); err != nil {
		return invalidModuleState("could not record adoption decisions; preview again")
	}
	return nil
}

func verifyAdoptedValues(
	ctx context.Context,
	rt *projectRuntime,
	muts []reconcile.Mutation,
) error {
	if len(muts) == 0 {
		return nil
	}
	paths := make([][]string, len(muts))
	for i, m := range muts {
		paths[i] = nixdata.SplitConfigPath(m.Path)
	}
	selectors, err := json.Marshal(paths)
	if err != nil {
		return err
	}
	// Return only the declared leaves to the agent for verification. Never
	// put expected values in argv or emit either actual or expected in errors.
	data, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
		ProjectRoot: rt.root,
		Expression:  ".#legacyPackages." + nixeval.CurrentSystem() + ".stackpanelRawConfig",
		Apply: `raw: map (builtins.foldl' (v: k: builtins.getAttr k v) raw) (builtins.fromJSON ` + nixser.QuoteString(
			string(selectors),
		) + `)`,
	})
	if err != nil {
		return moduleEvalError(ctx, err)
	}
	var values []any
	if err := json.Unmarshal(data, &values); err != nil || len(values) != len(muts) {
		return invalidModuleState("invalid adoption config readback")
	}
	for i, m := range muts {
		if !reflect.DeepEqual(m.Value, values[i]) {
			return invalidModuleState(
				"project flake did not apply all declared adoption settings",
			)
		}
	}
	return nil
}
