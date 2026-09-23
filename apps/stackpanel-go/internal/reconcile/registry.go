package reconcile

import (
	"fmt"
	"sort"
	"strings"
)

// Registry is an ordered set of reconcilers. Order matters for Apply: codegen
// runs before file ops so ops see fresh generated inputs.
type Registry struct {
	items []Reconciler
}

// NewRegistry builds a registry in the given order.
func NewRegistry(items ...Reconciler) *Registry {
	r := &Registry{}
	r.Add(items...)
	return r
}

// Add appends reconcilers, rejecting duplicate IDs.
func (r *Registry) Add(items ...Reconciler) {
	for _, item := range items {
		for _, existing := range r.items {
			if existing.ID() == item.ID() {
				panic(fmt.Sprintf("reconcile: duplicate reconciler id %q", item.ID()))
			}
		}
		r.items = append(r.items, item)
	}
}

// IDs lists reconciler IDs in registry order.
func (r *Registry) IDs() []string {
	ids := make([]string, 0, len(r.items))
	for _, item := range r.items {
		ids = append(ids, item.ID())
	}
	return ids
}

// Lookup returns a reconciler by ID.
func (r *Registry) Lookup(id string) (Reconciler, bool) {
	for _, item := range r.items {
		if item.ID() == id {
			return item, true
		}
	}
	return nil, false
}

// Select narrows the registry to --only IDs (when given) minus --skip IDs.
// Unknown IDs are an error so typos are not silently ignored.
func (r *Registry) Select(only, skip []string) (*Registry, error) {
	known := map[string]bool{}
	for _, id := range r.IDs() {
		known[id] = true
	}
	for _, id := range append(append([]string{}, only...), skip...) {
		if !known[id] {
			return nil, fmt.Errorf(
				"unknown reconciler %q (known: %s)",
				id,
				strings.Join(r.IDs(), ", "),
			)
		}
	}
	onlySet := map[string]bool{}
	for _, id := range only {
		onlySet[id] = true
	}
	skipSet := map[string]bool{}
	for _, id := range skip {
		skipSet[id] = true
	}
	selected := &Registry{}
	for _, item := range r.items {
		if len(onlySet) > 0 && !onlySet[item.ID()] {
			continue
		}
		if skipSet[item.ID()] {
			continue
		}
		selected.items = append(selected.items, item)
	}
	return selected, nil
}

// Diagnose runs every reconciler read-only and merges the results into one
// Report. A reconciler that fails becomes an error-severity Finding attributed
// to it, so one broken participant does not hide the others' output.
func (r *Registry) Diagnose(ctx *Context) *Report {
	report := &Report{Reconcilers: r.IDs()}
	for _, item := range r.items {
		diagnosis, err := item.Diagnose(ctx)
		if err != nil {
			report.Findings = append(report.Findings, Finding{
				Reconciler: item.ID(),
				Severity:   SeverityError,
				Title:      "diagnose failed",
				Detail:     err.Error(),
			})
			report.Errors = append(
				report.Errors,
				ReconcilerError{Reconciler: item.ID(), Err: err.Error()},
			)
			continue
		}
		if diagnosis == nil {
			continue
		}
		report.Findings = append(report.Findings, diagnosis.Findings...)
		report.Changes = append(report.Changes, diagnosis.Changes...)
		report.Offers = append(report.Offers, diagnosis.Offers...)
		for _, note := range diagnosis.Notes {
			report.Notes = append(report.Notes, fmt.Sprintf("%s: %s", item.ID(), note))
		}
	}
	report.sort()
	return report
}

// Apply runs every reconciler's Apply in registry order, stopping at the first
// error. Results are accumulated so a partial run is still reported faithfully.
func (r *Registry) Apply(ctx *Context) (*ApplySummary, error) {
	summary := &ApplySummary{}
	for _, item := range r.items {
		result, err := item.Apply(ctx)
		if err != nil {
			return summary, fmt.Errorf("%s: %w", item.ID(), err)
		}
		if result == nil {
			continue
		}
		summary.Applied = append(summary.Applied, result.Applied...)
		for _, note := range result.Notes {
			summary.Notes = append(summary.Notes, fmt.Sprintf("%s: %s", item.ID(), note))
		}
	}
	return summary, nil
}

// ApplySummary aggregates Apply results across reconcilers.
type ApplySummary struct {
	Applied []Change `json:"applied,omitempty"`
	Notes   []string `json:"notes,omitempty"`
}

// ReconcilerError records a participant that could not diagnose.
type ReconcilerError struct {
	Reconciler string `json:"reconciler"`
	Err        string `json:"error"`
}

func severityRank(s Severity) int {
	switch s {
	case SeverityError:
		return 0
	case SeverityWarning:
		return 1
	default:
		return 2
	}
}

func (rep *Report) sort() {
	sort.SliceStable(rep.Findings, func(i, j int) bool {
		if rep.Findings[i].Reconciler != rep.Findings[j].Reconciler {
			return false
		}
		return severityRank(
			rep.Findings[i].Severity,
		) < severityRank(
			rep.Findings[j].Severity,
		)
	})
}
