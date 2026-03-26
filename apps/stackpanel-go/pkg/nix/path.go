package nix

import (
	"encoding/json"
	"fmt"
	"path/filepath"
)

// NixPath represents a Nix path literal (e.g. ./hardware/prod.nix).
// It serializes to/from a tagged object {"__nixPath": "..."} to preserve
// path type information through JSON round-trips.
//
// Round-trip:
//
//	./hardware/prod.nix  →  {"__nixPath": "/abs/.../prod.nix"}
//	                     →  NixPath("./hardware/prod.nix")
//	                     →  ./hardware/prod.nix  (Nix expression)
type NixPath string

// MarshalJSON encodes the path as {"__nixPath": "<path>"}.
func (p NixPath) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]string{"__nixPath": string(p)})
}

// UnmarshalJSON decodes {"__nixPath": "..."} back to a NixPath.
func (p *NixPath) UnmarshalJSON(data []byte) error {
	var m map[string]string
	if err := json.Unmarshal(data, &m); err != nil {
		return err
	}
	path, ok := m["__nixPath"]
	if !ok {
		return fmt.Errorf("NixPath: missing __nixPath key in %s", data)
	}
	*p = NixPath(path)
	return nil
}

// ConvertNixPaths walks a decoded JSON value and replaces any map of the form
// {"__nixPath": "/abs/path"} with a NixPath relative to projectRoot.
// All other values are returned unchanged.
//
// This is used in Phase 2 (config.nix editing) to preserve path literals
// through the nix eval → Go → serialize round-trip.
func ConvertNixPaths(v any, projectRoot string) any {
	switch val := v.(type) {
	case map[string]any:
		// Check if this is a __nixPath sentinel (exactly one key)
		if raw, ok := val["__nixPath"]; ok && len(val) == 1 {
			if absPath, ok := raw.(string); ok {
				rel, err := filepath.Rel(projectRoot, absPath)
				if err != nil {
					// Cannot make relative — keep absolute
					return NixPath(absPath)
				}
				// Ensure path starts with ./ or ../
				if !filepath.IsAbs(rel) && len(rel) > 0 && rel[0] != '.' {
					rel = "./" + rel
				}
				return NixPath(rel)
			}
		}
		// Recursively process map values
		result := make(map[string]any, len(val))
		for k, v2 := range val {
			result[k] = ConvertNixPaths(v2, projectRoot)
		}
		return result
	case []any:
		result := make([]any, len(val))
		for i, elem := range val {
			result[i] = ConvertNixPaths(elem, projectRoot)
		}
		return result
	default:
		return v
	}
}
