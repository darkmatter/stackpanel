package reconcile

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/fileops"
)

// FileopsReconciler converges source-aware entries (path writers, managed
// blocks, adopted whole files) through the fileops engine. Diagnose is
// fileops.PlanManifest; Apply is fileops.ApplyManifest.
type FileopsReconciler struct {
	// ManifestPath overrides STACKPANEL_FILES_PREFLIGHT_MANIFEST (used after a
	// config mutation, when a freshly realized manifest replaces the shell's).
	ManifestPath string
}

const fileopsID = "fileops"

// ID implements Reconciler.
func (r *FileopsReconciler) ID() string { return fileopsID }

func (r *FileopsReconciler) manifest(ctx *Context) (*fileops.Manifest, error) {
	path := r.ManifestPath
	if path == "" {
		path = ctx.Getenv("STACKPANEL_FILES_PREFLIGHT_MANIFEST")
	}
	if path == "" {
		return nil, nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read preflight files manifest: %w", err)
	}
	var manifest fileops.Manifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return nil, fmt.Errorf("parse preflight files manifest: %w", err)
	}
	return &manifest, nil
}

// Diagnose implements Reconciler.
func (r *FileopsReconciler) Diagnose(ctx *Context) (*Diagnosis, error) {
	manifest, err := r.manifest(ctx)
	if err != nil {
		return nil, err
	}
	if manifest == nil {
		return &Diagnosis{
			Notes: []string{
				"skipped: no preflight manifest (not inside the devshell, or nothing to adopt)",
			},
		}, nil
	}
	diag := &Diagnosis{}
	for _, entry := range manifest.Files {
		for _, c := range entry.Collisions {
			diag.Findings = append(diag.Findings, collisionFinding(fileopsID, entry.Path, c))
		}
	}
	summary, err := fileops.PlanManifest(ctx.ProjectRoot, ctx.StateDir, *manifest)
	if err != nil {
		return nil, err
	}
	diag.Changes = append(diag.Changes, summaryChanges(ctx, summary)...)
	for _, refused := range summary.Refused {
		diag.Findings = append(diag.Findings, Finding{
			Reconciler: fileopsID,
			ID:         "adopt-refuse",
			Severity:   SeverityError,
			Title:      "refusing to adopt existing file (adopt = \"refuse\")",
			Path:       ctx.Rel(refused),
			Detail:     "remove the file or set adopt = \"backup\" to take it over",
		})
	}
	return diag, nil
}

// Apply implements Reconciler.
func (r *FileopsReconciler) Apply(ctx *Context) (*ApplyResult, error) {
	manifest, err := r.manifest(ctx)
	if err != nil {
		return nil, err
	}
	if manifest == nil {
		return &ApplyResult{Notes: []string{"skipped: no preflight manifest"}}, nil
	}
	summary, err := fileops.ApplyManifest(ctx.ProjectRoot, ctx.StateDir, *manifest)
	if err != nil {
		return nil, err
	}
	return &ApplyResult{Applied: summaryChanges(ctx, summary)}, nil
}

// summaryChanges maps a fileops.Summary onto Changes. Writes of files that do
// not exist yet are creates; restores of `path:json.path` form keep the JSON
// path in the summary text.
func summaryChanges(ctx *Context, s fileops.Summary) []Change {
	var out []Change
	for _, b := range s.Backups {
		out = append(
			out,
			Change{
				Reconciler: fileopsID,
				Kind:       ChangeBackup,
				Path:       ctx.Rel(b),
				Summary:    "existing file backed up on first contact",
			},
		)
	}
	for _, w := range s.Writes {
		kind := ChangeUpdate
		if _, err := os.Stat(w); os.IsNotExist(err) {
			kind = ChangeCreate
		}
		out = append(out, Change{Reconciler: fileopsID, Kind: kind, Path: ctx.Rel(w)})
	}
	for _, r := range s.Restored {
		if idx := strings.LastIndex(r, ":"); idx > 0 && !strings.HasPrefix(r, "/") {
			out = append(
				out,
				Change{
					Reconciler: fileopsID,
					Kind:       ChangeRestore,
					Path:       r[:idx],
					Summary:    "restore " + r[idx+1:] + " to baseline",
				},
			)
			continue
		}
		out = append(
			out,
			Change{
				Reconciler: fileopsID,
				Kind:       ChangeRestore,
				Path:       ctx.Rel(r),
				Summary:    "restore to baseline",
			},
		)
	}
	for _, d := range s.Removed {
		out = append(
			out,
			Change{
				Reconciler: fileopsID,
				Kind:       ChangeDelete,
				Path:       ctx.Rel(d),
				Summary:    "entry no longer declared",
			},
		)
	}
	return out
}
