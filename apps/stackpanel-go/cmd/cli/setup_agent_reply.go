package cmd

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

type setupReplyRecovery struct {
	Agent   string           `json:"agent,omitempty"`
	Phase   setupagent.Phase `json:"phase"`
	Message string           `json:"message"`
	Problem string           `json:"problem"`
}

func runSetupAgentReply(ctx context.Context, agent setupagent.Agent, phase setupagent.Phase, request setupagent.RunRequest, state *setupManifest, ui *tui.SetupUI) (*setupagent.Reply, error) {
	originalRequest := request
	if state.PendingReply != nil && phase == setupagent.Inspection {
		switchedAgent := state.PendingReply.Agent != "" && state.PendingReply.Agent != agent.ID
		nonJSONProse := !strings.HasPrefix(strings.TrimSpace(state.PendingReply.Message), "{")
		if switchedAgent || nonJSONProse {
			state.PendingReply = nil
			if state.path != "" {
				if err := state.save(); err != nil {
					return nil, err
				}
			}
		}
	}
	hadSavedPending := state.PendingReply != nil
	if state.PendingReply == nil {
		result, err := setupagent.Run(ctx, agent, request)
		var formatErr *setupagent.ReplyFormatError
		if err != nil && !errors.As(err, &formatErr) {
			return nil, fmt.Errorf("%s %s: %w (check the backend's credentials and permissions; --agent-log records diagnostics)", agent.ID, phase, err)
		}
		reply, parseErr := setupagent.ParseReply(result.Message)
		if parseErr == nil {
			return reply, nil
		}
		if !errors.As(parseErr, &formatErr) {
			return nil, parseErr
		}
		state.PendingReply = &setupReplyRecovery{Agent: agent.ID, Phase: phase, Message: result.Message, Problem: parseErr.Error()}
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
	reply, err := setupagent.ParseReply(pending.Message)
	if err != nil {
		ui.Warning(fmt.Sprintf("%s returned malformed setup JSON. Requesting a corrected reply · retry 1 of 1. Your choices are saved.", agent.ID))
		request.ReadOnly = true
		request.Prompt = setupagent.ReplyCorrectionPrompt(phase, pending.Message, pending.Problem)
		result, err := setupagent.Run(ctx, agent, request)
		if err != nil {
			return nil, fmt.Errorf("%s reply correction failed; original reply saved for retry: %w", agent.ID, err)
		}
		reply, err = setupagent.ParseReply(result.Message)
		if err != nil {
			return nil, fmt.Errorf("%s returned an invalid reply after one formatting retry; original reply saved: %w", agent.ID, err)
		}
	}
	if reply.Status == "blocked" {
		state.PendingReply = nil
		if state.path != "" {
			if err := state.save(); err != nil {
				return nil, err
			}
		}
		if hadSavedPending && phase == setupagent.Inspection {
			ui.Progress(fmt.Sprintf("Previous inspection reply could not be recovered; running a fresh %s inspection…", agent.ID))
			return runSetupAgentReply(ctx, agent, phase, originalRequest, state, ui)
		}
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
