package nix

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNixPath_MarshalJSON(t *testing.T) {
	p := NixPath("./hardware/prod.nix")
	data, err := json.Marshal(p)
	require.NoError(t, err)
	assert.Equal(t, `{"__nixPath":"./hardware/prod.nix"}`, string(data))
}

func TestNixPath_UnmarshalJSON(t *testing.T) {
	var p NixPath
	err := json.Unmarshal([]byte(`{"__nixPath":"./hardware/prod.nix"}`), &p)
	require.NoError(t, err)
	assert.Equal(t, NixPath("./hardware/prod.nix"), p)
}

func TestNixPath_UnmarshalJSON_MissingKey(t *testing.T) {
	var p NixPath
	err := json.Unmarshal([]byte(`{"other":"value"}`), &p)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "__nixPath")
}

func TestNixPath_RoundTrip(t *testing.T) {
	original := NixPath("./hardware/server/hardware-configuration.nix")
	data, err := json.Marshal(original)
	require.NoError(t, err)

	var decoded NixPath
	err = json.Unmarshal(data, &decoded)
	require.NoError(t, err)
	assert.Equal(t, original, decoded)
}

func TestConvertNixPaths_PathSentinel(t *testing.T) {
	projectRoot := "/home/user/project"
	input := map[string]any{
		"__nixPath": "/home/user/project/hardware/prod.nix",
	}
	result := ConvertNixPaths(input, projectRoot)
	assert.Equal(t, NixPath("./hardware/prod.nix"), result)
}

func TestConvertNixPaths_NonPathMap(t *testing.T) {
	projectRoot := "/home/user/project"
	input := map[string]any{
		"host": "192.168.1.1",
		"port": 22,
	}
	result := ConvertNixPaths(input, projectRoot)
	m, ok := result.(map[string]any)
	require.True(t, ok)
	assert.Equal(t, "192.168.1.1", m["host"])
	assert.Equal(t, 22, m["port"])
}

func TestConvertNixPaths_NestedMaps(t *testing.T) {
	projectRoot := "/home/user/project"
	input := map[string]any{
		"machine": map[string]any{
			"host": "192.168.1.1",
			"hardwareConfig": map[string]any{
				"__nixPath": "/home/user/project/hw/prod.nix",
			},
		},
	}
	result := ConvertNixPaths(input, projectRoot)
	m := result.(map[string]any)
	machine := m["machine"].(map[string]any)
	assert.Equal(t, "192.168.1.1", machine["host"])
	assert.Equal(t, NixPath("./hw/prod.nix"), machine["hardwareConfig"])
}

func TestConvertNixPaths_Slice(t *testing.T) {
	projectRoot := "/home/user/project"
	input := []any{
		map[string]any{"__nixPath": "/home/user/project/a.nix"},
		"plain string",
		42,
	}
	result := ConvertNixPaths(input, projectRoot)
	arr, ok := result.([]any)
	require.True(t, ok)
	assert.Equal(t, NixPath("./a.nix"), arr[0])
	assert.Equal(t, "plain string", arr[1])
	assert.Equal(t, 42, arr[2])
}

func TestConvertNixPaths_OutsideProjectRoot(t *testing.T) {
	projectRoot := "/home/user/project"
	input := map[string]any{
		"__nixPath": "/etc/nixos/hardware-configuration.nix",
	}
	result := ConvertNixPaths(input, projectRoot)
	// Should use a relative path starting with ../
	nixPath, ok := result.(NixPath)
	require.True(t, ok)
	assert.Contains(t, string(nixPath), "..")
}

func TestConvertNixPaths_Primitives(t *testing.T) {
	projectRoot := "/home/user/project"
	assert.Equal(t, "hello", ConvertNixPaths("hello", projectRoot))
	assert.Equal(t, 42, ConvertNixPaths(42, projectRoot))
	assert.Equal(t, true, ConvertNixPaths(true, projectRoot))
	assert.Nil(t, ConvertNixPaths(nil, projectRoot))
}
