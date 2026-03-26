// Package fileops applies declarative file manifests to a project directory.
//
// It supports three entry types: "json-ops" (surgical JSON path edits), "block"
// (managed text blocks delimited by markers), and "full-copy" (overwrite from a
// Nix store path). All writes are idempotent - unchanged files are skipped.
//
// State is tracked in a JSON sidecar so that managed paths can be reverted when
// entries are removed from the manifest.
package fileops

// Manifest is the top-level structure produced by Nix and consumed by the CLI
// init command. Each entry describes one managed file.
type Manifest struct {
	Version int     `json:"version"`
	Files   []Entry `json:"files"`
}

// Entry describes a single managed file. Type determines which fields apply:
//   - "json-ops": Ops contains the patch operations; Adopt controls backup behavior.
//   - "block": StorePath points to the Nix store content; BlockLabel/CommentPrefix
//     define the marker lines (e.g. "# -- BEGIN stackpanel --").
//   - "full-copy": StorePath is the source; the entire file is replaced.
type Entry struct {
	Path          string   `json:"path"`
	Type          string   `json:"type"` // "json-ops" | "block" | "full-copy"
	StorePath     string   `json:"storePath,omitempty"`
	BlockLabel    string   `json:"blockLabel,omitempty"`
	CommentPrefix string   `json:"commentPrefix,omitempty"`
	Mode          string   `json:"mode,omitempty"`  // octal string, e.g. "0755"
	Adopt         string   `json:"adopt,omitempty"` // "backup" to preserve existing content
	Ops           []JSONOp `json:"ops,omitempty"`
}

// JSONOp is a single patch operation on a JSON document.
// Supported ops: "set", "merge", "remove", "append", "appendUnique".
// Path is a list of keys/indices from the document root to the target location.
type JSONOp struct {
	Op    string   `json:"op"`
	Path  []string `json:"path"`
	Value any      `json:"value,omitempty"`
}

// Summary collects paths affected by a manifest apply for reporting to the user.
type Summary struct {
	Backups  []string // files backed up before first managed write
	Writes   []string // files that were written (content changed)
	Removed  []string // files or blocks removed because their entry was dropped
	Restored []string // JSON paths reverted to their pre-managed baseline
	Skipped  []string // files where content was already up-to-date
}

// stateFile is persisted between runs so we can diff what was previously managed
// against the current manifest and revert paths that are no longer declared.
type stateFile struct {
	Version int                   `json:"version"`
	Files   map[string]stateEntry `json:"files"` // keyed by relative path from project root
}

// stateEntry records per-file state from the previous apply.
// For json-ops: OriginalJSON is the baseline before our edits, ManagedPaths
// lists every JSON path we own. This lets us restore user content on removal.
type stateEntry struct {
	Type          string     `json:"type"`
	BackupPath    string     `json:"backupPath,omitempty"`
	OriginalJSON  any        `json:"originalJson,omitempty"`
	ManagedPaths  [][]string `json:"managedPaths,omitempty"`
	BlockLabel    string     `json:"blockLabel,omitempty"`
	CommentPrefix string     `json:"commentPrefix,omitempty"`
}
