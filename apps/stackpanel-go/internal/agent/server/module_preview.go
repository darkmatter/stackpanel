package server

import (
	"context"
	"encoding/json"
	"errors"
	"maps"
	"slices"

	"connectrpc.com/connect"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	nixser "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// Never transfer generated file contents to the UI. Compare file plans and
// service/package identities, not naming conventions or the current devshell.
const modulePlanProjection = `project = result: {
  services = result.serviceFingerprints;
  packages = result.packageFingerprints;
  files = map (file: { inherit (file) path; hash = builtins.hashString "sha256" (builtins.toJSON file); }) result.files;
};`

type modulePreviewPlan struct {
	Files    []struct{ Path, Hash string } `json:"files"`
	Services map[string]string             `json:"services"`
	Packages map[string]string             `json:"packages"`
}

func (p modulePreviewPlan) fileHashes() (map[string]string, error) {
	if p.Files == nil || p.Packages == nil || p.Services == nil {
		return nil, invalidModuleState("incomplete speculative plan")
	}
	files := make(map[string]string, len(p.Files))
	for _, f := range p.Files {
		if f.Path == "" || f.Hash == "" {
			return nil, invalidModuleState("invalid speculative file entry")
		}
		if _, ok := files[f.Path]; ok {
			return nil, invalidModuleState("duplicate speculative file path")
		}
		files[f.Path] = f.Hash
	}
	return files, nil
}

func modulePreviewDiff(before, after map[string]string) *agentv1.ModulePreviewDiff {
	diff := &agentv1.ModulePreviewDiff{
		Before: slices.Sorted(maps.Keys(before)),
		After:  slices.Sorted(maps.Keys(after)),
	}
	for _, key := range diff.Before {
		if value, ok := after[key]; !ok {
			diff.Removed = append(diff.Removed, key)
		} else if before[key] != value {
			diff.Changed = append(diff.Changed, key)
		}
	}
	for _, key := range diff.After {
		if _, ok := before[key]; !ok {
			diff.Added = append(diff.Added, key)
		}
	}
	return diff
}

func evalModulePlan(
	ctx context.Context,
	rt *projectRuntime,
	apply string,
	dst any,
) error {
	data, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
		Expression:  ".#legacyPackages." + nixeval.CurrentSystem() + ".stackpanelSpeculate",
		ProjectRoot: rt.root, Apply: apply,
	})
	if err != nil {
		return moduleEvalError(ctx, err)
	}
	if err := json.Unmarshal(data, dst); err != nil {
		return invalidModuleState("invalid speculative module plan")
	}
	return nil
}

type moduleAdoptionPlan struct {
	preview    *agentv1.ModulePreview
	enablePath []string
	mutations  []reconcile.Mutation
	ledger     *reconcile.Ledger
	records    map[string]reconcile.LedgerEntry
}

// Inspect the enable-only result first: this is the authority for question
// revisions, possible answers and config mutations, including for a re-preview.
func prepareModuleAdoption(
	ctx context.Context,
	rt *projectRuntime,
	id string,
	answers []*agentv1.ModuleAdoptionAnswer,
) (*moduleAdoptionPlan, error) {
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return nil, err
	}
	mod, err := findModule(state, id)
	if err != nil {
		return nil, err
	}
	path, err := moduleOptionPath(mod, "enablePath")
	if err != nil {
		return nil, err
	}
	literal, err := nixser.Serialize(path)
	if err != nil {
		return nil, err
	}
	prefix := `f: let ` + modulePlanProjection + ` path = ` + literal + `; enabled = f { enablePath = path; }; `
	var spec struct {
		Before, After       modulePreviewPlan
		Previous, Available []nixeval.AddonSpec
		Revision            string
	}
	err = evalModulePlan(ctx, rt, prefix+`base = f {}; in {
  before = project base; after = project enabled;
  previous = map (a: { inherit (a) id revision; }) base.addons;
  available = enabled.addons;
  revision = builtins.hashString "sha256" (builtins.toJSON enabled.addons);
}`, &spec)
	if err != nil {
		return nil, err
	}
	if spec.Previous == nil || spec.Available == nil || spec.Revision == "" {
		return nil, invalidModuleState("incomplete adoption declarations")
	}
	ledger, err := reconcile.LoadLedger(rt.root)
	if err != nil {
		return nil, invalidModuleState("could not read adoption ledger")
	}
	offers, muts, records, err := resolveAdoptionAnswers(
		id,
		spec.Previous,
		spec.Available,
		ledger,
		answers,
	)
	if err != nil {
		return nil, err
	}
	for _, m := range muts {
		parts := nixdata.SplitConfigPath(m.Path)
		if len(parts) == 0 {
			return nil, invalidModuleState("invalid adoption option path")
		}
		n := min(len(parts), len(path))
		if slices.Equal(path[:n], parts[:n]) &&
			!(slices.Equal(parts, path) && m.Value == true) {
			return nil, invalidModuleState("adoption conflicts with the module enable option")
		}
	}
	if len(muts) != 0 {
		// Pass references to fresh declarations, not their private config
		// values, on the process command line. Bind the second evaluation
		// to the declaration set just validated by the shared resolver.
		apply, err := answeredModuleProjection(prefix, spec.Revision, records)
		if err != nil {
			return nil, err
		}
		var answered struct{ Before, After modulePreviewPlan }
		if err := evalModulePlan(ctx, rt, apply, &answered); err != nil {
			return nil, err
		}
		spec.Before, spec.After = answered.Before, answered.After
	}
	before, err := spec.Before.fileHashes()
	if err != nil {
		return nil, err
	}
	after, err := spec.After.fileHashes()
	if err != nil {
		return nil, err
	}
	return &moduleAdoptionPlan{
		enablePath: path, ledger: ledger, records: records, mutations: muts,
		preview: &agentv1.ModulePreview{
			Files: modulePreviewDiff(
				before,
				after,
			),
			Services: modulePreviewDiff(spec.Before.Services, spec.After.Services),
			Packages: modulePreviewDiff(
				spec.Before.Packages,
				spec.After.Packages,
			),
			Offers: offers,
		},
	}, nil
}

// Resolve the base config and selected choice configs inside Nix. The Go
// resolver has rejected conflicting leaf assignments, so a recursive union
// reproduces exactly the patch that reconcile.Materialize will persist.
func answeredModuleProjection(
	prefix, revision string,
	records map[string]reconcile.LedgerEntry,
) (string, error) {
	type selection struct {
		ID      string   `json:"id"`
		Choices []string `json:"choices"`
	}
	choices := []selection{}
	for _, id := range slices.Sorted(maps.Keys(records)) {
		sel := selection{ID: id, Choices: []string{}}
		switch a := records[id].Answer.(type) {
		case bool:
			if !a {
				continue
			}
		case string:
			if a == "" {
				continue
			}
			sel.Choices = []string{a}
		case []string:
			if len(a) == 0 {
				continue
			}
			sel.Choices = a
		default:
			return "", invalidModuleState("invalid resolved adoption answer")
		}
		choices = append(choices, sel)
	}
	data, err := json.Marshal(choices)
	if err != nil {
		return "", err
	}
	return prefix + `decisions = builtins.fromJSON ` + nixser.QuoteString(
		string(data),
	) + `;
  by = key: values: builtins.listToAttrs (map (v: { name = v.${key}; value = v; }) values);
  specs = by "id" enabled.addons;
  configs = builtins.concatMap (s: let a = specs.${s.id}; choices = by "value" (a.question.choices or []);
    in [(a.config or {})] ++ map (k: choices.${k}.config or {}) s.choices) decisions;
  merge = a: b: builtins.zipAttrsWith (_: vs: if builtins.length vs == 1 then builtins.head vs
    else merge (builtins.head vs) (builtins.elemAt vs 1)) [a b];
  adoption = builtins.foldl' merge {} configs;
in assert builtins.hashString "sha256" (builtins.toJSON enabled.addons) == ` + nixser.QuoteString(
		revision,
	) + `;
 { before = project (f {}); after = project (f { enablePath = path; inherit adoption; }); }`, nil
}

func (s *moduleService) PreviewModuleEnable(
	ctx context.Context,
	req *connect.Request[agentv1.PreviewModuleEnableRequest],
) (*connect.Response[agentv1.PreviewModuleEnableResponse], error) {
	rt := runtimeFor(ctx)
	if rt == nil || rt.root == "" {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("no project selected"),
		)
	}
	var plan *moduleAdoptionPlan
	err := withModuleConfigLock(ctx, rt, func(ctx context.Context) error {
		var err error
		plan, err = prepareModuleAdoption(
			ctx,
			rt,
			req.Msg.GetModuleId(),
			req.Msg.GetAnswers(),
		)
		return err
	})
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(
		&agentv1.PreviewModuleEnableResponse{Preview: plan.preview},
	), nil
}
