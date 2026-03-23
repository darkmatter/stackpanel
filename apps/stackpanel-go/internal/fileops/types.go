package fileops

type Manifest struct {
	Version int     `json:"version"`
	Files   []Entry `json:"files"`
}

type Entry struct {
	Path          string   `json:"path"`
	Type          string   `json:"type"`
	StorePath     string   `json:"storePath,omitempty"`
	BlockLabel    string   `json:"blockLabel,omitempty"`
	CommentPrefix string   `json:"commentPrefix,omitempty"`
	Mode          string   `json:"mode,omitempty"`
	Adopt         string   `json:"adopt,omitempty"`
	Ops           []JSONOp `json:"ops,omitempty"`
}

type JSONOp struct {
	Op    string   `json:"op"`
	Path  []string `json:"path"`
	Value any      `json:"value,omitempty"`
}

type Summary struct {
	Backups  []string
	Writes   []string
	Removed  []string
	Restored []string
	Skipped  []string
}

type stateFile struct {
	Version int                   `json:"version"`
	Files   map[string]stateEntry `json:"files"`
}

type stateEntry struct {
	Type          string     `json:"type"`
	BackupPath    string     `json:"backupPath,omitempty"`
	OriginalJSON  any        `json:"originalJson,omitempty"`
	ManagedPaths  [][]string `json:"managedPaths,omitempty"`
	BlockLabel    string     `json:"blockLabel,omitempty"`
	CommentPrefix string     `json:"commentPrefix,omitempty"`
}
