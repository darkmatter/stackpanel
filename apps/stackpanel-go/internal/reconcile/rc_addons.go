package reconcile

import (
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// AddonsReconciler lists adoption offers the user has not decided on. It
// never applies anything: `stack setup` owns the prompt, mutation and ledger
// flow; `stack doctor` only shows what would be offered.
type AddonsReconciler struct {
	// Addons overrides the config's addon list (a fresh repo evaluates
	// lib.initAddons from the stackpanel flake instead).
	Addons []nixeval.AddonSpec
	// Reconsider re-offers addons declined at the current revision.
	Reconsider bool
}

const addonsID = "addons"

// ID implements Reconciler.
func (r *AddonsReconciler) ID() string { return addonsID }

func (r *AddonsReconciler) addons(ctx *Context) []nixeval.AddonSpec {
	if r.Addons != nil {
		return r.Addons
	}
	if ctx.Config != nil {
		return ctx.Config.Addons
	}
	return nil
}

// Diagnose implements Reconciler.
func (r *AddonsReconciler) Diagnose(ctx *Context) (*Diagnosis, error) {
	addons := r.addons(ctx)
	if len(addons) == 0 {
		return &Diagnosis{Notes: []string{"no addons available"}}, nil
	}
	ledger, err := LoadLedger(ctx.ProjectRoot, RevisionsOf(addons))
	if err != nil {
		return nil, err
	}
	diag := &Diagnosis{Offers: PendingOffers(addons, ledger, r.Reconsider)}
	if ledger.MigratedFrom() != "" {
		diag.Notes = append(
			diag.Notes,
			"legacy .stack/addons.json will be migrated to reconcile.json on the next setup",
		)
	}
	if len(diag.Offers) == 0 {
		diag.Notes = append(
			diag.Notes,
			"all offers decided; use --reconsider to see declined ones again",
		)
	}
	return diag, nil
}

// Apply implements Reconciler. Offers are decided in the setup flow.
func (r *AddonsReconciler) Apply(*Context) (*ApplyResult, error) {
	return &ApplyResult{}, nil
}
