package flakeedit

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const txnSource = `{
  inputs = {
    stackpanel.url = "github:darkmatter/stackpanel";
  };
  outputs = { self, stackpanel, ... }@inputs:
    stackpanel.lib.mkFlake { inherit inputs self; };
}
`

const (
	txnOriginalLock = `{"lock":"original"}`
	txnNewLock      = `{"lock":"staged"}`
)

var txnInput = FlakeInput{Name: "calendar", URL: "github:example/calendar"}

func txnProject(t *testing.T, lock string) string {
	t.Helper()
	root := filepath.Join(t.TempDir(), "a project ; with spaces")
	require.NoError(t, os.Mkdir(root, 0o700))
	require.NoError(
		t,
		os.WriteFile(filepath.Join(root, "flake.nix"), []byte(txnSource), 0o640),
	)
	if lock != "" {
		require.NoError(
			t,
			os.WriteFile(filepath.Join(root, "flake.lock"), []byte(lock), 0o600),
		)
	}
	return root
}

// The script only stands in for the Nix executable; the public operation does
// all parsing, locking, publishing and rollback. Keep control files outside
// the project and check that Nix sees the proposed declaration in its cwd.
func txnNix(t *testing.T, root, body string) string {
	t.Helper()
	bin := t.TempDir()
	logPath := filepath.Join(bin, "calls")
	t.Setenv("TXN_CALLS", logPath)
	t.Setenv("TXN_PROJECT", root)
	t.Setenv("TXN_LOCK", txnNewLock)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	script := `#!/bin/sh
set -eu
printf '%s\n' "$2" >> "$TXN_CALLS"
test . -ef "$TXN_PROJECT"
test "$1" = flake
case "$2:$#" in
  lock:6) test "$3" = --update-input; test "$4" = calendar; grep -q calendar flake.nix; shift 4 ;;
  update:5) test "$3" = calendar; grep -q calendar flake.nix; shift 3 ;;
  lock:4) if grep -q calendar flake.nix; then exit 1; fi; shift 2 ;;
  *) exit 1 ;;
esac
test "$1" = --output-lock-file
out=$2
case "$out" in /*) ;; *) exit 1 ;; esac
test ! -e "$out"
` + body + "\n"
	require.NoError(t, os.WriteFile(filepath.Join(bin, "nix"), []byte(script), 0o700))
	return logPath
}

func txnRead(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	return string(data)
}

func txnCheckLock(t *testing.T, root, want string) {
	t.Helper()
	path := filepath.Join(root, "flake.lock")
	if want == "" {
		_, err := os.Lstat(path)
		require.ErrorIs(t, err, os.ErrNotExist)
		return
	}
	require.Equal(t, want, txnRead(t, path))
}

func TestModuleTransactionNixFailure(t *testing.T) {
	for name, lock := range map[string]string{"existing lock": txnOriginalLock, "absent lock": ""} {
		t.Run(name, func(t *testing.T) {
			root := txnProject(t, lock)
			txnNix(
				t,
				root,
				`printf 'partial' > "$out"; echo 'Nix failed halfway' >&2; exit 42`,
			)
			err := InstallModule(t.Context(), root, txnInput, "", nil)
			require.ErrorContains(t, err, "Nix failed halfway")
			require.Equal(t, txnSource, txnRead(t, filepath.Join(root, "flake.nix")))
			txnCheckLock(t, root, lock)
		})
	}
}

func TestModuleTransactionRejectsUnusableStage(t *testing.T) {
	for name, script := range map[string]string{
		"missing":   `exit 0`,
		"truncated": `printf '{' > "$out"`,
		"symlink":   `ln -s "$TXN_PROJECT/flake.lock" "$out"`,
	} {
		t.Run(name, func(t *testing.T) {
			root := txnProject(t, txnOriginalLock)
			calls := txnNix(t, root, script)
			require.Error(t, InstallModule(t.Context(), root, txnInput, "", nil))
			require.Equal(t, "lock\n", txnRead(t, calls))
			txnCheckLock(t, root, txnOriginalLock)
			require.Equal(t, txnSource, txnRead(t, filepath.Join(root, "flake.nix")))
		})
	}
}

func TestModuleTransactionRejectsStaleResult(t *testing.T) {
	// Work done by an external writer while Nix runs is not ours to roll
	// back, regardless of whether the Nix command succeeds or fails.
	for _, tc := range []struct {
		name     string
		original string
		script   string
		lock     string
		source   string
	}{
		{"changed lock", txnOriginalLock, `printf user > flake.lock`, "user", txnSource},
		{"created lock", "", `printf user > flake.lock`, "user", txnSource},
		{"removed lock", txnOriginalLock, `rm flake.lock`, "", txnSource},
		{"replaced identical lock", txnOriginalLock, `cp flake.lock other; mv other flake.lock`, txnOriginalLock, txnSource},
		{"changed flake", txnOriginalLock, `printf 'user flake' > flake.nix`, txnOriginalLock, "user flake"},
		{"failed Nix with concurrent edits", "", `printf user > flake.lock; printf 'user flake' > flake.nix; exit 1`, "user", "user flake"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := txnProject(t, tc.original)
			calls := txnNix(t, root, `printf '%s' "$TXN_LOCK" > "$out"`+"\n"+tc.script)
			require.Error(t, InstallModule(t.Context(), root, txnInput, "", nil))
			require.Equal(t, "lock\n", txnRead(t, calls))
			txnCheckLock(t, root, tc.lock)
			require.Equal(t, tc.source, txnRead(t, filepath.Join(root, "flake.nix")))
		})
	}
}

func TestModuleTransactionPreflight(t *testing.T) {
	for _, tc := range []struct {
		name, file string
	}{
		{"symlink", "flake.lock"},
		{"symlink", "flake.nix"},
		{"dangling link", "flake.lock"},
		{"read-only", "flake.lock"},
		{"read-only", "flake.nix"},
		{"parse error", "flake.nix"},
	} {
		t.Run(tc.name+"/"+tc.file, func(t *testing.T) {
			root := txnProject(t, txnOriginalLock)
			path := filepath.Join(root, tc.file)
			outside := filepath.Join(t.TempDir(), "user-file")
			switch tc.name {
			case "symlink", "dangling link":
				if tc.name == "symlink" {
					require.NoError(t, os.WriteFile(outside, []byte(txnRead(t, path)), 0o600))
				}
				require.NoError(t, os.Remove(path))
				require.NoError(t, os.Symlink(outside, path))
			case "read-only":
				require.NoError(t, os.Chmod(path, 0o444))
			case "parse error":
				require.NoError(t, os.WriteFile(path, []byte(txnSource+"???"), 0o600))
			}
			before, err := os.Lstat(path)
			require.NoError(t, err)
			calls := txnNix(t, root, `exit 1`)
			require.Error(t, InstallModule(t.Context(), root, txnInput, "", nil))
			require.NoFileExists(t, calls)
			after, err := os.Lstat(path)
			require.NoError(t, err)
			require.True(t, os.SameFile(before, after))
			require.Equal(t, before.Mode(), after.Mode())
			switch tc.name {
			case "dangling link":
				require.NoFileExists(t, outside)
			case "parse error":
				require.Equal(t, txnSource+"???", txnRead(t, path))
			default:
				require.Equal(t, txnSource, txnRead(t, filepath.Join(root, "flake.nix")))
				txnCheckLock(t, root, txnOriginalLock)
			}
		})
	}
}

func TestModuleTransactionValidatorRollback(t *testing.T) {
	for _, tc := range []struct {
		name, before string
		replace      bool
	}{
		{"restore original lock", txnOriginalLock, false},
		{"remove newly created lock", "", false},
		{"preserve independent replacements", txnOriginalLock, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := txnProject(t, tc.before)
			txnNix(t, root, `printf '%s' "$TXN_LOCK" > "$out"`)
			validationErr := errors.New("evaluation rejected the module")
			flakePath := filepath.Join(root, "flake.nix")
			lockPath := filepath.Join(root, "flake.lock")
			err := InstallModule(t.Context(), root, txnInput, "", nil, func() error {
				require.Contains(t, txnRead(t, flakePath), "calendar")
				txnCheckLock(t, root, txnNewLock)
				if tc.replace {
					// Even an atomic-save with identical staged bytes belongs to
					// the other writer; use a different inode, not just mtime.
					other := filepath.Join(root, "saved")
					require.NoError(t, os.WriteFile(other, []byte(txnNewLock), 0o600))
					require.NoError(t, os.Rename(other, lockPath))
					require.NoError(t, os.WriteFile(flakePath, []byte("user flake"), 0o640))
				}
				return validationErr
			})
			require.ErrorIs(t, err, validationErr)
			if tc.replace {
				txnCheckLock(t, root, txnNewLock)
				require.Equal(t, "user flake", txnRead(t, flakePath))
			} else {
				txnCheckLock(t, root, tc.before)
				require.Equal(t, txnSource, txnRead(t, flakePath))
			}
		})
	}
}

func TestModuleTransactionNoOpStillValidates(t *testing.T) {
	root := txnProject(t, txnOriginalLock)
	calls := txnNix(t, root, `printf '%s' "$TXN_LOCK" > "$out"`)
	require.NoError(t, InstallModule(t.Context(), root, txnInput, "", nil))
	validationErr := errors.New("not exposed by evaluated flake")
	err := InstallModule(
		t.Context(),
		root,
		txnInput,
		"",
		nil,
		func() error { return validationErr },
	)
	require.ErrorIs(t, err, validationErr)
	require.Equal(t, "lock\n", txnRead(t, calls))
	txnCheckLock(t, root, txnNewLock)
}

func TestModuleTransactionRepairsAbsentLock(t *testing.T) {
	root := txnProject(t, txnOriginalLock)
	calls := txnNix(t, root, `printf '%s' "$TXN_LOCK" > "$out"`)
	require.NoError(t, InstallModule(t.Context(), root, txnInput, "", nil))
	flakePath := filepath.Join(root, "flake.nix")
	installed, err := os.Stat(flakePath)
	require.NoError(t, err)
	require.NoError(t, os.Remove(filepath.Join(root, "flake.lock")))
	require.NoError(t, InstallModule(t.Context(), root, txnInput, "", nil))
	txnCheckLock(t, root, txnNewLock)
	require.Equal(t, "lock\nlock\n", txnRead(t, calls))
	after, err := os.Stat(flakePath)
	require.NoError(t, err)
	require.True(t, os.SameFile(installed, after))
}

func TestModuleTransactionScopedContext(t *testing.T) {
	root := txnProject(t, txnOriginalLock)
	alias := filepath.Join(t.TempDir(), "alias")
	require.NoError(t, os.Symlink(root, alias))
	calls := txnNix(t, root, `printf '%s' "$TXN_LOCK" > "$out"`)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	var fork context.Context
	err := WithModuleProject(ctx, alias, func(scoped context.Context) error {
		fork = context.WithoutCancel(scoped)
		return InstallModule(scoped, root, txnInput, "", nil, func() error {
			// A second mutation cannot borrow the same active scope while
			// this operation is validating the proposed state.
			require.ErrorContains(t, UpdateModuleWithImports(fork, root, txnInput, "", "", nil), "sequentially")
			return nil
		})
	})
	require.NoError(t, err)
	// Removing context cancellation does not extend the scope's lifetime.
	require.ErrorIs(t, UpdateModuleWithImports(fork, root, txnInput, "", "", nil), context.Canceled)
	require.Equal(t, "lock\n", txnRead(t, calls))
}

func TestModuleTransactionGuardedUninstall(t *testing.T) {
	root := txnProject(t, txnOriginalLock)
	calls := txnNix(t, root, `printf '%s' "$TXN_LOCK" > "$out"`)
	require.NoError(t, InstallModule(t.Context(), root, txnInput, "", nil))
	flakePath := filepath.Join(root, "flake.nix")
	installed := txnRead(t, flakePath)
	t.Setenv("TXN_LOCK", txnOriginalLock)
	validationErr := errors.New("removal failed evaluation")
	err := UninstallRegistryModule(t.Context(), root, txnInput, "", func() error {
		require.NotContains(t, txnRead(t, flakePath), "calendar")
		txnCheckLock(t, root, txnOriginalLock)
		return validationErr
	})
	require.ErrorIs(t, err, validationErr)
	require.Equal(t, installed, txnRead(t, flakePath))
	txnCheckLock(t, root, txnNewLock)
	require.Equal(t, "lock\nlock\n", txnRead(t, calls))
}

func TestModuleTransactionSerializesAcrossProcesses(t *testing.T) {
	const helperEnv = "STACKPANEL_TEST_FLAKE_TXN_LOCKED_PROJECT"
	if root := os.Getenv(helperEnv); root != "" {
		// This process does not share memory or even the project path spelling
		// with the installer. It must be able to cancel while waiting for it.
		ctx, cancel := context.WithTimeout(t.Context(), 250*time.Millisecond)
		defer cancel()
		require.ErrorIs(t, UpdateModuleWithImports(ctx, root, txnInput, "", "", nil), context.DeadlineExceeded)
		return
	}

	root := txnProject(t, txnOriginalLock)
	alias := filepath.Join(t.TempDir(), "alias")
	require.NoError(t, os.Symlink(root, alias))
	calls := txnNix(t, root, `printf '%s' "$TXN_LOCK" > "$out"`)
	err := InstallModule(t.Context(), root, txnInput, "", nil, func() error {
		ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
		defer cancel()
		cmd := exec.CommandContext(
			ctx,
			os.Args[0],
			"-test.run=^TestModuleTransactionSerializesAcrossProcesses$",
		)
		cmd.Env = append(os.Environ(), helperEnv+"="+alias)
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Logf("second process: %s", out)
		}
		return err
	})
	require.NoError(t, err)
	require.Equal(t, "lock\n", txnRead(t, calls))
	// The waiter never ran Nix. After release the same branch update does.
	require.NoError(t, UpdateModuleWithImports(t.Context(), alias, txnInput, "", "", nil))
	require.Equal(t, []string{"lock", "update"}, strings.Fields(txnRead(t, calls)))
}
