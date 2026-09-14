package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
)

func TestSetupOptionContextUpgradesSavedRequest(t *testing.T) {
	bin := t.TempDir()
	script := `#!/bin/sh
test -z "$STACKPANEL_ROOT" || exit 1
test "$1" = eval || exit 1
test "$2" = --json || exit 1
test "$3" = --no-update-lock-file || exit 1
test "$4" = --no-write-lock-file || exit 1
test "$5" = --expr || exit 1
case "$6" in
  *'builtins.getFlake "git+file:///framework?rev=pinned&dir=\${literal}"'*) ;;
  *) exit 1 ;;
esac
printf '%s\n' '[{"name":"apps.<name>.tooling.dev.package","type":"package","description":"Tool binary package"}]'
`
	path := filepath.Join(bin, "nix")
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STACKPANEL_ROOT", "/wrong-caller")
	request := setupagent.SetupRequest{
		Root: t.TempDir(), InspectionRef: "git+file:///framework?rev=pinned&dir=${literal}",
		FlakeRef: "git+file:///framework?rev=pinned&dir=${literal}", Template: "minimal", Mode: "new",
		Context:  `{"templateFiles":{".stack/config.nix":"original template"},"addons":[],"futureField":{"keep":true}}`,
		Answers:  []setupagent.Answer{{ID: "language", Values: []string{"Bun"}}},
		Resuming: true, PreviousError: "apps.web.dev does not exist",
	}
	before := request
	if err := ensureSetupOptionContext(context.Background(), &request); err != nil {
		t.Fatal(err)
	}
	var oldBrief, brief map[string]json.RawMessage
	_ = json.Unmarshal([]byte(before.Context), &oldBrief)
	_ = json.Unmarshal([]byte(request.Context), &brief)
	for key, value := range oldBrief {
		if string(brief[key]) != string(value) {
			t.Fatalf("lost saved context %s", key)
		}
	}
	var schema setupOptionSchema
	if err := json.Unmarshal(brief["optionSchema"], &schema); err != nil || schema.FlakeRef != request.InspectionRef || len(schema.Options) != 1 {
		t.Fatalf("missing pinned schema: %+v %v", schema, err)
	}
	before.Context = request.Context
	if !reflect.DeepEqual(before, request) {
		t.Fatal("schema upgrade changed the saved request")
	}
	// A valid cache must not depend on Nix still being available.
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)
	if err := ensureSetupOptionContext(context.Background(), &request); err != nil {
		t.Fatalf("cached schema was re-evaluated: %v", err)
	}
	request.InspectionRef = "github:fixture/framework/different-pin"
	before = request
	if err := ensureSetupOptionContext(context.Background(), &request); err == nil {
		t.Fatal("reused schema from a different framework pin")
	}
	if !reflect.DeepEqual(before, request) {
		t.Fatal("failed schema load damaged saved request")
	}
}

// One bounded real provider repair, then pure Nix evaluation of its edit. The
// invalid option mirrors the reported failure; no user's repository is changed.
func TestInstalledSetupSchemaRepair(t *testing.T) {
	ref := os.Getenv("STACKPANEL_TEST_FRAMEWORK")
	if os.Getenv("STACKPANEL_TEST_INSTALLED_AGENTS") != "1" || ref == "" {
		t.Skip("set STACKPANEL_TEST_INSTALLED_AGENTS=1 and STACKPANEL_TEST_FRAMEWORK for real repair test")
	}
	binary, err := exec.LookPath("codex")
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	request := setupagent.SetupRequest{Root: root, InspectionRef: ref, FlakeRef: ref, Context: `{}`, Mode: "existing", Resuming: true}
	if err := ensureSetupOptionContext(context.Background(), &request); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(root, ".stack"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeSetupGitFile(t, root, ".stack/config.nix", `{ ... }: {
  enable = true;
  name = "schema-repair-test";
  apps.web = { path = "."; type = "bun"; dev.command = "bun --hot src/server.ts"; };
}`)
	refJSON, _ := json.Marshal(ref)
	// The test flake evaluates modules without an application build or devshell.
	flake := fmt.Sprintf(`{
  inputs.stackpanel.url = %s;
  outputs = { self, stackpanel }: let
    pkgs = import stackpanel.inputs.nixpkgs { system = "x86_64-linux"; };
    evaluated = pkgs.lib.evalModules { modules = [
      (stackpanel.outPath + "/nix/stackpanel")
      { _module.args = { inherit pkgs; inputs = {}; };
        stackpanel = import ./.stack/config.nix { inherit pkgs; }; }
    ]; };
    app = evaluated.config.stackpanel.apps.web;
  in { repaired = app.path == "." && app.type == "bun" && (
    if app.tooling.dev != null then
      app.tooling.dev.package.pname == "bun" && app.tooling.dev.args == [ "--hot" "src/server.ts" ]
    else app.commands.dev.command == "bun --hot src/server.ts"
  ); };
}`, strings.ReplaceAll(string(refJSON), "${", `\${`))
	writeSetupGitFile(t, root, "flake.nix", flake)
	run := func(args ...string) []byte {
		t.Helper()
		command := exec.CommandContext(context.Background(), args[0], args[1:]...)
		command.Dir, command.Env = root, freshSetupEnvironment(os.Environ())
		output, err := command.CombinedOutput()
		if err != nil {
			t.Fatalf("%s failed: %v\n%s", args[0], err, output)
		}
		return output
	}
	run("git", "init")
	run("git", "add", "flake.nix", ".stack/config.nix")
	run("nix", "flake", "lock")
	broken := exec.Command("nix", "eval", "--json", "--no-update-lock-file", "--no-write-lock-file", ".#repaired")
	broken.Dir, broken.Env = root, freshSetupEnvironment(os.Environ())
	if output, err := broken.CombinedOutput(); err == nil || !strings.Contains(string(output), "stackpanel.apps.web.dev") {
		t.Fatalf("fixture must reproduce the unknown-option error before invoking Codex: %s %v", output, err)
	}
	exists := true
	plan := &setupagent.Plan{Summary: "Repair only .stack/config.nix using the supplied option schema. Keep web at path . with type bun and development command bun --hot src/server.ts. Do not edit flake.nix or create other files.", Expectations: reconcile.Expectations{Version: 1, Config: []reconcile.ConfigAssertion{{Path: []string{"apps", "web"}, Exists: &exists}}}}
	_, err = setupagent.Run(context.Background(), setupagent.Agent{ID: "codex", Path: binary}, setupagent.RunRequest{
		Dir: root, Prompt: setupagent.BuildPrompt(request, setupagent.Repair, plan, "The option stackpanel.apps.web.dev does not exist."),
		Timeout: 2 * time.Minute, Env: freshSetupEnvironment(os.Environ()),
	})
	if err != nil {
		t.Fatal(err)
	}
	if got, err := os.ReadFile(filepath.Join(root, "flake.nix")); err != nil || string(got) != flake {
		t.Fatal("agent changed the verifier flake")
	}
	// Keep stdout separate from Nix's dirty-tree warnings.
	command := exec.Command("nix", "eval", "--json", "--no-update-lock-file", "--no-write-lock-file", ".#repaired")
	command.Dir, command.Env = root, freshSetupEnvironment(os.Environ())
	var stderr strings.Builder
	command.Stderr = &stderr
	output, err := command.Output()
	if err != nil || strings.TrimSpace(string(output)) != "true" {
		t.Fatalf("repaired config did not evaluate to the accepted command: %s %v\n%s", output, err, stderr.String())
	}
}

func TestSetupOptionContextFromPinnedFramework(t *testing.T) {
	ref := os.Getenv("STACKPANEL_TEST_FRAMEWORK")
	if ref == "" {
		t.Skip("set STACKPANEL_TEST_FRAMEWORK to test real pure Nix introspection")
	}
	request := setupagent.SetupRequest{Root: t.TempDir(), InspectionRef: ref, Context: `{}`}
	if err := ensureSetupOptionContext(context.Background(), &request); err != nil {
		t.Fatal(err)
	}
	var brief struct {
		Schema setupOptionSchema `json:"optionSchema"`
	}
	if err := json.Unmarshal([]byte(request.Context), &brief); err != nil {
		t.Fatal(err)
	}
	options := map[string]string{}
	for _, option := range brief.Schema.Options {
		options[option.Name] = option.Type
	}
	for _, name := range []string{"apps.<name>.path", "apps.<name>.type", "apps.<name>.tooling.dev.package", "apps.<name>.tooling.dev.args", "apps.<name>.commands.dev.command", "modules.<name>.enable", "ide.vscode.enable", "ide.zed.enable"} {
		if options[name] == "" {
			t.Errorf("missing supported option %s", name)
		}
	}
	if options["apps.<name>.dev.command"] != "" {
		t.Error("invented app command option")
	}
	prompt := setupagent.BuildPrompt(request, setupagent.Repair, nil, "apps.web.dev does not exist")
	if !strings.Contains(prompt, ".tooling.dev.package") {
		t.Error("repair did not receive schema")
	}
	t.Logf("supplied %d options (%d bytes) from %s", len(options), len(request.Context), ref)
}
