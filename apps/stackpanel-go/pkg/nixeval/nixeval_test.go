package nixeval

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/stretchr/testify/require"
)

func writeFixture(t *testing.T, dir, filename, value string) {
	t.Helper()
	require.NoError(t, os.WriteFile(filepath.Join(dir, filename), []byte(value), 0o600))
}

func TestProjectFlakeArgsAreScopedAndSorted(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
	root, other, source := t.TempDir(), t.TempDir(), filepath.Join(
		t.TempDir(),
		"local #1",
	)
	require.NoError(t, os.Mkdir(source, 0o700))
	for _, dir := range []string{root, other, source} {
		writeFixture(t, dir, "flake.nix", `{ outputs = _: {}; }`)
	}
	m, err := userconfig.NewManager()
	require.NoError(t, err)
	require.NoError(
		t,
		m.SetLinkedModule(root, "zeta", userconfig.LinkedModule{Path: source}),
	)
	require.NoError(
		t,
		m.SetLinkedModule(root, "alpha", userconfig.LinkedModule{Path: source}),
	)
	_, err = m.SetCurrentProject(root)
	require.NoError(t, err)
	args, err := ProjectFlakeArgs(root)
	require.NoError(t, err)
	real, err := filepath.EvalSymlinks(source)
	require.NoError(t, err)
	ref := "path:" + strings.ReplaceAll(real, "local #1", "local%20%231")
	require.Equal(
		t,
		[]string{
			"--no-write-lock-file",
			"--override-input",
			"alpha",
			ref,
			"--override-input",
			"zeta",
			ref,
		},
		args,
	)
	args, err = ProjectFlakeArgs(other)
	require.NoError(t, err)
	require.Equal(t, []string{"--no-write-lock-file"}, args)
	_, err = EvalModuleState(t.Context(), "")
	require.Error(t, err)
}

// Offline integration: the only input is another local flake. Use real Nix to
// prove that the flags affect the selected consumer, that edits are visible
// (even when a lock already exists), and that errors are not masked by caches.
func TestLinkedModuleStateIsPureAndDoesNotChangeLock(t *testing.T) {
	nix, err := findNixBin()
	if err != nil {
		t.Skip("Nix not installed")
	}
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
	t.Setenv(
		"NIX_CONFIG",
		os.Getenv("NIX_CONFIG")+"\nextra-experimental-features = nix-command flakes\n",
	)
	locked, linked, root, other := t.TempDir(), t.TempDir(), t.TempDir(), t.TempDir()
	module := func(dir, value string) {
		writeFixture(
			t,
			dir,
			"flake.nix",
			fmt.Sprintf(`{ outputs = _: { value = %q; }; }`, value),
		)
	}
	module(locked, "registry")
	module(linked, "first draft")
	writeFixture(t, root, "flake.nix", fmt.Sprintf(`{
  inputs.demo.url = "path:%s";
  outputs = { self, demo }: { legacyPackages.%q.stackpanelSerializable = {
    inherit (demo) value;
    pure = !(builtins ? currentSystem);
  }; };
}`, locked, CurrentSystem()))
	// An unrelated flake in cwd and the environment must never win.
	module(other, "wrong consumer")
	t.Chdir(other)
	t.Setenv("STACKPANEL_ROOT", other)

	cmd := exec.CommandContext(t.Context(), nix, "flake", "lock")
	cmd.Dir = root
	out, err := cmd.CombinedOutput()
	require.NoError(t, err, "%s", out)
	lockFile := filepath.Join(root, "flake.lock")
	original, err := os.ReadFile(lockFile)
	require.NoError(t, err)
	m, err := userconfig.NewManager()
	require.NoError(t, err)
	require.NoError(
		t,
		m.SetLinkedModule(root, "demo", userconfig.LinkedModule{Path: linked}),
	)
	assertValue := func(value string) {
		t.Helper()
		data, err := EvalModuleState(t.Context(), root)
		require.NoError(t, err)
		require.JSONEq(t, fmt.Sprintf(`{"value":%q,"pure":true}`, value), string(data))
		unchanged, err := os.ReadFile(lockFile)
		require.NoError(t, err)
		require.Equal(t, original, unchanged)
	}
	assertValue("first draft")
	module(linked, "second draft")
	assertValue("second draft")
	writeFixture(t, linked, "flake.nix", "{ syntax error")
	_, err = EvalModuleState(t.Context(), root)
	require.Error(t, err)
	pin, err := EvalLockedModuleState(t.Context(), root)
	require.NoError(t, err)
	require.JSONEq(t, `{"value":"registry","pure":true}`, string(pin))
	require.NoError(t, m.UnlinkModule(root, "demo"))
	assertValue("registry")
}
