package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/spf13/cobra"
)

func TestFreshSetupEnvironment(t *testing.T) {
	env := freshSetupEnvironment([]string{
		"PATH=/test/bin", "HOME=/test/home", "NIX_CONFIG=keep", "PROVIDER_TOKEN=test",
		"STACKPANEL_ROOT=/wrong", "STACKPANEL_CONFIG_JSON=/stale", "STACKPANEL_STATE_DIR=/wrong",
		"__STACKPANEL_HOOK_RAN=1", "__STACKPANEL_CLEAN_ENV=1", "DIRENV_DIR=/wrong", "IN_NIX_SHELL=impure",
		"STACKPANEL_USER_CONFIG=/custom/config.json", "PWD=/wrong", "OLDPWD=/wrong",
	})
	got := strings.Join(env, "\n")
	want := "PATH=/test/bin\nHOME=/test/home\nNIX_CONFIG=keep\nPROVIDER_TOKEN=test\nSTACKPANEL_USER_CONFIG=/custom/config.json"
	if got != want {
		t.Fatalf("environment = %q; want %q", got, want)
	}
}

func TestResolveAgentSetupFlakeIgnoresConsumerRoot(t *testing.T) {
	t.Setenv("STACKPANEL_ROOT", "/consumer")
	t.Setenv("STACKPANEL_FLAKE", "")
	if got := resolveAgentSetupFlake(""); got != defaultStackpanelFlake {
		t.Fatalf("selected consumer as framework: %s", got)
	}
	t.Setenv("STACKPANEL_FLAKE", "github:fixture/framework")
	if got := resolveAgentSetupFlake(""); got != "github:fixture/framework" {
		t.Fatalf("ignored source override: %s", got)
	}
	if got := resolveAgentSetupFlake("path:/explicit"); got != "path:/explicit" {
		t.Fatalf("ignored explicit source: %s", got)
	}
}

func TestRetainSetupChecksPreventsRemovalDuringRepair(t *testing.T) {
	expected := reconcile.Expectations{Version: 1, RequiredChecks: []string{"declared"}}
	report := &reconcile.Report{CheckResults: []reconcile.CheckResult{
		{ID: "declared", Status: "pass"},
		{ID: "failed", Status: "fail"},
		{ID: "skipped", Status: "skipped"},
	}}
	retainSetupChecks(&expected, report)
	retainSetupChecks(&expected, report)
	if got := strings.Join(expected.RequiredChecks, ","); got != "declared,failed,skipped" {
		t.Fatalf("repair contract lost checks or added duplicates: %s", got)
	}
}

func TestPrepareSetupRequestRejectsDirtyLocalFramework(t *testing.T) {
	root := t.TempDir()
	bin := t.TempDir()
	script := `#!/bin/sh
if [ "$1" = flake ]; then
  printf '%s\n' '{"url":"git+file:///local/framework","path":"/nix/store/fixture-source","locked":{}}'
else
  case "$3" in
    /nix/store/fixture-source#lib.initTemplates.default) printf '%s\n' '{"flake.nix":"template"}' ;;
    /nix/store/fixture-source#lib.initAddons) printf '%s\n' '{}' ;;
    *) echo "unexpected inspection reference" >&2; exit 1 ;;
  esac
fi
`
	if err := os.WriteFile(filepath.Join(bin, "nix"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	_, err := prepareSetupRequest(context.Background(), root, setupFlags{flake: "git+file:///local/framework"})
	if err == nil || !strings.Contains(err.Error(), "local framework checkout has uncommitted changes") {
		t.Fatalf("dirty local input must not reach the agent as a directory reference: %v", err)
	}
}

func TestPrepareSetupRequestAllowsCommittedLocalFramework(t *testing.T) {
	bin := t.TempDir()
	script := `#!/bin/sh
if [ "$1" = flake ]; then
  printf '%s\n' '{"url":"git+file:///local/framework?rev=committed","locked":{"rev":"committed"}}'
else
  case "$3" in
    *'#lib.initTemplates.default') printf '%s\n' '{"flake.nix":"template"}' ;;
    *'#lib.initAddons') printf '%s\n' '{}' ;;
    *) exit 1 ;;
  esac
fi
`
	if err := os.WriteFile(filepath.Join(bin, "nix"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	request, err := prepareSetupRequest(context.Background(), t.TempDir(), setupFlags{flake: "git+file:///local/framework"})
	if err != nil || request.FlakeRef != "git+file:///local/framework?rev=committed" {
		t.Fatalf("committed local source was not retained: %+v %v", request, err)
	}
}

func TestRunFreshDoctorIsolatesShellOutputAndPaths(t *testing.T) {
	root, executable := setupShellFixture(t)
	var output bytes.Buffer
	report, err := runFreshDoctor(context.Background(), root, executable, "/expectations with spaces.json", &output)
	if err != nil {
		t.Fatal(err)
	}
	if report.HasErrors() || !strings.Contains(output.String(), "hook stdout noise") {
		t.Fatalf("report/log isolation failed: %+v, %s", report, output.String())
	}
}

func TestRunFreshDoctorRejectsFalseSuccess(t *testing.T) {
	for _, test := range []struct {
		name string
		edit func(*reconcile.Report)
	}{
		{"missing coverage", func(r *reconcile.Report) { r.Coverage = nil }},
		{"missing verification", func(r *reconcile.Report) { r.Reconcilers = r.Reconcilers[:4] }},
		{"pending changes", func(r *reconcile.Report) {
			r.Changes = []reconcile.Change{{Reconciler: "files", Kind: reconcile.ChangeCreate, Path: "missing.json"}}
		}},
		{"skipped check", func(r *reconcile.Report) {
			r.CheckResults = []reconcile.CheckResult{{ID: "missing", Scope: "repo", Status: "skipped"}}
		}},
	} {
		t.Run(test.name, func(t *testing.T) {
			root, executable := setupShellFixture(t)
			report := completeSetupReport()
			test.edit(&report)
			data, err := json.Marshal(report)
			if err != nil {
				t.Fatal(err)
			}
			t.Setenv("TEST_DOCTOR_JSON", string(data))
			if _, err := runFreshDoctor(context.Background(), root, executable, "/expectations.json", io.Discard); err == nil {
				t.Fatal("accepted incomplete report from a zero-exit process")
			}
		})
	}
}

func TestFreshReconciliationRequiresLock(t *testing.T) {
	root, executable := setupShellFixture(t)
	if err := os.Remove(filepath.Join(root, "flake.lock")); err != nil {
		t.Fatal(err)
	}
	if err := runFreshReconciliation(context.Background(), root, executable, io.Discard); err == nil || !strings.Contains(err.Error(), "flake.lock") {
		t.Fatalf("expected missing-lock error, got %v", err)
	}
}

func TestFreshReconciliationReturnsDiagnosticTail(t *testing.T) {
	root, executable := setupShellFixture(t)
	t.Setenv("TEST_NIX_FAILURE", "1")
	err := runFreshReconciliation(context.Background(), root, executable, io.Discard)
	if err == nil || !strings.Contains(err.Error(), "fixture evaluation failure") {
		t.Fatalf("repair needs the actual failure diagnostic: %v", err)
	}
}

func TestSetupLockPreservesGitAndUserEdits(t *testing.T) {
	for _, mode := range []string{"new", "unchanged", "conflicting"} {
		t.Run(mode, func(t *testing.T) {
			root := setupGitFixture(t)
			lock := filepath.Join(root, "flake.lock")
			original := []byte("user lock\n")
			if mode != "new" {
				writeSetupGitFile(t, root, "flake.lock", string(original))
			}
			ctx := context.Background()
			guard, err := captureSetupGit(ctx, root)
			if err != nil {
				t.Fatal(err)
			}
			bin := t.TempDir()
			script := `#!/bin/sh
test "$1 $2 $3 $4" = 'flake lock . --output-lock-file' || exit 1
case "$5" in "$PWD"/*) echo 'output is inside the repository' >&2; exit 1 ;; esac
test -z "${STACKPANEL_ROOT:-}" || exit 1
printf '%s\n' "$TEST_LOCK_CONTENT" > "$5"
`
			if err := os.WriteFile(filepath.Join(bin, "nix"), []byte(script), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
			t.Setenv("TEST_LOCK_CONTENT", "resolved lock")
			if mode == "unchanged" {
				t.Setenv("TEST_LOCK_CONTENT", "user lock")
			}
			err = runSetupLock(ctx, root, t.TempDir(), guard, io.Discard)
			if mode == "conflicting" {
				if err == nil || !strings.Contains(err.Error(), "preexisting user edits") {
					t.Fatalf("expected protected lock error: %v", err)
				}
			} else if err != nil {
				t.Fatal(err)
			}
			if mode != "new" {
				data, err := os.ReadFile(lock)
				if err != nil || !bytes.Equal(data, original) {
					t.Fatalf("changed user lock: %q %v", data, err)
				}
			}
			if err := guard.Check(ctx); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestSetupLockWithRealNix(t *testing.T) {
	if os.Getenv("STACKPANEL_TEST_REAL_NIX") != "1" {
		t.Skip("set STACKPANEL_TEST_REAL_NIX=1 for the Nix daemon integration test")
	}
	if _, err := exec.LookPath("nix"); err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	setupGitTestRun(t, root, "init", "-q")
	ctx := context.Background()
	guard, err := captureSetupGit(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	// No network or registry needed: exercise the actual daemon and Git-backed
	// flake machinery with a relative local input.
	writeSetupGitFile(t, root, "dependency/flake.nix", "{ outputs = _: {}; }\n")
	writeSetupGitFile(t, root, "flake.nix", "{ inputs.test.url = \"path:./dependency\"; outputs = _: {}; }\n")
	if err := guard.AddNixInputs(ctx); err != nil {
		t.Fatal(err)
	}
	before, err := setupReadIndex(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	var diagnostic bytes.Buffer
	if err := runSetupLock(ctx, root, t.TempDir(), guard, &diagnostic); err != nil {
		t.Fatalf("host lock: %v\n%s", err, diagnostic.String())
	}
	after, err := setupReadIndex(ctx, root)
	if err != nil || !reflect.DeepEqual(before, after) {
		t.Fatalf("Nix changed the index: %v", err)
	}
	data, err := os.ReadFile(filepath.Join(root, "flake.lock"))
	if err != nil || !json.Valid(data) {
		t.Fatalf("missing real lock: %s %v", data, err)
	}
	if err := guard.AddNixInputs(ctx); err != nil {
		t.Fatal(err)
	}
	if _, owned := guard.owned["flake.lock"]; !owned {
		t.Fatal("host did not retain visibility of the generated lock")
	}
}

func TestExperimentalSetupRejectsPartialVerification(t *testing.T) {
	for _, opts := range []setupFlags{
		{experimentalAgent: "auto", only: []string{"files"}},
		{experimentalAgent: "auto", skip: []string{"checks"}},
		{experimentalAgent: "auto", reconsider: true},
	} {
		cmd := &cobra.Command{}
		cmd.SetContext(context.Background())
		if err := runSetupWith(cmd, opts); err == nil || !strings.Contains(err.Error(), "cannot be combined") {
			t.Fatalf("unexpected error: %v", err)
		}
	}
}

func TestExperimentalSetupDryRunDoesNotStartAgent(t *testing.T) {
	cmd := &cobra.Command{}
	cmd.SetContext(context.Background())
	// Ordinary setup rejects this combination before evaluating or writing.
	// The agent branch would instead try to discover this nonexistent agent.
	err := runSetupWith(cmd, setupFlags{experimentalAgent: "not-an-agent", tmp: true, dryRun: true})
	if err == nil || !strings.Contains(err.Error(), "--tmp cannot be combined") {
		t.Fatalf("dry-run did not follow the read-only path: %v", err)
	}
}

func TestSetupLogTailBounded(t *testing.T) {
	var tail setupLogTail
	_, _ = tail.Write(bytes.Repeat([]byte("a"), 64*1024))
	_, _ = tail.Write([]byte("last diagnostic"))
	if len(tail.data) != 32*1024 || !bytes.HasSuffix(tail.data, []byte("last diagnostic")) {
		t.Fatalf("invalid diagnostic tail: %d bytes", len(tail.data))
	}
}

func completeSetupReport() reconcile.Report {
	r := reconcile.Report{Reconcilers: []string{"codegen", "files", "fileops", "checks", "verification"}}
	for _, id := range r.Reconcilers {
		r.Coverage = append(r.Coverage, reconcile.Coverage{Reconciler: id, Status: "complete"})
	}
	return r
}

func setupShellFixture(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()
	root := filepath.Join(dir, "repo with spaces")
	if err := os.Mkdir(root, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "flake.lock"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	write := func(path, contents string) {
		t.Helper()
		if err := os.WriteFile(path, []byte(contents), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(dir, "nix"), `#!/bin/sh
set -eu
test "$1" = develop
test "$2" = .
test "$3" = --no-update-lock-file
test "$4" = --no-write-lock-file
test "$5" = --command
test -z "${STACKPANEL_ROOT+x}"
test -z "${__STACKPANEL_HOOK_RAN+x}"
test -z "${DIRENV_DIR+x}"
printf '%s\n' 'hook stdout noise: {not a doctor report}'
if test "${TEST_NIX_FAILURE:-}" = 1; then
  printf '%s\n' 'fixture evaluation failure' >&2
  exit 1
fi
shift 5
exec "$@"
`)
	executable := filepath.Join(dir, "stack 'quoted' $tool")
	write(executable, `#!/bin/sh
set -eu
if test "$1" = doctor; then
  test "$2" = --strict
  test "$3" = --scope
  test "$4" = repo,build
  test "$5" = --build
  test "$6" = --expectations
  test "$8" = --json
  printf '%s\n' "$TEST_DOCTOR_JSON"
fi
`)
	data, err := json.Marshal(completeSetupReport())
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("TEST_DOCTOR_JSON", string(data))
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STACKPANEL_ROOT", "/wrong")
	t.Setenv("__STACKPANEL_HOOK_RAN", "1")
	t.Setenv("DIRENV_DIR", "/wrong")
	return root, executable
}
