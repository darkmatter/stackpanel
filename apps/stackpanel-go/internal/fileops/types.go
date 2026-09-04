// Package fileops applies declarative file manifests to a project directory.
//
// Entry types (the Nix-side `writer` axis lowered onto the applier):
//   - "json-ops" / "yaml-ops" / "toml-ops": surgical path edits inside a
//     structured document (writer = "paths")
//   - "block": a managed text block delimited by markers (writer = "block")
//   - "full-copy": overwrite from a Nix store path (adopted whole files)
//
// All writes are idempotent - unchanged files are skipped. Every mutation can
// also be previewed: PlanManifest runs the same logic with writes disabled and
// reports what ApplyManifest would do.
//
// State is tracked in a JSON sidecar so that managed paths can be reverted when
// entries are removed from the manifest.
package fileops

// Manifest is the top-level structure produced by Nix and consumed by the CLI
// preflight / setup commands. Each entry describes one managed file.
type Manifest struct {
	Version int     `json:"version"`
	Files   []Entry `json:"files"`
}

// Entry describes a single managed file. Type determines which fields apply:
//   - "json-ops" | "yaml-ops" | "toml-ops": Ops contains the patch operations;
//     Adopt controls first-contact behavior; Collisions carries plan-time
//     conflicts detected by Nix for reporting.
//   - "block": StorePath points to the Nix store content; BlockLabel/CommentPrefix
//     define the marker lines (e.g. "# -- BEGIN stackpanel --").
//   - "full-copy": StorePath is the source; the entire file is replaced.
type Entry struct {
	Path          string      `json:"path"`
	Type          string      `json:"type"` // "json-ops" | "yaml-ops" | "toml-ops" | "block" | "full-copy"
	Format        string      `json:"format,omitempty"`
	StorePath     string      `json:"storePath,omitempty"`
	BlockLabel    string      `json:"blockLabel,omitempty"`
	CommentPrefix string      `json:"commentPrefix,omitempty"`
	Mode          string      `json:"mode,omitempty"`  // octal string, e.g. "0755"
	Adopt         string      `json:"adopt,omitempty"` // "none" | "backup" | "refuse"
	Ops           []JSONOp    `json:"ops,omitempty"`
	Collisions    []Collision `json:"collisions,omitempty"`
}

// JSONOp is a single patch operation on a structured document.
// Supported ops: "set", "merge", "remove", "append", "appendUnique".
// Path is a list of keys/indices from the document root to the target location.
type JSONOp struct {
	Op    string   `json:"op"`
	Path  []string `json:"path"`
	Value any      `json:"value,omitempty"`
}

// Collision is a plan-time conflict detected by Nix: more than one definition
// contributed a replacing op (set/remove) to the same path with different
// payloads, so the last one silently wins. Reported, never resolved here.
type Collision struct {
	Path  []string `json:"path"`
	Count int      `json:"count"`
	Ops   []JSONOp `json:"ops"`
}

// Summary collects paths affected by a manifest apply (or plan) for reporting.
type Summary struct {
	Backups  []string // files backed up before first managed write
	Writes   []string // files that were (or would be) written (content changed)
	Removed  []string // files or blocks removed because their entry was dropped
	Restored []string // JSON paths reverted to their pre-managed baseline
	Skipped  []string // files where content was already up-to-date
	Refused  []string // pre-existing files an adopt = "refuse" entry would not take over (plan only)
}

// stateFile is persisted between runs so we can diff what was previously managed
// against the current manifest and revert paths that are no longer declared.
type stateFile struct {
	Version int                   `json:"version"`
	Files   map[string]stateEntry `json:"files"` // keyed by relative path from project root
}

// stateEntry records per-file state from the previous apply.
// For *-ops: OriginalJSON is the baseline before our edits, ManagedPaths
// lists every path we own. This lets us restore user content on removal.
// For full-copy: CreatedByUs is true when stackpanel created the file (it did
// not exist before the first apply). On revert, we only delete the file when
// CreatedByUs is true. Existing state files deserialize CreatedByUs as false,
// meaning files are left alone — the safe direction for backward compatibility.
type stateEntry struct {
	Type          string     `json:"type"`
	BackupPath    string     `json:"backupPath,omitempty"`
	CreatedByUs   bool       `json:"createdByUs,omitempty"`
	OriginalJSON  any        `json:"originalJson,omitempty"`
	ManagedPaths  [][]string `json:"managedPaths,omitempty"`
	BlockLabel    string     `json:"blockLabel,omitempty"`
	CommentPrefix string     `json:"commentPrefix,omitempty"`
}
