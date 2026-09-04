package fileops

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// ManagedPaths returns the project-relative paths (and their entry types) the
// applier already manages, from the state sidecar. Callers use it to tell
// first contact from an ongoing update. A missing state file yields an empty map.
func ManagedPaths(stateDir string) map[string]string {
	out := map[string]string{}
	data, err := os.ReadFile(filepath.Join(stateDir, stateFilename))
	if err != nil {
		return out
	}
	var st stateFile
	if err := json.Unmarshal(data, &st); err != nil {
		return out
	}
	for path, entry := range st.Files {
		out[path] = entry.Type
	}
	return out
}

// DecodeDocument parses a json/yaml/toml document into the generic map.
func DecodeDocument(format string, data []byte) (map[string]any, error) {
	c, ok := codecForType(format + "-ops")
	if !ok {
		return nil, fmt.Errorf("fileops: unsupported document format %q", format)
	}
	if len(data) == 0 {
		return map[string]any{}, nil
	}
	return c.Decode(data)
}

// PreviewOps applies ops to a copy of doc and returns the result, without
// baseline tracking. Used to preview a paths writer before any state exists.
func PreviewOps(doc map[string]any, ops []JSONOp) (map[string]any, error) {
	normalized, _, err := normalizeJSONOps(ops)
	if err != nil {
		return nil, err
	}
	next := cloneMap(doc)
	for _, op := range normalized {
		if err := applyJSONOp(next, op); err != nil {
			return nil, err
		}
	}
	return next, nil
}

// DocumentsEqual compares two documents structurally, tolerating numeric type
// differences between codecs (json float64 vs yaml/toml int).
func DocumentsEqual(a, b map[string]any) bool {
	return jsonEqual(a, b)
}
