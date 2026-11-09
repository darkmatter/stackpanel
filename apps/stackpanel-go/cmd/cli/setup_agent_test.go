package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
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
	report, err := runFreshDoctor(context.Background(), root, executable, &output, "--expectations", "/expectations with spaces.json")
	if err != nil {
		t.Fatal(err)
	}
	if report.HasErrors() || !strings.Contains(output.String(), "hook stdout noise") {
		t.Fatalf("report/log isolation failed: %+v, %s", report, output.String())
	}
	// Doctor exits nonzero when it finds problems; they are in the report.
	failing := completeSetupReport()
	failing.Findings = []reconcile.Finding{{Reconciler: "verification", ID: "config:apps.web", Severity: reconcile.SeverityError, Title: "apps.web is missing"}}
	data, _ := json.Marshal(failing)
	t.Setenv("TEST_DOCTOR_JSON", string(data))
	t.Setenv("TEST_DOCTOR_EXIT", "1")
	if report, err = runFreshDoctor(context.Background(), root, executable, io.Discard, "--expectations", "/expectations.json"); err != nil || len(doctorProblems(report)) != 1 {
		t.Fatalf("lost the report of a failing doctor: %+v %v", report, err)
	}
	t.Setenv("TEST_DOCTOR_JSON", "")
	if _, err := runFreshDoctor(context.Background(), root, executable, io.Discard, "--expectations", "/expectations.json"); err == nil {
		t.Fatal("accepted a doctor run without a report")
	}
}

func TestDoctorProblemsLeaveOutSkippedChecks(t *testing.T) {
	report := &reconcile.Report{
		CheckResults: []reconcile.CheckResult{{ID: "needs-runtime", Status: "skipped"}, {ID: "build", Status: "fail"}},
		Findings: []reconcile.Finding{
			{ID: "strict:check:needs-runtime", Severity: reconcile.SeverityError, Title: "needs-runtime: check did not pass (skipped)"},
			{ID: "check:needs-runtime", Severity: reconcile.SeverityError, Title: "needs-runtime: required check did not pass"},
			{ID: "strict:check:build", Severity: reconcile.SeverityError, Title: "build: check did not pass (fail)", Detail: "exit 1"},
			{ID: "config:apps.web", Severity: reconcile.SeverityError, Title: "apps.web: expected exists=true, got false"},
			{ID: "editorconfig", Severity: reconcile.SeverityWarning, Title: "optional"},
		},
		Errors: []reconcile.ReconcilerError{{Reconciler: "files", Err: "manifest unreadable"}},
	}
	got := strings.Join(doctorProblems(report), "\n")
	want := "files: manifest unreadable\nbuild: check did not pass (fail): exit 1\napps.web: expected exists=true, got false"
	if got != want {
		t.Fatalf("problems = %q; want %q", got, want)
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

func TestSetupPrepareRunsPlannedCommandInsideRepository(t *testing.T) {
	root, _ := setupShellFixture(t)
	app := filepath.Join(root, "apps", "web app")
	if err := os.MkdirAll(app, 0o755); err != nil {
		t.Fatal(err)
	}
	step := setupagent.PrepareCommand{ID: "deps", Dir: "apps/web app", Argv: []string{"sh", "-c", `pwd > lock; printf '%s' "$1" >> lock`, "deps", "a $b 'c'"}}
	if err := runSetupPrepare(context.Background(), root, step, io.Discard); err != nil {
		t.Fatal(err)
	}
	resolved, err := filepath.EvalSymlinks(app)
	if err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(filepath.Join(app, "lock")); string(data) != resolved+"\na $b 'c'" {
		t.Fatalf("command did not run unchanged in its directory: %q", data)
	}
	step.Argv = []string{"sh", "-c", "echo registry unreachable >&2; exit 3"}
	if err := runSetupPrepare(context.Background(), root, step, io.Discard); err == nil || !strings.Contains(err.Error(), "registry unreachable") {
		t.Fatalf("repair needs the command's own diagnostic: %v", err)
	}
	if err := os.Symlink(t.TempDir(), filepath.Join(root, "outside")); err != nil {
		t.Fatal(err)
	}
	step.Dir, step.Argv = "outside", []string{"sh", "-c", "touch ran"}
	if err := runSetupPrepare(context.Background(), root, step, io.Discard); err == nil || !strings.Contains(err.Error(), "escapes repository") {
		t.Fatalf("command ran through a symlink out of the repository: %v", err)
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
test "$3" = --command
test -z "${STACKPANEL_ROOT+x}"
test -z "${__STACKPANEL_HOOK_RAN+x}"
test -z "${DIRENV_DIR+x}"
printf '%s\n' 'hook stdout noise: {not a doctor report}'
if test "${TEST_NIX_FAILURE:-}" = 1; then
  printf '%s\n' 'fixture evaluation failure' >&2
  exit 1
fi
shift 3
exec "$@"
`)
	executable := filepath.Join(dir, "stack 'quoted' $tool")
	write(executable, `#!/bin/sh
set -eu
if test "$1" = doctor; then
  test "$2" = --expectations
  printf '%s\n' "$TEST_DOCTOR_JSON"
  exit "${TEST_DOCTOR_EXIT:-0}"
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
