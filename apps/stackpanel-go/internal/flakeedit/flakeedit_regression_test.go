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

	modified, err := DeleteNixPath(
		[]byte(source),
		[]string{"apps", "web", "environments", "dev", "env", "MISSING"},
	)
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

// TestPatchNixPath_SiblingDottedPrefixMergesNotOverwrites guards against a
// regression where inserting a new leaf under a key that already has a sibling
// dotted binding (e.g. patching `ide.vscode.enable` when `ide.zed.enable = true;`
// exists) emitted a fresh `ide = { ... };` block. That produces two top-level
// `ide` attributes, which Nix rejects ("attribute 'ide' already defined") and
// effectively clobbers the existing value. The patch must merge by reusing
// dotted notation instead.
func TestPatchNixPath_SiblingDottedPrefixMergesNotOverwrites(t *testing.T) {
	source := `{
  ide.zed.enable = true;
}
`

	modified, err := PatchNixPath(
		[]byte(source),
		[]string{"ide", "vscode", "enable"},
		`true`,
	)
	require.NoError(t, err)
	result := string(modified)

	// The existing sibling must be preserved verbatim.
	assert.Contains(t, result, `ide.zed.enable = true;`)
	// The new leaf must be added in dotted form so it merges with the sibling.
	assert.Contains(t, result, `ide.vscode.enable = true;`)
	// And crucially, there must be no conflicting `ide = {` attrset block that
	// would duplicate the `ide` attribute.
	assert.NotContains(t, result, `ide = {`)
}

// TestPatchNixPath_SiblingDottedPrefixDeeperLeaf covers a deeper divergence:
// `ide.zed.enable` exists and we add `ide.vscode.settings.theme`. The shared
// `ide` prefix means dotted notation must be used for the whole new path.
func TestPatchNixPath_SiblingDottedPrefixDeeperLeaf(t *testing.T) {
	source := `{
  ide.zed.enable = true;
}
`

	modified, err := PatchNixPath(
		[]byte(source),
		[]string{"ide", "vscode", "settings", "theme"},
		`"dark"`,
	)
	require.NoError(t, err)
	result := string(modified)

	assert.Contains(t, result, `ide.zed.enable = true;`)
	assert.Contains(t, result, `ide.vscode.settings.theme = "dark";`)
	assert.NotContains(t, result, `ide = {`)
}

// TestPatchNixPath_NoSiblingCollisionKeepsNestedForm ensures the merge-safe
// dotted insertion only kicks in on a real prefix collision; a genuinely new
// subtree still uses the readable nested attrset form.
func TestPatchNixPath_NoSiblingCollisionKeepsNestedForm(t *testing.T) {
	source := `{
  ide.zed.enable = true;
}
`

	modified, err := PatchNixPath(
		[]byte(source),
		[]string{"git", "hooks", "enable"},
		`true`,
	)
	require.NoError(t, err)
	result := string(modified)

	assert.Contains(t, result, `ide.zed.enable = true;`)
	assert.Contains(t, result, `git = {`)
	assert.Contains(t, result, `enable = true;`)
}

func TestParseConfigVariableExpr(t *testing.T) {
	id, ok := parseConfigVariableExpr(`config.variables."/computed/apps/web/port".value`)
	require.True(t, ok)
	require.Equal(t, "/computed/apps/web/port", id)

	_, ok = parseConfigVariableExpr(`not-a-config-var`)
	assert.False(t, ok)
}
