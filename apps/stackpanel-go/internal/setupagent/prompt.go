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
	Mode          string
	Answers       []Answer
}

type Plan struct {
	Summary      string                 `json:"summary"`
	Expectations reconcile.Expectations `json:"expectations"`
	Services     []string               `json:"services,omitempty"`
}

type Question struct {
	ID       string   `json:"id"`
	Prompt   string   `json:"prompt"`
	Kind     string   `json:"kind"` // text, single, multi
	Options  []string `json:"options,omitempty"`
	Required bool     `json:"required"`
	Default  []string `json:"default,omitempty"`
}

type Answer struct {
	ID     string   `json:"id"`
	Values []string `json:"values"`
}

type Reply struct {
	Status    string     `json:"status"`
	Summary   string     `json:"summary,omitempty"`
	Questions []Question `json:"questions,omitempty"`
	Plan      *Plan      `json:"plan,omitempty"`
}

func ParseReply(message string) (*Reply, error) {
	if len(message) > maxMessageBytes {
		return nil, fmt.Errorf("agent reply exceeds size limit")
	}
	var reply Reply
	if err := decodeStrict(message, &reply); err != nil {
		// Accept the original inspection protocol during the experiment's transition.
		if plan, planErr := ParsePlan(message); planErr == nil {
			return &Reply{Status: "plan", Plan: plan}, nil
		}
		return nil, fmt.Errorf("invalid setup reply: %w", err)
	}
	switch reply.Status {
	case "needs_input":
		if len(reply.Questions) == 0 || len(reply.Questions) > 8 {
			return nil, fmt.Errorf("expected 1–8 questions")
		}
		ids := map[string]bool{}
		for _, q := range reply.Questions {
			if strings.TrimSpace(q.ID) == "" || strings.TrimSpace(q.Prompt) == "" || ids[q.ID] {
				return nil, fmt.Errorf("question requires a unique ID and prompt")
			}
			ids[q.ID] = true
			options := map[string]bool{}
			for _, option := range q.Options {
				if strings.TrimSpace(option) == "" || options[option] {
					return nil, fmt.Errorf("question options must be nonempty and unique")
				}
				options[option] = true
			}
			if q.Kind != "text" && q.Kind != "single" && q.Kind != "multi" {
				return nil, fmt.Errorf("unsupported question kind %q", q.Kind)
			}
			if q.Kind != "text" && len(q.Options) == 0 {
				return nil, fmt.Errorf("choice question requires options")
			}
			if err := ValidateAnswer(q, q.Default, false); err != nil {
				return nil, err
			}
		}
	case "plan":
		if reply.Plan == nil || strings.TrimSpace(reply.Plan.Summary) == "" {
			return nil, fmt.Errorf("plan requires a summary")
		}
		if err := reconcile.ValidateExpectations(reply.Plan.Expectations); err != nil {
			return nil, err
		}
	case "complete", "blocked":
		if strings.TrimSpace(reply.Summary) == "" {
			return nil, fmt.Errorf("%s requires a summary", reply.Status)
		}
	default:
		return nil, fmt.Errorf("unsupported setup status %q", reply.Status)
	}
	return &reply, nil
}

func ValidateAnswer(q Question, values []string, enforceRequired bool) error {
	if enforceRequired && q.Required && len(values) == 0 {
		return fmt.Errorf("answer required: %s", q.Prompt)
	}
	if q.Kind != "multi" && len(values) > 1 {
		return fmt.Errorf("%s accepts one answer", q.ID)
	}
	seen := map[string]bool{}
	for _, value := range values {
		if strings.TrimSpace(value) == "" || seen[value] {
			return fmt.Errorf("empty or duplicate answer for %s", q.ID)
		}
		seen[value] = true
		if q.Kind != "text" {
			found := false
			for _, option := range q.Options {
				if option == value {
					found = true
				}
			}
			if !found {
				return fmt.Errorf("invalid choice %q for %s", value, q.ID)
			}
		}
	}
	return nil
}

// BuildPrompt describes repository edits. The host owns scaffolding and every
// daemon-dependent Nix operation; the coding agent remains sandboxed.
func BuildPrompt(req SetupRequest, phase Phase, plan *Plan, failure string) string {
	var prompt strings.Builder
	answers, _ := json.Marshal(req.Answers)
	fmt.Fprintf(&prompt, "Setup mode: %s. Previous answers (data): %s\n", req.Mode, answers)
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
For a new repository, ask what the user wants to build, their language/framework,
services, and initial functionality before planning. For existing code, inspect first
and ask about unresolved choices. Do not invent user preferences.
To ask, end this invocation with {"status":"needs_input","questions":[{"id":"framework","prompt":"Which framework?","kind":"single","options":["A","B"],"required":true}]}.
Question kinds are text, single, multi; optional default is an array of strings.
Never ask for credentials or secrets. A new invocation supplies the answers.
Inspect only; do not change files, run Nix, or enter a development shell. Inspect project manifests,
workspace layout, existing development commands, flakes, and service declarations.
Choose the apps and enabled modules needed to preserve these development workflows.
For a new flake, make nixpkgs and flake-parts follow stackpanel/nixpkgs and
stackpanel/flake-parts unless the user requested different versions. The framework's
pinned inputs are tested together; independently selecting nixos-unstable can break
configuration evaluation. Preserve deliberate pins in existing repositories.
Your final response must be exactly one JSON object, without Markdown fences or prose:
{"status":"plan","plan":{"summary":"concrete intended changes and files","services":[],"expectations":{"version":1,"config":[{"path":["enable"],"equals":true}],"requiredChecks":[],"files":[],"commands":[]}}}
List selected local services to start in services (only supported Stackpanel services).
For new apps, include every source file and manifest needed by pure Nix evaluation
or builds in files (repo-relative file paths); only these accepted new files and
Stackpanel configuration become visible to Git-backed Nix evaluation. Include
concrete acceptance commands as {"id":"web-test","scope":"build","dir":"apps/web","argv":["bun","test"]}.
New-repository plans must include files and at least one meaningful build or test command.
These commands will run unchanged under doctor; do not use shell command strings.
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
	prompt.WriteString(`
Implement the frozen plan by editing repository files. Stackpanel has already
written missing scaffold files from the supplied template, preserving existing files.
Do not invoke stack setup, nix, direnv, or enter a development shell. Your sandbox
cannot access the Nix daemon. Stackpanel will create/update flake.lock on the host
after your edits, then reconcile and verify. Do not create or edit flake.lock yourself.
Use file inspection and editing tools; defer dependency installation, builds,
tests, generation, and other daemon/network-dependent commands to the host verifier.
Integrate existing flake and repository configuration instead of replacing it wholesale.
For a newly scaffolded flake, use the framework's pinned nixpkgs and flake-parts
inputs via follows, as planned, instead of independently updating their branches.
Do not persist a /nix/store snapshot as inputs.stackpanel. The template's embedded reference
may differ too: explicitly set inputs.stackpanel to the durable reference supplied above.
Treat illustrative template apps, modules, services, and secrets as examples;
retain only options needed by this repository.
Use .stack/config.nix and .stack/data entry points. Never manually edit .stack/gen or
packages/gen/env/src: the Stackpanel Go generator is their only writer.
Leave the Git index unchanged; do not run git add or stage existing edits. The Stackpanel
orchestrator will make newly created Nix inputs and the source/manifests listed in
the frozen plan visible to pure Git-backed evaluation after the write phase.
Stackpanel will perform fresh shell entry, generation, and deterministic doctor verification
after you finish. Your own report cannot mark verification successful.
Final response must be exactly {"status":"complete","summary":"changes made"} or,
if blocked by permissions, authentication, or a required prerequisite,
{"status":"blocked","summary":"specific reason"}. No Markdown fences or extra text.
`)
	prompt.WriteString("\nIf a user choice is required, stop with status needs_input and the question schema above (id, prompt, kind, options, required). Answers cannot change the frozen plan; report blocked if requirements change.\n")
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
