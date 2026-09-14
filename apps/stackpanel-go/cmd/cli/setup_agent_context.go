package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
)

type setupOptionSchema struct {
	FlakeRef string        `json:"flakeRef"`
	Options  []setupOption `json:"options"`
}

type setupOption struct {
	Name        string `json:"name"`
	Type        string `json:"type"`
	Description string `json:"description"`
}

// Load schema independently of the target project: its configuration may not
// evaluate yet. Enrich older manifests without replacing their template, pin,
// answers or accepted plan. Only agent phases need this context.
func ensureSetupOptionContext(ctx context.Context, request *setupagent.SetupRequest) error {
	var brief map[string]json.RawMessage
	if err := json.Unmarshal([]byte(request.Context), &brief); err != nil {
		return fmt.Errorf("read setup context: %w", err)
	}
	if brief == nil || request.InspectionRef == "" {
		return fmt.Errorf("setup context requires a pinned framework reference")
	}
	var schema setupOptionSchema
	if json.Unmarshal(brief["optionSchema"], &schema) == nil && schema.FlakeRef == request.InspectionRef && len(schema.Options) > 0 {
		return nil
	}
	arch := runtime.GOARCH
	switch arch {
	case "amd64":
		arch = "x86_64"
	case "arm64":
		arch = "aarch64"
	}
	// Preserve URI characters and disable Nix interpolation. JSON's HTML and
	// Unicode escapes are not Nix escapes (notably & in locked Git references).
	quote := func(value string) string {
		return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`, "\r", `\r`, "\t", `\t`, "${", `\${`).Replace(value) + `"`
	}
	expr := fmt.Sprintf(setupOptionSchemaExpr, quote(request.InspectionRef), quote(arch+"-"+runtime.GOOS))
	nctx, cancel := context.WithTimeout(ctx, setupStageTimeout)
	defer cancel()
	command := exec.CommandContext(nctx, "nix", "eval", "--json", "--no-update-lock-file", "--no-write-lock-file", "--expr", expr)
	command.Dir = request.Root
	command.Env = freshSetupEnvironment(os.Environ())
	var stderr bytes.Buffer
	command.Stderr = &stderr
	data, err := command.Output()
	if err != nil {
		return fmt.Errorf("load pinned Stackpanel option schema: %w\n%s", err, stderr.String())
	}
	schema = setupOptionSchema{FlakeRef: request.InspectionRef}
	if err := json.Unmarshal(data, &schema.Options); err != nil {
		return fmt.Errorf("read Stackpanel option schema: %w", err)
	}
	if len(schema.Options) == 0 {
		return fmt.Errorf("pinned Stackpanel option schema is empty")
	}
	brief["optionSchema"], err = json.Marshal(schema)
	if err != nil {
		return err
	}
	data, err = json.Marshal(brief)
	if err == nil {
		request.Context = string(data)
	}
	return err
}

// getOptions includes Nix-only tooling and extension submodules omitted by the
// proto schema and starter templates. Keep the context scoped to repository
// onboarding, without forcing option defaults, project evaluation or builds.
const setupOptionSchemaExpr = `
let
  flake = builtins.getFlake %s;
  pkgs = import flake.inputs.nixpkgs { system = %s; };
  inherit (pkgs) lib;
  options = flake.lib.getOptions { inherit pkgs; };
  roots = [ "enable" "name" "github" "project" "apps" "bun" "go"
    "modules" "devshell" "ide" "gitignore" "ports" "env" "envs"
    "cli" "direnv" "services" "process-compose" "caddy" "checks" "doctor" ];
  selected = o: !(o.internal or false) && !(o.readOnly or false)
    && builtins.elem (builtins.elemAt o.loc 1) roots;
in map (o: {
  name = lib.removePrefix "stackpanel." o.name;
  inherit (o) type description;
}) (builtins.filter selected (lib.optionAttrSetToDocList options))
`
