// Package server provides JSON transformation utilities for Nix data.
package server

import (
	"encoding/json"
	"strings"
	"unicode"
)

// kebabToCamel converts kebab-case to camelCase.
// e.g., "variable-id" -> "variableId", "ca-url" -> "caUrl"
func kebabToCamel(s string) string {
	if !strings.Contains(s, "-") {
		return s
	}

	var result strings.Builder
	capitalizeNext := false

	for i, r := range s {
		if r == '-' {
			capitalizeNext = true
			continue
		}
		if capitalizeNext {
			result.WriteRune(unicode.ToUpper(r))
			capitalizeNext = false
		} else if i == 0 {
			result.WriteRune(unicode.ToLower(r))
		} else {
			result.WriteRune(r)
		}
	}

	return result.String()
}

// transformJSONKeysToCamel recursively transforms all keys in a JSON structure
// from kebab-case to camelCase. It preserves map keys for known map fields.
func transformJSONKeysToCamel(data any, mapFields map[string]struct{}, parentKey string) any {
	switch v := data.(type) {
	case map[string]any:
		_, skipKeyTransform := mapFields[parentKey]
		result := make(map[string]any, len(v))
		for key, value := range v {
			// Determine if this map's keys should be preserved as-is
			if skipKeyTransform {
				result[key] = transformJSONKeysToCamel(value, mapFields, key)
				continue
			}

			newKey := kebabToCamel(key)
			// If the original or converted key is a map field, preserve map keys for its value
			result[newKey] = transformJSONKeysToCamel(value, mapFields, newKey)
		}
		return result
	case []any:
		result := make([]any, len(v))
		for i, item := range v {
			result[i] = transformJSONKeysToCamel(item, mapFields, parentKey)
		}
		return result
	default:
		return v
	}
}

// transformNixJSONToCamelCase takes JSON data from Nix (which uses kebab-case)
// and converts keys to camelCase for protojson compatibility.
func transformNixJSONToCamelCase(data []byte, mapFields map[string]struct{}) ([]byte, error) {
	if len(data) == 0 {
		return data, nil
	}

	var parsed any
	if err := json.Unmarshal(data, &parsed); err != nil {
		return nil, err
	}

	transformed := transformJSONKeysToCamel(parsed, mapFields, "")
	return json.Marshal(transformed)
}

// camelToKebab converts camelCase to kebab-case.
// e.g., "variableId" -> "variable-id", "caUrl" -> "ca-url"
func camelToKebab(s string) string {
	var result strings.Builder
	for i, r := range s {
		if unicode.IsUpper(r) && i > 0 {
			result.WriteRune('-')
		}
		result.WriteRune(unicode.ToLower(r))
	}
	return result.String()
}

// transformJSONKeysToKebab recursively transforms all keys in a JSON structure
// from camelCase to kebab-case. It preserves map keys for known map fields.
func transformJSONKeysToKebab(data any, mapFields map[string]struct{}, parentKey string) any {
	switch v := data.(type) {
	case map[string]any:
		_, skipKeyTransform := mapFields[parentKey]
		result := make(map[string]any, len(v))
		for key, value := range v {
			if skipKeyTransform {
				result[key] = transformJSONKeysToKebab(value, mapFields, key)
				continue
			}

			newKey := camelToKebab(key)
			result[newKey] = transformJSONKeysToKebab(value, mapFields, newKey)
		}
		return result
	case []any:
		result := make([]any, len(v))
		for i, item := range v {
			result[i] = transformJSONKeysToKebab(item, mapFields, parentKey)
		}
		return result
	default:
		return v
	}
}

// transformCamelCaseToNixJSON takes JSON data from protojson (camelCase)
// and converts keys to kebab-case for Nix compatibility.
func transformCamelCaseToNixJSON(data []byte, mapFields map[string]struct{}) ([]byte, error) {
	if len(data) == 0 {
		return data, nil
	}

	var parsed any
	if err := json.Unmarshal(data, &parsed); err != nil {
		return nil, err
	}

	transformed := transformJSONKeysToKebab(parsed, mapFields, "")
	return json.Marshal(transformed)
}
