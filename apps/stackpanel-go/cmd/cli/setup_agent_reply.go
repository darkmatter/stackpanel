package cmd

import (
	"context"
	"errors"
	"fmt"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

type setupReplyRecovery struct {
	Phase   setupagent.Phase `json:"phase"`
	Message string           `json:"message"`
	Problem string           `json:"problem"`
}

func runSetupAgentReply(ctx context.Context, agent setupagent.Agent, phase setupagent.Phase, request setupagent.RunRequest, state *setupManifest, ui *tui.SetupUI) (*setupagent.Reply, error) {
	if state.PendingReply == nil {
		result, err := setupagent.Run(ctx, agent, request)
		var formatErr *setupagent.ReplyFormatError
		if err != nil && !errors.As(err, &formatErr) {
			return nil, fmt.Errorf("%s %s: %w (check the CLI's login and permissions; --agent-log records diagnostics)", agent.ID, phase, err)
		}
		reply, parseErr := setupagent.ParseReply(result.Message)
		if parseErr == nil {
			return reply, nil
		}
		if !errors.As(parseErr, &formatErr) {
			return nil, parseErr
		}
		state.PendingReply = &setupReplyRecovery{Phase: phase, Message: result.Message, Problem: parseErr.Error()}
		if state.path != "" {
			if err := state.save(); err != nil {
				return nil, err
			}
		}
	}
	pending := state.PendingReply
	if pending.Phase != phase {
		return nil, fmt.Errorf("saved reply belongs to %s, not %s; use --restart to review a new plan", pending.Phase, phase)
	}
	ui.Warning(fmt.Sprintf("%s returned malformed setup JSON. Requesting a corrected reply · retry 1 of 1. Your choices are saved.", agent.ID))
	request.ReadOnly = true
	request.Prompt = setupagent.ReplyCorrectionPrompt(phase, pending.Message, pending.Problem)
	result, err := setupagent.Run(ctx, agent, request)
	if err != nil {
		return nil, fmt.Errorf("%s reply correction failed; original reply saved for retry: %w", agent.ID, err)
	}
	reply, err := setupagent.ParseReply(result.Message)
	if err != nil {
		return nil, fmt.Errorf("%s returned an invalid reply after one formatting retry; original reply saved: %w", agent.ID, err)
	}
	if reply.Status == "blocked" {
		return nil, fmt.Errorf("%s could not recover its reply: %s", agent.ID, reply.Summary)
	}
	if (phase == setupagent.Inspection && reply.Status != "plan" && reply.Status != "needs_input") ||
		(phase != setupagent.Inspection && reply.Status != "complete" && reply.Status != "needs_input") {
		return nil, fmt.Errorf("%s reply correction returned unexpected status %q for %s", agent.ID, reply.Status, phase)
	}
	state.PendingReply = nil
	if state.path != "" {
		if err := state.save(); err != nil {
			return nil, err
		}
	}
	return reply, nil
}
