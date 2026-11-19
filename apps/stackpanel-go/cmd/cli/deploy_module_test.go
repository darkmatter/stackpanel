package cmd

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestDeclaredDeployShadowsBuiltinAndPreservesArgv(t *testing.T) {
	root := t.TempDir()
	t.Setenv("STACKPANEL_ROOT", t.TempDir()) // stale shell, not the deployment's project
	t.Setenv("STACKPANEL_TEST_PAIRING_TOKEN", "test-only-not-for-children")
	script := filepath.Join(root, "backend;literal")
	if err := os.WriteFile(
		script,
		[]byte(
			"#!/bin/sh\n[ -z \"${STACKPANEL_TEST_PAIRING_TOKEN+x}\" ] || exit 3\nprintf '%s\\n' \"$@\" > args\n",
		),
		0o755,
	); err != nil {
		t.Fatal(err)
	}
	app := "api; echo unsafe"
	env := "test stage"
	targets := []string{"$(touch injected)", "two words"}
	cfg := &DeployStackpanelConfig{
		projectRoot: root,
		Apps: map[string]DeployAppConfig{
			app: {
				Deployment: AppDeploymentOptions{
					Enable:     true,
					Backend:    "colmena",
					DefaultEnv: env,
					Targets:    targets,
				},
			},
		},
		DeployBackends: map[string]DeployBackend{"colmena": {Script: &script}},
	}
	if err := runDeploy(t.Context(), cfg, app, true); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "args")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("dry-run executed backend: %v", err)
	}
	if err := runDeploy(t.Context(), cfg, app, false); err != nil {
		t.Fatal(err)
	}
	read, err := os.ReadFile(filepath.Join(root, "args"))
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Split(
		strings.TrimSuffix(string(read), "\n"),
		"\n",
	); !slices.Equal(
		got,
		append([]string{app, env}, targets...),
	) {
		t.Errorf("backend args = %q", got)
	}
	if _, err := os.Stat(
		filepath.Join(root, "injected"),
	); !errors.Is(
		err,
		os.ErrNotExist,
	) {
		t.Fatalf("shell expansion: %v", err)
	}
	state, err := readDeployState(root)
	if err != nil || state[app][env].Backend != "colmena" {
		t.Errorf("deployment was not recorded: %v %v", state, err)
	}
	if err := os.WriteFile(script, []byte("#!/bin/sh\nexit 9\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	var failed *exec.ExitError
	if err := runDeploy(
		t.Context(),
		cfg,
		app,
		false,
	); !errors.As(err, &failed) ||
		failed.ExitCode() != 9 {
		t.Fatalf("backend failure was not returned: %v", err)
	}
}

func TestDeclaredDeployRejectsCommandText(t *testing.T) {
	script := "sh -c echo"
	if err := deployModuleBackend(
		t.Context(),
		t.TempDir(),
		DeployBackend{Script: &script},
		"api",
		"prod",
		nil,
		true,
	); err == nil {
		t.Fatal("accepted command text as an executable")
	}
}
