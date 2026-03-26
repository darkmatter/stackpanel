// json_transform.go provides package-level aliases for the JSON key transformation
// functions in pkg/nixdata/transform.go.
//
// Nix uses kebab-case for attribute names while protojson (and the web UI) uses
// camelCase. These wrappers exist so existing callers in the server package
// (connect_entities_gen.go, connect_patch.go, etc.) compile without changes.
// New code should use nixdata.* directly.
package server

import "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"

// kebabToCamel converts kebab-case to camelCase.
// e.g., "variable-id" -> "variableId", "ca-url" -> "caUrl"
func kebabToCamel(s string) string {
	return nixdata.KebabToCamel(s)
}

// camelToKebab converts camelCase to kebab-case.
// e.g., "variableId" -> "variable-id", "caUrl" -> "ca-url"
func camelToKebab(s string) string {
	return nixdata.CamelToKebab(s)
}

// transformJSONKeysToCamel recursively transforms all keys in a JSON structure
// from kebab-case to camelCase. It preserves map keys for known map fields.
func transformJSONKeysToCamel(data any, mapFields map[string]struct{}, parentKey string) any {
	return nixdata.TransformKeysToCamel(data, mapFields, parentKey)
}

// transformJSONKeysToKebab recursively transforms all keys in a JSON structure
// from camelCase to kebab-case. It preserves map keys for known map fields.
func transformJSONKeysToKebab(data any, mapFields map[string]struct{}, parentKey string) any {
	return nixdata.TransformKeysToKebab(data, mapFields, parentKey)
}

// transformNixJSONToCamelCase takes JSON data from Nix (which uses kebab-case)
// and converts keys to camelCase for protojson compatibility.
func transformNixJSONToCamelCase(data []byte, mapFields map[string]struct{}) ([]byte, error) {
	return nixdata.NixJSONToCamelCase(data, mapFields)
}

// transformCamelCaseToNixJSON takes JSON data from protojson (camelCase)
// and converts keys to kebab-case for Nix compatibility.
func transformCamelCaseToNixJSON(data []byte, mapFields map[string]struct{}) ([]byte, error) {
	return nixdata.CamelCaseToNixJSON(data, mapFields)
}
