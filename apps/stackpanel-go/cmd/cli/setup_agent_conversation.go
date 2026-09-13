package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

func runAgentPhase(ctx context.Context, agent setupagent.Agent, request *setupagent.SetupRequest, phase setupagent.Phase, plan *setupagent.Plan, failure string, ui *tui.SetupUI, debug io.Writer) (*setupagent.Reply, error) {
	for round := 0; round < 8; round++ {
		result, err := setupagent.Run(ctx, agent, setupagent.RunRequest{
			Dir: request.Root, Env: freshSetupEnvironment(os.Environ()), ReadOnly: phase == setupagent.Inspection,
			Prompt: setupagent.BuildPrompt(*request, phase, plan, failure), Timeout: setupStageTimeout,
			Stdout: debug, Stderr: debug,
			OnEvent: func(event setupagent.Event) { ui.Activity(event.Text) },
		})
		if err != nil {
			return nil, fmt.Errorf("%s %s: %w (check the CLI's login and permissions; --agent-log records diagnostics)", agent.ID, phase, err)
		}
		reply, err := setupagent.ParseReply(result.Message)
		if err != nil {
			return nil, err
		}
		if reply.Status == "blocked" {
			return nil, fmt.Errorf("%s blocked: %s", agent.ID, reply.Summary)
		}
		if reply.Status != "needs_input" {
			if phase != setupagent.Inspection && reply.Status != "complete" {
				return nil, fmt.Errorf("%s must return complete", phase)
			}
			return reply, nil
		}
		for _, question := range reply.Questions {
			values, err := ui.Ask(question.Prompt, question.Kind, question.Options, question.Default, question.Required)
			if err != nil {
				return nil, err
			}
			if err := setupagent.ValidateAnswer(question, values, true); err != nil {
				return nil, err
			}
			request.Answers = append(request.Answers, setupagent.Answer{ID: question.ID, Values: values})
		}
	}
	return nil, fmt.Errorf("%s exceeded eight question rounds", phase)
}

func renderSetupPlan(plan *setupagent.Plan, opts setupFlags) string {
	var s strings.Builder
	fmt.Fprintf(&s, "%s\n", plan.Summary)
	if len(plan.Expectations.Files) > 0 {
		fmt.Fprintf(&s, "\nFiles · %d\n", len(plan.Expectations.Files))
		for _, file := range plan.Expectations.Files {
			fmt.Fprintf(&s, "  %s\n", file)
		}
	}
	if len(plan.Expectations.Config) > 0 {
		s.WriteString("\nConfiguration\n")
		for _, c := range plan.Expectations.Config {
			value, _ := json.Marshal(c.Equals)
			description := " = " + string(value)
			if len(c.Equals) == 0 && c.Exists != nil {
				if *c.Exists {
					description = " must exist"
				} else {
					description = " must be absent"
				}
			}
			fmt.Fprintf(&s, "  %s%s\n", strings.Join(c.Path, "."), description)
		}
	}
	if len(plan.Expectations.Commands) > 0 {
		s.WriteString("\nBuild & test\n")
		for _, c := range plan.Expectations.Commands {
			fmt.Fprintf(&s, "  %s · %s\n    %s\n", c.ID, c.Dir, setupCommandLabel(c.Argv))
		}
	}
	if len(plan.Services) > 0 {
		s.WriteString("\nServices\n")
		for _, service := range plan.Services {
			fmt.Fprintf(&s, "  %s\n", service)
		}
	}
	s.WriteString("\nVerification\n  Doctor checks the agreed repository setup.\n")
	for _, id := range plan.Expectations.RequiredChecks {
		fmt.Fprintf(&s, "  Required check: %s\n", id)
	}
	switch {
	case opts.noRuntime:
		s.WriteString("  Runtime and Studio checks are skipped (--no-runtime).\n")
	case opts.noBrowser:
		s.WriteString("  Start the local agent and verify runtime.\n  Studio check is skipped (--no-browser).\n")
	default:
		s.WriteString("  Start the local agent, connect Studio, and verify runtime.\n")
	}
	return s.String()
}

// Quote arguments containing whitespace so the review preserves argv boundaries.
func setupCommandLabel(argv []string) string {
	parts := make([]string, len(argv))
	for i, arg := range argv {
		if strings.ContainsAny(arg, " \t\n\"'\\") {
			quoted, _ := json.Marshal(arg)
			parts[i] = string(quoted)
		} else {
			parts[i] = arg
		}
	}
	return strings.Join(parts, " ")
}
