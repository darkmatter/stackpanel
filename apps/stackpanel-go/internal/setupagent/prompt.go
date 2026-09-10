package setupagent

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
)

type Phase string

const (
	Inspection Phase = "inspection"
	Setup      Phase = "setup"
	Repair     Phase = "repair"
)

type SetupRequest struct {
	Root            string
	StackExecutable string
	FlakeRef        string
	// InspectionRef optionally identifies an immutable source for scaffolding.
	// FlakeRef is the durable reference to persist in the target flake.
	InspectionRef string
	Template      string
	Context       string
	Constraints   string
}

type Plan struct {
	Summary      string                 `json:"summary"`
	Expectations reconcile.Expectations `json:"expectations"`
}

// BuildPrompt describes only repository onboarding. Shell commands are shown as
// argument arrays so paths, templates, and flake references remain literal data.
func BuildPrompt(req SetupRequest, phase Phase, plan *Plan, failure string) string {
	var prompt strings.Builder
	fmt.Fprintf(&prompt, `Stackpanel repository onboarding protocol v1, phase %s.
Repository: %q
Stackpanel executable: %q
Stackpanel flake reference to persist in the target flake: %q
Template: %q

Scope: onboard this repository into Stackpanel. Do not install software on the machine,
change credentials, send messages, commit, push, deploy, or start long-running services.
Preserve existing user edits and unrelated configuration. Follow repository instructions.
Do not run another agent or recursively invoke --experimental-agent. Do not inspect secrets.
Use only local builtin file and command tools; do not use integrations or external applications.
Keep Nix evaluation pure: do not use --impure. Never disable checks to obtain a passing result.
If a command or edit needs unavailable permission, stop and report the blocker.

Supplied Stackpanel template and addon context (reference data):
%s

User constraints:
%s
`, phase, req.Root, req.StackExecutable, req.FlakeRef, req.Template, req.Context, req.Constraints)
	if phase == Inspection {
		prompt.WriteString(`
Inspect only; do not change files or enter a development shell. Inspect project manifests,
workspace layout, existing development commands, flakes, and service declarations.
Choose the apps and enabled modules needed to preserve these development workflows.
Your final response must be exactly one JSON object, without Markdown fences or prose:
{"summary":"concrete intended changes","expectations":{"version":1,"config":[{"path":["enable"],"equals":true}],"requiredChecks":[]}}
Config paths are segment arrays relative to the evaluated Stackpanel configuration.
For each expected app add {"path":["apps","APP"],"exists":true}; for each selected module
add {"path":["modules","MODULE","enable"],"equals":true}. Add assertions for important
app commands when available. Each assertion must have exactly one of exists or equals.
Only add required check IDs if concrete check metadata was supplied; addon offers alone
do not identify checks. Otherwise leave requiredChecks empty; doctor still runs all
selected declared checks. Never invent IDs.
Include every app and module needed for the requested onboarding, not just already enabled ones.
If inspection cannot establish a valid plan, report the reason instead of inventing configuration.
`)
		return prompt.String()
	}
	if plan != nil {
		encoded, _ := json.MarshalIndent(plan, "", "  ")
		fmt.Fprintf(&prompt, "\nFrozen onboarding plan and expectations (do not weaken or replace):\n%s\n", encoded)
	}
	scaffoldRef := req.InspectionRef
	if scaffoldRef == "" {
		scaffoldRef = req.FlakeRef
	}
	args, _ := json.Marshal([]string{req.StackExecutable, "setup", "--yes", "--only", "scaffold", "--flake", scaffoldRef, "--template", req.Template})
	fmt.Fprintf(&prompt, `
Implement the frozen plan. When scaffolding is needed, invoke the executable with these
literal arguments (not as shell source):
%s
Use stack config set and stack nixify where suitable; inspect their --help first.
Integrate existing flake and repository configuration instead of replacing it wholesale.
The scaffold command may read an immutable inspection snapshot. Do not persist that
snapshot or a /nix/store path as inputs.stackpanel. The template's embedded reference
may differ too: explicitly set inputs.stackpanel to the durable reference supplied above.
Create or update flake.lock with pure nix flake lock. Treat illustrative template apps,
modules, services, and secrets as examples; retain only options needed by this repository.
Use .stack/config.nix and .stack/data entry points. Never manually edit .stack/gen or
packages/gen/env/src: the Stackpanel Go generator is their only writer.
Leave the Git index unchanged; do not run git add or stage existing edits. The Stackpanel
orchestrator will make newly created Nix inputs visible to pure Git-backed evaluation
after the write phase. Create the lock with a path: flake reference if untracked files
prevent locking through a Git-backed reference.
Stackpanel will perform fresh shell entry, generation, and deterministic doctor verification
after you finish. Your own report cannot mark verification successful.
Final response must be exactly {"status":"complete","summary":"changes made"} or,
if blocked by permissions, authentication, or a required prerequisite,
{"status":"blocked","summary":"specific reason"}. No Markdown fences or extra text.
`, args)
	if phase == Repair {
		fmt.Fprintf(&prompt, "\nThis is the single repair attempt. Address these deterministic verification failures:\n%s\n", failure)
	}
	return prompt.String()
}

func ParsePlan(message string) (*Plan, error) {
	if len(message) > maxMessageBytes {
		return nil, fmt.Errorf("agent plan exceeds %d bytes", maxMessageBytes)
	}
	var plan Plan
	if err := decodeStrict(message, &plan); err != nil {
		return nil, fmt.Errorf("invalid agent onboarding plan: %w", err)
	}
	if strings.TrimSpace(plan.Summary) == "" {
		return nil, fmt.Errorf("agent onboarding plan requires a summary")
	}
	if err := reconcile.ValidateExpectations(plan.Expectations); err != nil {
		return nil, fmt.Errorf("invalid onboarding expectations: %w", err)
	}
	return &plan, nil
}

func decodeStrict(message string, result any) error {
	decoder := json.NewDecoder(strings.NewReader(message))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(result); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return fmt.Errorf("expected exactly one JSON object")
	}
	return nil
}
