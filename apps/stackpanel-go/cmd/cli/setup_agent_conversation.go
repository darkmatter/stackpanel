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
			OnEvent: func(event setupagent.Event) { ui.Progress(string(phase) + ": " + event.Text) },
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

func renderSetupPlan(plan *setupagent.Plan) string {
	var s strings.Builder
	fmt.Fprintf(&s, "Onboarding plan\n\n%s\n", plan.Summary)
	for _, file := range plan.Expectations.Files {
		fmt.Fprintf(&s, "  File: %s\n", file)
	}
	for _, c := range plan.Expectations.Config {
		value, _ := json.Marshal(c)
		fmt.Fprintf(&s, "  Config: %s\n", value)
	}
	for _, c := range plan.Expectations.Commands {
		argv, _ := json.Marshal(c.Argv)
		fmt.Fprintf(&s, "  Verify %s in %s: %s\n", c.ID, c.Dir, argv)
	}
	for _, service := range plan.Services {
		fmt.Fprintf(&s, "  Start service: %s\n", service)
	}
	s.WriteString("\nThen verify with doctor and connect Studio.\n")
	return s.String()
}
