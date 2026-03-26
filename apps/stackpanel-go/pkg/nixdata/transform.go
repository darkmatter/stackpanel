package nixdata

// Nix uses kebab-case for attribute names, but Go/TypeScript/protobuf use
// camelCase. This file handles bidirectional conversion, with special care
// to preserve user-defined map keys (variable IDs, app names, etc.) that
// must pass through untouched.

import (
	"encoding/json"
	"strings"
	"unicode"
)

// KebabToCamel converts a kebab-case string to camelCase.
//
//	"variable-id" -> "variableId"
//	"ca-url"      -> "caUrl"
//	"already"     -> "already"
func KebabToCamel(s string) string {
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

// CamelToKebab converts a camelCase string to kebab-case.
//
//	"variableId" -> "variable-id"
//	"caUrl"      -> "ca-url"
//	"already"    -> "already"
func CamelToKebab(s string) string {
	var result strings.Builder
	for i, r := range s {
		if unicode.IsUpper(r) && i > 0 {
			result.WriteRune('-')
		}
		result.WriteRune(unicode.ToLower(r))
	}
	return result.String()
}

// TransformKeysToCamel recursively converts all JSON object keys from
// kebab-case to camelCase. The mapFields set controls which parent keys
// should have their children's keys left untouched — this is critical
// because user-defined map keys (app names, variable IDs) are not schema
// names and must not be case-transformed.
//
// parentKey tracks the converted key of the current node's parent so we
// can check whether we're inside a map field.
func TransformKeysToCamel(data any, mapFields map[string]struct{}, parentKey string) any {
	switch v := data.(type) {
	case map[string]any:
		_, skipKeyTransform := mapFields[parentKey]
		result := make(map[string]any, len(v))
		for key, value := range v {
			if skipKeyTransform {
				// Parent is a map field — preserve this key as-is.
				result[key] = TransformKeysToCamel(value, mapFields, key)
				continue
			}
			newKey := KebabToCamel(key)
			result[newKey] = TransformKeysToCamel(value, mapFields, newKey)
		}
		return result
	case []any:
		result := make([]any, len(v))
		for i, item := range v {
			result[i] = TransformKeysToCamel(item, mapFields, parentKey)
		}
		return result
	default:
		return v
	}
}

// TransformKeysToKebab recursively converts all JSON object keys in data
// from camelCase to kebab-case. Keys that are children of a known map field
// (see MapFieldNames) are preserved verbatim.
func TransformKeysToKebab(data any, mapFields map[string]struct{}, parentKey string) any {
	switch v := data.(type) {
	case map[string]any:
		_, skipKeyTransform := mapFields[parentKey]
		result := make(map[string]any, len(v))
		for key, value := range v {
			if skipKeyTransform {
				result[key] = TransformKeysToKebab(value, mapFields, key)
				continue
			}
			newKey := CamelToKebab(key)
			result[newKey] = TransformKeysToKebab(value, mapFields, newKey)
		}
		return result
	case []any:
		result := make([]any, len(v))
		for i, item := range v {
			result[i] = TransformKeysToKebab(item, mapFields, parentKey)
		}
		return result
	default:
		return v
	}
}

// NixJSONToCamelCase takes raw JSON produced by nix eval (kebab-case keys)
// and returns JSON with keys converted to camelCase, suitable for protojson
// or standard Go struct unmarshalling.
//
// mapFields controls which parent keys should have their children's keys
// left untouched. Pass MapFieldNames() for the standard Stackpanel set.
func NixJSONToCamelCase(data []byte, mapFields map[string]struct{}) ([]byte, error) {
	if len(data) == 0 {
		return data, nil
	}

	var parsed any
	if err := json.Unmarshal(data, &parsed); err != nil {
		return nil, err
	}

	transformed := TransformKeysToCamel(parsed, mapFields, "")
	return json.Marshal(transformed)
}

// CamelCaseToNixJSON takes JSON with camelCase keys (e.g. from protojson)
// and returns JSON with kebab-case keys suitable for writing to Nix.
//
// mapFields controls which parent keys should have their children's keys
// left untouched. Pass MapFieldNames() for the standard Stackpanel set.
func CamelCaseToNixJSON(data []byte, mapFields map[string]struct{}) ([]byte, error) {
	if len(data) == 0 {
		return data, nil
	}

	var parsed any
	if err := json.Unmarshal(data, &parsed); err != nil {
		return nil, err
	}

	transformed := TransformKeysToKebab(parsed, mapFields, "")
	return json.Marshal(transformed)
}
