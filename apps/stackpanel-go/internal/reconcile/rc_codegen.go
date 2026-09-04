package reconcile

import (
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/codegen"
)

// CodegenReconciler converges host-side generated artifacts (env payloads,
// manifests) using the codegen Builder. Diagnose is Builder.Diff; Apply is
// Builder.Build with the same module selection.
type CodegenReconciler struct {
	Modules []string // empty means every registered module
	Force   bool
}

const codegenID = "codegen"

// ID implements Reconciler.
func (r *CodegenReconciler) ID() string { return codegenID }

// Diagnose implements Reconciler.
func (r *CodegenReconciler) Diagnose(ctx *Context) (*Diagnosis, error) {
	if !ctx.InDevshell() {
		return &Diagnosis{
			Notes: []string{
				"skipped: not inside the devshell (STACKPANEL_CONFIG_JSON unset)",
			},
		}, nil
	}
	builder := codegen.NewBuilder(codegen.DefaultRegistry())
	summary, err := builder.Diff(ctx.Ctx, ctx.ProjectRoot, r.Modules, ctx.Verbose)
	if err != nil {
		return nil, err
	}
	diag := &Diagnosis{}
	for _, result := range summary.Results {
		for _, d := range result.Diffs {
			kind := ChangeKind("")
			switch d.Action {
			case codegen.ArtifactActionCreate:
				kind = ChangeCreate
			case codegen.ArtifactActionUpdate:
				kind = ChangeUpdate
			case codegen.ArtifactActionRemove:
				kind = ChangeDelete
			default:
				continue
			}
			diag.Changes = append(
				diag.Changes,
				Change{
					Reconciler: codegenID,
					Kind:       kind,
					Path:       ctx.Rel(d.Path),
					Summary:    "module " + result.Module,
				},
			)
		}
		for _, w := range result.Warnings {
			diag.Findings = append(
				diag.Findings,
				Finding{
					Reconciler: codegenID,
					ID:         result.Module,
					Severity:   SeverityWarning,
					Title:      w,
				},
			)
		}
		if ctx.Verbose {
			diag.Notes = append(diag.Notes, result.Notes...)
		}
	}
	return diag, nil
}

// Apply implements Reconciler.
func (r *CodegenReconciler) Apply(ctx *Context) (*ApplyResult, error) {
	if !ctx.InDevshell() {
		return &ApplyResult{Notes: []string{"skipped: not inside the devshell"}}, nil
	}
	builder := codegen.NewBuilder(codegen.DefaultRegistry())
	summary, err := builder.Build(
		ctx.Ctx,
		ctx.ProjectRoot,
		r.Modules,
		r.Force,
		ctx.Verbose,
	)
	if err != nil {
		return nil, err
	}
	res := &ApplyResult{}
	for _, result := range summary.Results {
		for _, f := range result.Files {
			res.Applied = append(
				res.Applied,
				Change{
					Reconciler: codegenID,
					Kind:       ChangeUpdate,
					Path:       ctx.Rel(f),
					Summary:    "module " + result.Module,
				},
			)
		}
		for _, f := range result.Removed {
			res.Applied = append(
				res.Applied,
				Change{
					Reconciler: codegenID,
					Kind:       ChangeDelete,
					Path:       ctx.Rel(f),
					Summary:    "module " + result.Module,
				},
			)
		}
		for _, w := range result.Warnings {
			res.Notes = append(res.Notes, "warning: "+w)
		}
	}
	return res, nil
}
