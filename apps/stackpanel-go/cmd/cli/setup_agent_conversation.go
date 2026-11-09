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

const maxQuestionRounds = 8

// runAgentPhase runs agent turns for phase, putting each round of questions
// to the user, until the agent gives its final reply. An inspection reply is
// always a plan, and the user reviews it; a reply that is not JSON becomes the
// plan's summary. A write phase's reply matters less than its edits, which
// doctor checks next.
func runAgentPhase(ctx context.Context, agent setupagent.Agent, request *setupagent.SetupRequest, phase setupagent.Phase, plan *setupagent.Plan, failure string, ui *tui.SetupUI, debug io.Writer, state *setupManifest) (*setupagent.Reply, error) {
	if state == nil {
		state = &setupManifest{}
	}
	if agent.ID == "pi" && state.Pi == nil {
		state.Pi = &setupagent.PiState{}
	}
	for round := 0; round < maxQuestionRounds; round++ {
		if err := answerSetupQuestions(state, request, ui); err != nil {
			return nil, err
		}
		request.Conversation = state.Conversation
		result, err := setupagent.Run(ctx, agent, setupagent.RunRequest{
			Dir: request.Root, Env: freshSetupEnvironment(os.Environ()), ReadOnly: phase == setupagent.Inspection,
			Prompt: setupagent.BuildPrompt(*request, phase, plan, failure), Timeout: setupStageTimeout,
			Stdout: debug, Stderr: debug,
			PiState: state.Pi, SavePiState: state.persist,
			OnEvent: func(event setupagent.Event) {
				if event.Kind == "warning" {
					ui.Warning(event.Text)
				} else {
					ui.Activity(event.Text)
				}
			},
		})
		if err != nil {
			return nil, fmt.Errorf("%s %s turn failed: %w (check that %s is signed in; --agent-log records its output)", agent.ID, phase, err, agent.ID)
		}
		message := strings.TrimSpace(result.Message)
		reply, err := setupagent.ParseReply(message)
		if err != nil {
			reply = &setupagent.Reply{Status: setupagent.StatusComplete, Summary: message}
		}
		if reply.Status == setupagent.StatusNeedsInput {
			state.Pending = reply.Questions
			if err := state.persist(); err != nil {
				return nil, err
			}
			continue
		}
		if reply.Status == setupagent.StatusBlocked {
			ui.Warning(fmt.Sprintf("%s did not finish: %s", agent.ID, reply.Summary))
		}
		if phase == setupagent.Inspection && reply.Plan == nil {
			reply = &setupagent.Reply{Status: setupagent.StatusPlan, Plan: &setupagent.Plan{Summary: reply.Summary}}
			setupagent.NormalizePlan(reply.Plan)
		}
		if reply.Plan != nil && reply.Plan.Summary == "" {
			reply.Plan.Summary = "Set up Stackpanel for this repository."
		}
		return reply, nil
	}
	return nil, fmt.Errorf("%s asked more than %d rounds of questions", agent.ID, maxQuestionRounds)
}

func answerSetupQuestions(state *setupManifest, request *setupagent.SetupRequest, ui *tui.SetupUI) error {
	for len(state.Pending) > 0 {
		question := state.Pending[0]
		answered := false
		for _, answer := range request.Answers {
			if answer.ID == question.ID {
				answered = true
				break
			}
		}
		if !answered {
			// Without a person to ask, a question with no default gets an empty
			// answer, which leaves the choice to the agent.
			values, err := ui.Ask(question.Prompt, question.Kind, question.Options, question.Default, question.Required && ui.Interactive())
			if err != nil {
				return err
			}
			answer := setupagent.Answer{ID: question.ID, Values: values}
			request.Answers = append(request.Answers, answer)
			state.Conversation = append(state.Conversation, setupagent.Exchange{Question: question, Answer: answer})
		}
		state.Pending = state.Pending[1:]
		if err := state.persist(); err != nil {
			return err
		}
	}
	return nil
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
	if len(plan.Prepare) > 0 {
		s.WriteString("\nHost preparation · runs on this machine before doctor\n")
		for _, c := range plan.Prepare {
			fmt.Fprintf(&s, "  %s · %s\n    %s\n", c.ID, c.Dir, setupCommandLabel(c.Argv))
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
