package userconfig

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func flakeDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	require.NoError(
		t,
		os.WriteFile(
			filepath.Join(dir, "flake.nix"),
			[]byte(`{ outputs = _: {}; }`),
			0o600,
		),
	)
	real, err := filepath.EvalSymlinks(dir)
	require.NoError(t, err)
	return real
}

func TestLinkPreservesProjectsAndUnknownOptions(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", "")
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	path := DefaultConfigPath()
	require.Equal(
		t,
		filepath.Join(os.Getenv("XDG_CONFIG_HOME"), "stackpanel", "config.yaml"),
		path,
	)
	root, source, other := flakeDir(t), flakeDir(t), flakeDir(t)
	original := []byte(`version: 1
current_project: ` + other + `
default_project: ` + other + `
projects:
  - path: ` + root + `
    name: existing display name
    futureProjectOption: retain
registries: [https://org.example/modules.json, https://alt.example/catalog]
registryHeaders:
  https://org.example/modules.json: {Authorization: test-value}
  https://unlisted.example/modules.json: {Authorization: not-enabled}
futureGlobalOption: [one, two]
`)
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o700))
	require.NoError(t, os.WriteFile(path, original, 0o600))
	first, err := NewManager()
	require.NoError(t, err)
	second, err := NewManager() // intentionally stale after first manager writes
	require.NoError(t, err)
	link := LinkedModule{Path: source, UIDevURL: "http://localhost:5174/preview"}
	require.NoError(t, first.SetLinkedModule(root, "my-module", link))
	_, err = second.AddProject(other, "other")
	require.NoError(t, err)

	persisted, err := NewManager()
	require.NoError(t, err)
	require.Equal(
		t,
		[]string{"https://org.example/modules.json", "https://alt.example/catalog"},
		persisted.RegistrySources(),
	)
	require.Equal(
		t,
		map[string]map[string]string{
			"https://org.example/modules.json": {"Authorization": "test-value"},
		},
		persisted.RegistryHeaders(),
	)
	require.Equal(t, other, persisted.CurrentProjectPath())
	require.Equal(t, other, persisted.GetDefaultProjectPath())
	require.Equal(t, "existing display name", persisted.GetProject(root).Name)
	require.Equal(t, link, LinkedModules(root)["my-module"])
	require.Empty(t, LinkedModules(other))
	require.Empty(t, LinkedModules(""))

	bytes, err := os.ReadFile(path)
	require.NoError(t, err)
	require.Contains(t, string(bytes), "futureProjectOption: retain")
	require.Contains(t, string(bytes), "futureGlobalOption:")
	info, err := os.Stat(path)
	require.NoError(t, err)
	require.Equal(t, os.FileMode(0o600), info.Mode().Perm())
	require.Error(t, second.UnlinkModule(other, "my-module"))
	require.NoError(t, second.UnlinkModule(root, "my-module"))
	require.Empty(t, LinkedModules(root))
}

func TestCorruptConfigNeverClobbered(t *testing.T) {
	path := filepath.Join(t.TempDir(), "custom.yaml")
	t.Setenv("STACKPANEL_USER_CONFIG", path)
	m, err := NewManager()
	require.NoError(t, err)
	bad := []byte("projects: [bad\n")
	require.NoError(t, os.WriteFile(path, bad, 0o600))
	_, err = NewManager()
	require.Error(t, err)
	_, err = m.SetCurrentProject(t.TempDir())
	require.Error(t, err)
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	require.Equal(t, bad, data)
}

func TestUIDevURLLoopbackOnly(t *testing.T) {
	for _, valid := range []string{"", "http://localhost:5174/", "https://127.0.0.2/preview", "http://[::1]:8888/"} {
		require.NoError(t, ValidateUIDevURL(valid), valid)
	}
	for _, invalid := range []string{"//localhost:5174", "ws://127.0.0.1", "http://localhost.example", "http://127.0.0.1@external.test/", "https://user@localhost", "http://[::2]", "http://127.0.0.1:99999", "http://localhost\\@external.test", "http://localhost:5174/ui?token=secret", "http://localhost:5174/ui#secret", "http://localhost/?", "http://localhost/#"} {
		require.Error(t, ValidateUIDevURL(invalid), invalid)
	}
}

func TestEditedLinkCannotBypassURLValidation(t *testing.T) {
	root := flakeDir(t)
	path := filepath.Join(t.TempDir(), "config.yaml")
	t.Setenv("STACKPANEL_USER_CONFIG", path)
	for _, raw := range []string{"https://remote.test", "http://localhost:5174/a?secret=1", "https://127.0.0.1/#fragment", "http://user@localhost:5174"} {
		require.NoError(
			t,
			os.WriteFile(
				path,
				[]byte(
					"projects:\n  - path: "+root+"\n    linkedModules:\n      test:\n        path: /tmp/test\n        uiDevUrl: '"+raw+"'\n",
				),
				0o600,
			),
		)
		_, err := LoadLinkedModules(root)
		require.Error(t, err)
		require.Empty(t, LinkedModules(root))
	}
}
