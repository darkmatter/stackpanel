// Package reconcile is the engine behind `stack doctor` and `stack setup`.
//
// Four concepts, one of which is new:
//   - Modules define what it means to have X (files.entries, scripts, checks).
//   - Reconcile converges disk onto files.entries + codegen + file ops. It
//     already existed as write-files and preflight run; this package adds the
//     preview mode and the report.
//   - Addons say "you could turn X on": metadata, a question, a revision, a
//     config mutation. The only new authoring surface.
//   - Doctor observes and reports. It never installs.
//
// Every participant implements Reconciler. Diagnose is read-only and produces
// Findings (observations) and Changes (what Apply would do). `stack doctor`
// stops after Diagnose; `stack setup` renders the same report, confirms, then
// calls Apply. `preflight run` calls Apply on the reconciliation subset only,
// so shell entry never prompts and never adopts anything.
package reconcile

import (
	"context"
	"os"
	"path/filepath"
)

// Severity of a Finding. Errors make `stack doctor` exit non-zero.
type Severity string

const (
	SeverityInfo    Severity = "info"
	SeverityWarning Severity = "warning"
	SeverityError   Severity = "error"
)

// Finding is an observation. It never implies a write.
type Finding struct {
	Reconciler string   `json:"reconciler"`
	ID         string   `json:"id,omitempty"`
	Severity   Severity `json:"severity"`
	Title      string   `json:"title"`
	Detail     string   `json:"detail,omitempty"`
	Path       string   `json:"path,omitempty"`
	FixCommand string   `json:"fixCommand,omitempty"`
}

// ChangeKind classifies a planned filesystem effect.
type ChangeKind string

const (
	ChangeCreate  ChangeKind = "create"
	ChangeUpdate  ChangeKind = "update"
	ChangeDelete  ChangeKind = "delete"
	ChangeRestore ChangeKind = "restore"
	ChangeBackup  ChangeKind = "backup"
	ChangeUnknown ChangeKind = "unknown"
)

// Change is one thing Apply would do (or did). Path is project-relative when
// the target is inside the project, otherwise absolute.
type Change struct {
	Reconciler string     `json:"reconciler"`
	Kind       ChangeKind `json:"kind"`
	Path       string     `json:"path"`
	Summary    string     `json:"summary,omitempty"`
}

// Diagnosis is the read-only output of a reconciler.
type Diagnosis struct {
	Findings []Finding `json:"findings,omitempty"`
	Changes  []Change  `json:"changes,omitempty"`
	Offers   []Offer   `json:"offers,omitempty"`
	Notes    []string  `json:"notes,omitempty"`
}

// ApplyResult is what a reconciler actually did.
type ApplyResult struct {
	Applied []Change `json:"applied,omitempty"`
	Notes   []string `json:"notes,omitempty"`
}

// Context is shared by every reconciler in a run.
type Context struct {
	Ctx         context.Context
	ProjectRoot string
	// StateDir holds preflight state and the files manifest written by
	// write-files. Defaults to <root>/.stack/profile.
	StateDir string
	Verbose  bool
	// Getenv resolves environment variables; tests substitute a map.
	Getenv func(string) string
	// Config is the project's evaluated config JSON (STACKPANEL_CONFIG_JSON),
	// nil when running outside a devshell.
	Config *ProjectConfig
	// Build enables realizing build-scope doctor checks with `nix build`.
	Build bool
}

// NewContext fills defaults: os.Getenv, state dir under .stack/profile, and
// the config JSON if the devshell exported one.
func NewContext(ctx context.Context, projectRoot string) (*Context, error) {
	absRoot, err := filepath.Abs(projectRoot)
	if err != nil {
		return nil, err
	}
	c := &Context{
		Ctx:         ctx,
		ProjectRoot: absRoot,
		Getenv:      os.Getenv,
	}
	c.StateDir = c.Getenv("STACKPANEL_STATE_DIR")
	if c.StateDir == "" {
		c.StateDir = filepath.Join(absRoot, ".stack", "profile")
	}
	if cfg, err := LoadProjectConfig(c.Getenv); err == nil {
		c.Config = cfg
	}
	return c, nil
}

// InDevshell reports whether the evaluated config is available, which is what
// the codegen/files/fileops reconcilers need.
func (c *Context) InDevshell() bool {
	return c.Config != nil
}

// Rel renders a path relative to the project root for display.
func (c *Context) Rel(path string) string {
	if rel, err := filepath.Rel(c.ProjectRoot, path); err == nil && !isParentRel(rel) {
		return rel
	}
	return path
}

func isParentRel(rel string) bool {
	return rel == ".." || len(rel) >= 3 && rel[:3] == "../"
}

// Reconciler is the contract every participant implements.
type Reconciler interface {
	// ID is the stable name used by --only / --skip and in the report.
	ID() string
	// Diagnose is read-only. It must not write to the repository.
	Diagnose(*Context) (*Diagnosis, error)
	// Apply performs the changes Diagnose reported. Idempotent.
	Apply(*Context) (*ApplyResult, error)
}
