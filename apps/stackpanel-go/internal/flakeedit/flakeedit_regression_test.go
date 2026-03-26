package flakeedit

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHasInput_DetectsAttrsetStyleBinding(t *testing.T) {
	source := `{
  inputs = {
    legacy = {
      url = "github:old/input";
    };
  };

  outputs = { self, ... }: { };
}`

	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	assert.True(t, editor.HasInput("legacy"))

	result, err := editor.AddInput(FlakeInput{
		Name: "legacy",
		URL:  "github:author/legacy",
	})
	require.NoError(t, err)
	assert.Equal(t, source, string(result))
}

func TestDeleteNixPath_NonexistentPathReturnsOriginalSource(t *testing.T) {
	source := `{
  apps = {
    web = {
      environments = {
        dev = {
          env = {
            PORT = config.variables."/computed/apps/web/port".value;
          };
        };
      };
    };
  };
}`

	modified, err := DeleteNixPath([]byte(source), []string{"apps", "web", "environments", "dev", "env", "MISSING"})
	require.NoError(t, err)
	assert.Equal(t, source, string(modified))
}

func TestPatchAndDeletePathsRequireInputPath(t *testing.T) {
	source := []byte(`{ }`)

	_, err := PatchNixPath(source, nil, `"value"`)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "path is required")

	_, err = DeleteNixPath(source, nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "path is required")
}

func TestParseConfigVariableExpr(t *testing.T) {
	id, ok := parseConfigVariableExpr(`config.variables."/computed/apps/web/port".value`)
	require.True(t, ok)
	require.Equal(t, "/computed/apps/web/port", id)

	_, ok = parseConfigVariableExpr(`not-a-config-var`)
	assert.False(t, ok)
}
