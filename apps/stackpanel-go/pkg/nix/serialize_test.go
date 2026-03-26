package nix

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSerialize_Primitives(t *testing.T) {
	tests := []struct {
		name     string
		input    any
		expected string
	}{
		{"nil", nil, "null"},
		{"true", true, "true"},
		{"false", false, "false"},
		{"int", 42, "42"},
		{"negative int", -17, "-17"},
		{"int64", int64(9223372036854775807), "9223372036854775807"},
		{"uint", uint(100), "100"},
		{"float", 3.14, "3.14"},
		{"float whole", 42.0, "42"},            // Whole floats serialize as integers
		{"float64 from json", float64(2), "2"}, // JSON-decoded integers come as float64
		{"string", "hello", `"hello"`},
		{"empty string", "", `""`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := Serialize(tt.input)
			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestSerialize_StringEscaping(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"backslash", `a\b`, `"a\\b"`},
		{"double quote", `say "hi"`, `"say \"hi\""`},
		{"newline", "line1\nline2", "''line1\nline2''"},
		{"tab", "a\tb", `"a\tb"`},
		{"dollar sign", "cost $5", `"cost \$5"`},
		{"interpolation", "${foo}", `"\${foo}"`},
		{"multiline with dollar", "a\n${b}", "''a\n''${b}''"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := Serialize(tt.input)
			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestSerialize_Slices(t *testing.T) {
	tests := []struct {
		name     string
		input    any
		expected string
	}{
		{"empty slice", []int{}, "[ ]"},
		{"int slice", []int{1, 2, 3}, "[ 1 2 3 ]"},
		{"string slice", []string{"a", "b"}, `[ "a" "b" ]`},
		{"mixed via interface", []any{1, "two", true}, `[ 1 "two" true ]`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := Serialize(tt.input)
			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestSerialize_Maps(t *testing.T) {
	tests := []struct {
		name     string
		input    any
		expected string
	}{
		{"empty map", map[string]int{}, "{ }"},
		{"simple map", map[string]int{"a": 1}, `{ a = 1; }`},
		{"string values", map[string]string{"name": "test"}, `{ name = "test"; }`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := Serialize(tt.input)
			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestSerialize_MapKeysSorted(t *testing.T) {
	input := map[string]int{"z": 1, "a": 2, "m": 3}
	result, err := Serialize(input)
	require.NoError(t, err)
	assert.Equal(t, "{ a = 2; m = 3; z = 1; }", result)
}

func TestSerialize_Structs(t *testing.T) {
	type Simple struct {
		Name  string `json:"name"`
		Value int    `json:"value"`
	}

	result, err := Serialize(Simple{Name: "test", Value: 42})
	require.NoError(t, err)
	assert.Equal(t, `{ name = "test"; value = 42; }`, result)
}

func TestSerialize_StructWithOmitempty(t *testing.T) {
	type WithOptional struct {
		Required string  `json:"required"`
		Optional *string `json:"optional,omitempty"`
	}

	// Without optional
	result, err := Serialize(WithOptional{Required: "yes"})
	require.NoError(t, err)
	assert.Equal(t, `{ required = "yes"; }`, result)

	// With optional
	opt := "present"
	result, err = Serialize(WithOptional{Required: "yes", Optional: &opt})
	require.NoError(t, err)
	assert.Equal(t, `{ required = "yes"; optional = "present"; }`, result)
}

func TestSerialize_NestedStruct(t *testing.T) {
	type Inner struct {
		Value int `json:"value"`
	}
	type Outer struct {
		Name  string `json:"name"`
		Inner Inner  `json:"inner"`
	}

	result, err := Serialize(Outer{Name: "test", Inner: Inner{Value: 42}})
	require.NoError(t, err)
	assert.Equal(t, `{ name = "test"; inner = { value = 42; }; }`, result)
}

func TestSerialize_Pointers(t *testing.T) {
	// Nil pointer
	var nilPtr *string
	result, err := Serialize(nilPtr)
	require.NoError(t, err)
	assert.Equal(t, "null", result)

	// Non-nil pointer
	s := "hello"
	result, err = Serialize(&s)
	require.NoError(t, err)
	assert.Equal(t, `"hello"`, result)
}

func TestSerialize_AttrNameQuoting(t *testing.T) {
	tests := []struct {
		name     string
		input    map[string]int
		contains string
	}{
		{"simple name", map[string]int{"foo": 1}, "foo = 1"},
		{"with hyphen", map[string]int{"foo-bar": 1}, "foo-bar = 1"},
		{"with number", map[string]int{"foo2": 1}, "foo2 = 1"},
		{"starts with number", map[string]int{"2foo": 1}, `"2foo" = 1`},
		{"with space", map[string]int{"foo bar": 1}, `"foo bar" = 1`},
		{"with dot", map[string]int{"foo.bar": 1}, `"foo.bar" = 1`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := Serialize(tt.input)
			require.NoError(t, err)
			assert.Contains(t, result, tt.contains)
		})
	}
}

func TestSerializeIndented(t *testing.T) {
	type App struct {
		Port int  `json:"port"`
		TLS  bool `json:"tls"`
	}
	type Config struct {
		Name string         `json:"name"`
		Apps map[string]App `json:"apps"`
	}

	input := Config{
		Name: "test",
		Apps: map[string]App{
			"web": {Port: 3000, TLS: true},
		},
	}

	result, err := SerializeIndented(input, "  ")
	require.NoError(t, err)

	// Should contain newlines and indentation
	assert.Contains(t, result, "\n")
	assert.Contains(t, result, "  ")
}

func TestSerialize_InvalidMapKey(t *testing.T) {
	input := map[int]string{1: "one"}
	_, err := Serialize(input)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "map keys must be strings")
}

// Test with actual stackpanel-like types
func TestSerialize_NullValues(t *testing.T) {
	// Test data similar to what was causing the panic with null values
	data := map[string]interface{}{
		"docs": map[string]interface{}{
			"name": "docs",
			"path": "apps/docs",
			"variables": map[string]interface{}{
				"NODE-ENV": map[string]interface{}{
					"environments": []interface{}{"staging", "dev"},
					"variable-id":  nil, // This was causing the issue
				},
			},
		},
	}

	// Should not panic
	result, err := SerializeIndented(data, "  ")
	require.NoError(t, err)
	assert.Contains(t, result, "variable-id = null")
	assert.Contains(t, result, "docs")
}

// TestSerialize_JSONDecodedEnums tests that enum values (which JSON decodes as float64)
// are serialized as integers, not floats like "2.0"
func TestSerialize_JSONDecodedEnums(t *testing.T) {
	// Simulate what happens when JSON decodes {"type": 2} - the 2 becomes float64(2)
	data := map[string]interface{}{
		"key":         "POSTGRES_URL",
		"type":        float64(2), // AppVariableType.VARIABLE = 2, JSON decodes as float64
		"variable_id": "postgres-url",
	}

	result, err := Serialize(data)
	require.NoError(t, err)

	// Should contain "type = 2" not "type = 2.0"
	assert.Contains(t, result, "type = 2;")
	assert.NotContains(t, result, "type = 2.0")
}

// Nix path literals (./foo.nix, ../bar.nix) must be serialized as quoted
// strings by the generic serializer. Preserving unquoted path literals
// through a JSON round-trip was previously handled by a NixPath sentinel
// type, but that approach was replaced by tree-sitter direct edits
// (flakeedit.PatchNixPath). This test ensures the serializer treats path-
// like strings the same as any other string — no special-casing.
func TestSerialize_PathLikeStringsAreQuoted(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"relative path", "./hardware/prod.nix", `"./hardware/prod.nix"`},
		{"parent path", "../other/config.nix", `"../other/config.nix"`},
		{"absolute path", "/etc/nixos/hardware-configuration.nix", `"/etc/nixos/hardware-configuration.nix"`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := Serialize(tt.input)
			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestSerialize_PathLikeStringInMap(t *testing.T) {
	m := map[string]any{
		"hardwareConfig": "./hardware/prod.nix",
	}
	result, err := Serialize(m)
	require.NoError(t, err)
	assert.Contains(t, result, `hardwareConfig = "./hardware/prod.nix"`)
	assert.NotContains(t, result, `hardwareConfig = ./hardware/prod.nix;`)
}

func TestSerialize_StackpanelTypes(t *testing.T) {
	type App struct {
		Port   int     `json:"port"`
		Domain *string `json:"domain,omitempty"`
		TLS    bool    `json:"tls"`
	}

	domain := "web.localhost"
	apps := map[string]App{
		"web": {Port: 3000, Domain: &domain, TLS: true},
		"api": {Port: 3001, TLS: false},
	}

	result, err := Serialize(apps)
	require.NoError(t, err)

	// Verify structure
	assert.Contains(t, result, "api =")
	assert.Contains(t, result, "web =")
	assert.Contains(t, result, "port = 3000")
	assert.Contains(t, result, `domain = "web.localhost"`)
	assert.Contains(t, result, "tls = true")
}
