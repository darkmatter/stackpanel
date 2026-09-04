package reconcile

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

// ScaffoldReconciler writes the project scaffolding (flake.nix, .envrc,
// .stack/...) from the stackpanel flake's lib.initTemplates.<template>, the
// same file set `nix flake init -t` copies. Existing files are left alone
// unless Force is set. This is the former `stackpanel init` fetch + write
// steps on the Reconciler contract.
type ScaffoldReconciler struct {
	FlakeRef string
	Template string
	Force    bool

	files map[string]string
}

const scaffoldID = "scaffold"

// ID implements Reconciler.
func (r *ScaffoldReconciler) ID() string { return scaffoldID }

// Fetch evaluates the template once per process.
func (r *ScaffoldReconciler) Fetch(ctx context.Context) (map[string]string, error) {
	if r.files != nil {
		return r.files, nil
	}
	files, err := nixeval.GetInitFilesFromFlakeTemplate(
		ctx,
		NormalizeFlakeRef(r.FlakeRef),
		r.Template,
	)
	if err != nil {
		return nil, fmt.Errorf(
			"failed to get init files from flake: %w\nHint: check that the flake reference %q is valid",
			err,
			r.FlakeRef,
		)
	}
	r.files = files
	return files, nil
}

// Diagnose implements Reconciler.
func (r *ScaffoldReconciler) Diagnose(ctx *Context) (*Diagnosis, error) {
	files, err := r.Fetch(ctx.Ctx)
	if err != nil {
		return nil, err
	}
	diag := &Diagnosis{}
	for _, rel := range sortedKeys(files) {
		abs := filepath.Join(ctx.ProjectRoot, rel)
		_, statErr := os.Stat(abs)
		switch {
		case errors.Is(statErr, os.ErrNotExist):
			diag.Changes = append(
				diag.Changes,
				Change{
					Reconciler: scaffoldID,
					Kind:       ChangeCreate,
					Path:       rel,
					Summary:    "template " + r.Template,
				},
			)
		case statErr != nil:
			return nil, statErr
		case r.Force:
			diag.Changes = append(
				diag.Changes,
				Change{
					Reconciler: scaffoldID,
					Kind:       ChangeUpdate,
					Path:       rel,
					Summary:    "--force overwrite",
				},
			)
		}
	}
	if len(diag.Changes) == 0 {
		diag.Notes = append(
			diag.Notes,
			fmt.Sprintf("all %d scaffolding file(s) present", len(files)),
		)
	}
	return diag, nil
}

// Apply implements Reconciler.
func (r *ScaffoldReconciler) Apply(ctx *Context) (*ApplyResult, error) {
	files, err := r.Fetch(ctx.Ctx)
	if err != nil {
		return nil, err
	}
	res := &ApplyResult{}
	created, skipped, applied, err := WriteScaffold(ctx.ProjectRoot, files, r.Force)
	if err != nil {
		return nil, err
	}
	for _, c := range applied {
		c.Reconciler = scaffoldID
		res.Applied = append(res.Applied, c)
	}
	res.Notes = append(
		res.Notes,
		fmt.Sprintf("wrote %d file(s), skipped %d", created, skipped),
	)
	return res, nil
}

// WriteScaffold writes every (path, content) pair under root, respecting
// force. Returns (created, skipped, changes, error).
func WriteScaffold(
	root string,
	files map[string]string,
	force bool,
) (int, int, []Change, error) {
	var created, skipped int
	var changes []Change
	for _, rel := range sortedKeys(files) {
		abs := filepath.Join(root, rel)
		exists := false
		if _, err := os.Stat(abs); err == nil {
			exists = true
		} else if !errors.Is(err, os.ErrNotExist) {
			return created, skipped, changes, err
		}
		if exists && !force {
			skipped++
			continue
		}
		if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
			return created, skipped, changes, fmt.Errorf(
				"failed to create directory for %s: %w",
				rel,
				err,
			)
		}
		if err := os.WriteFile(abs, []byte(files[rel]), 0o644); err != nil {
			return created, skipped, changes, fmt.Errorf("failed to write %s: %w", rel, err)
		}
		kind := ChangeCreate
		if exists {
			kind = ChangeUpdate
		}
		changes = append(changes, Change{Kind: kind, Path: rel})
		created++
	}
	return created, skipped, changes, nil
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// NormalizeFlakeRef converts "path:" references to "git+file://" for better
// performance (git filters files instead of copying everything). Other
// reference forms are returned unchanged.
func NormalizeFlakeRef(flakeRef string) string {
	if strings.HasPrefix(flakeRef, "path:") {
		return "git+file://" + strings.TrimPrefix(flakeRef, "path:")
	}
	return flakeRef
}

// RegisterReconciler records the project in ~/.config/stackpanel/stackpanel.yaml
// so the agent and studio can find it.
type RegisterReconciler struct {
	// Skip disables registration (temporary projects).
	Skip bool
}

const registerID = "register"

// ID implements Reconciler.
func (r *RegisterReconciler) ID() string { return registerID }

// Diagnose implements Reconciler.
func (r *RegisterReconciler) Diagnose(ctx *Context) (*Diagnosis, error) {
	if r.Skip {
		return &Diagnosis{Notes: []string{"temporary project not registered"}}, nil
	}
	ucm, err := userconfig.NewManager()
	if err != nil {
		return &Diagnosis{
			Findings: []Finding{
				{
					Reconciler: registerID,
					Severity:   SeverityWarning,
					Title:      "cannot read user config",
					Detail:     err.Error(),
				},
			},
		}, nil
	}
	if ucm.HasProject(ctx.ProjectRoot) {
		return &Diagnosis{Notes: []string{"project already registered"}}, nil
	}
	return &Diagnosis{
		Changes: []Change{
			{
				Reconciler: registerID,
				Kind:       ChangeUpdate,
				Path:       "~/.config/stackpanel/stackpanel.yaml",
				Summary:    "register " + filepath.Base(ctx.ProjectRoot),
			},
		},
	}, nil
}

// Apply implements Reconciler.
func (r *RegisterReconciler) Apply(ctx *Context) (*ApplyResult, error) {
	if r.Skip {
		return &ApplyResult{}, nil
	}
	ucm, err := userconfig.NewManager()
	if err != nil {
		return nil, fmt.Errorf("failed to create user config manager: %w", err)
	}
	if ucm.HasProject(ctx.ProjectRoot) {
		return &ApplyResult{}, nil
	}
	name := filepath.Base(ctx.ProjectRoot)
	if _, err := ucm.AddProject(ctx.ProjectRoot, name); err != nil {
		return nil, fmt.Errorf("failed to add project: %w", err)
	}
	return &ApplyResult{
		Applied: []Change{
			{
				Reconciler: registerID,
				Kind:       ChangeUpdate,
				Path:       "~/.config/stackpanel/stackpanel.yaml",
				Summary:    "registered " + name,
			},
		},
	}, nil
}
