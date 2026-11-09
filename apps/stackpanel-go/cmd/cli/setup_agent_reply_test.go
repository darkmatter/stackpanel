package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

func setupReplyFixture(t *testing.T) (setupagent.Agent, string) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "codex")
	script := `#!/bin/sh
base=$(dirname "$0")
input=$(cat)
case "$input" in
  *'formatting retry only'*)
    printf '%s\n' "$*" >> "$base/correction-calls"
    printf '%s' "$input" > "$base/correction-prompt"
    cat "$base/correction-events" ;;
  *)
    printf '%s\n' "$*" >> "$base/original-calls"
    cat "$base/original-events" ;;
esac
`
	if err := os.WriteFile(path, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	return setupagent.Agent{ID: "codex", Path: path}, dir
}

func writeSetupReplyEvents(t *testing.T, dir, name, message string) {
	t.Helper()
	text, _ := json.Marshal(message)
	events := `{"type":"item.completed","item":{"type":"agent_message","text":` + string(text) + "}}\n{\"type\":\"turn.completed\"}\n"
	if err := os.WriteFile(filepath.Join(dir, name+"-events"), []byte(events), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestSetupReplyCorrectionResumesWithoutRepeatingWork(t *testing.T) {
	for _, phase := range []setupagent.Phase{setupagent.Inspection, setupagent.Setup, setupagent.Repair} {
		t.Run(string(phase), func(t *testing.T) {
			setupStateTestEnvironment(t)
			agent, fixture := setupReplyFixture(t)
			root := t.TempDir()
			message := `{"status":"complete","summary":"Created agreed files"}`
			if phase == setupagent.Inspection {
				message = `{"status":"plan","plan":{"summary":"Create app","expectations":{"version":1,"files":["src/main.ts"],"config":[{"path":["enable"],"equals":true}],"commands":[{"id":"build","scope":"build","dir":".","argv":["bun","run","build"]}]}}}`
			}
			// Missing content still requires a model correction. A missing final
			// outer brace alone is recovered without another invocation.
			malformed := strings.TrimSuffix(message, "}")
			if phase == setupagent.Inspection {
				malformed = strings.TrimSuffix(malformed, "}")
			} else {
				malformed = strings.TrimSuffix(malformed, `"`)
			}
			writeSetupReplyEvents(t, fixture, "original", malformed)
			writeSetupReplyEvents(t, fixture, "correction", malformed)
			state := &setupManifest{Version: 1, Root: root, Stage: "apply", path: setupStatePath(root),
				Plan:    &setupagent.Plan{Expectations: reconcile.Expectations{Version: 1, RequiredChecks: []string{"keep-check"}}},
				Request: setupagent.SetupRequest{Root: root, Answers: []setupagent.Answer{{ID: "framework", Values: []string{"Bun"}}}},
			}
			var output bytes.Buffer
			ui := tui.NewSetupUI(context.Background(), false, &output)
			defer ui.Close()
			request := setupagent.RunRequest{Dir: root, ReadOnly: phase == setupagent.Inspection, Prompt: "Original onboarding invocation"}
			_, err := runSetupAgentReply(context.Background(), agent, phase, request, state, ui)
			if err == nil || !strings.Contains(err.Error(), "after one formatting retry") {
				t.Fatalf("unbounded/accepted bad reply: %v", err)
			}
			saved, err := loadSetupManifest(root)
			if err != nil {
				t.Fatal(err)
			}
			if saved.PendingReply == nil || saved.PendingReply.Message != malformed || len(saved.Request.Answers) != 1 {
				t.Fatalf("lost recovery state: %+v", saved)
			}
			writeSetupReplyEvents(t, fixture, "correction", message)
			reply, err := runSetupAgentReply(context.Background(), agent, phase, request, saved, ui)
			if err != nil || reply == nil {
				t.Fatalf("resume reply: %+v %v", reply, err)
			}
			completed, err := loadSetupManifest(root)
			if err != nil || completed.PendingReply != nil {
				t.Fatalf("recovery state not cleared: %+v %v", completed, err)
			}
			originalCalls, _ := os.ReadFile(filepath.Join(fixture, "original-calls"))
			if bytes.Count(originalCalls, []byte("\n")) != 1 {
				t.Fatalf("repeated original work: %s", originalCalls)
			}
			corrections, _ := os.ReadFile(filepath.Join(fixture, "correction-calls"))
			if bytes.Count(corrections, []byte("--sandbox read-only")) != 2 || bytes.Contains(corrections, []byte("workspace-write")) {
				t.Fatalf("correction can write files: %s", corrections)
			}
			prompt, _ := os.ReadFile(filepath.Join(fixture, "correction-prompt"))
			if !bytes.Contains(prompt, []byte("Do not use tools")) || !bytes.Contains(prompt, []byte("do not invent missing content")) {
				t.Fatal("correction prompt lost scope")
			}
		})
	}
}

func TestSetupReplyDoesNotRetryProviderFailure(t *testing.T) {
	agent, fixture := setupReplyFixture(t)
	if err := os.WriteFile(filepath.Join(fixture, "original-events"), []byte("{\"type\":\"turn.failed\",\"error\":{\"message\":\"permission denied\"}}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	ui := tui.NewSetupUI(context.Background(), false, &output)
	defer ui.Close()
	state := &setupManifest{}
	_, err := runSetupAgentReply(context.Background(), agent, setupagent.Setup, setupagent.RunRequest{Dir: t.TempDir()}, state, ui)
	if err == nil || !strings.Contains(err.Error(), "permission denied") {
		t.Fatalf("lost provider error: %v", err)
	}
	if state.PendingReply != nil {
		t.Fatal("provider failure became formatting recovery")
	}
	if _, err := os.Stat(filepath.Join(fixture, "correction-calls")); !os.IsNotExist(err) {
		t.Fatal("retried provider permission error")
	}
}

func TestSetupReplyCorrectionCannotReplaceAcceptedPlan(t *testing.T) {
	agent, fixture := setupReplyFixture(t)
	writeSetupReplyEvents(t, fixture, "original", `{"status":"complete","summary":"Done`)
	writeSetupReplyEvents(t, fixture, "correction", `{"status":"plan","plan":{"summary":"Weaken checks","expectations":{"version":1,"config":[{"path":["enable"],"equals":true}]}}}`)
	var output bytes.Buffer
	ui := tui.NewSetupUI(context.Background(), false, &output)
	defer ui.Close()
	state := &setupManifest{}
	_, err := runSetupAgentReply(context.Background(), agent, setupagent.Setup, setupagent.RunRequest{Dir: t.TempDir()}, state, ui)
	if err == nil || !strings.Contains(err.Error(), "unexpected status") || state.PendingReply == nil {
		t.Fatalf("accepted replacement plan: %v", err)
	}
}

func TestSetupReplyMissingFinalOuterBraceDoesNotRetry(t *testing.T) {
	for _, phase := range []setupagent.Phase{setupagent.Inspection, setupagent.Setup} {
		t.Run(string(phase), func(t *testing.T) {
			agent, fixture := setupReplyFixture(t)
			message := `{"status":"complete","summary":"Created agreed files"}`
			if phase == setupagent.Inspection {
				message = `{"status":"plan","plan":{"summary":"Configure app","expectations":{"version":1,"config":[{"path":["enable"],"equals":true}]}}}`
			}
			writeSetupReplyEvents(t, fixture, "original", strings.TrimSuffix(message, "}"))
			var output bytes.Buffer
			ui := tui.NewSetupUI(context.Background(), false, &output)
			defer ui.Close()
			state := &setupManifest{}
			reply, err := runSetupAgentReply(context.Background(), agent, phase, setupagent.RunRequest{
				Dir: t.TempDir(), ReadOnly: phase == setupagent.Inspection,
			}, state, ui)
			if err != nil || reply == nil || state.PendingReply != nil {
				t.Fatalf("recover reply: %+v, state %+v, error %v", reply, state.PendingReply, err)
			}
			if strings.Contains(output.String(), "malformed") {
				t.Fatal("recoverable reply displayed a malformed JSON warning")
			}
			if _, err := os.Stat(filepath.Join(fixture, "correction-calls")); !os.IsNotExist(err) {
				t.Fatalf("recoverable reply invoked correction: %v", err)
			}
		})
	}
}

func TestSetupSavedReplyMissingFinalOuterBraceDoesNotRetry(t *testing.T) {
	for _, phase := range []setupagent.Phase{setupagent.Inspection, setupagent.Setup, setupagent.Repair} {
		t.Run(string(phase), func(t *testing.T) {
			setupStateTestEnvironment(t)
			agent, fixture := setupReplyFixture(t)
			root := t.TempDir()
			message := `{"status":"complete","summary":"Created agreed files"}`
			if phase == setupagent.Inspection {
				message = `{"status":"plan","plan":{"summary":"Configure app","expectations":{"version":1,"config":[{"path":["enable"],"equals":true}]}}}`
			}
			state := &setupManifest{Version: 1, Root: root, Stage: "apply", path: setupStatePath(root),
				Plan:         &setupagent.Plan{Expectations: reconcile.Expectations{Version: 1, RequiredChecks: []string{"keep-check"}}},
				Request:      setupagent.SetupRequest{Root: root, Answers: []setupagent.Answer{{ID: "framework", Values: []string{"Bun"}}}},
				PendingReply: &setupReplyRecovery{Phase: phase, Message: strings.TrimSuffix(message, "}"), Problem: "invalid setup reply: unexpected EOF"},
			}
			if err := state.save(); err != nil {
				t.Fatal(err)
			}
			loaded, err := loadSetupManifest(root)
			if err != nil {
				t.Fatal(err)
			}
			var output bytes.Buffer
			ui := tui.NewSetupUI(context.Background(), false, &output)
			defer ui.Close()
			reply, err := runSetupAgentReply(context.Background(), agent, phase, setupagent.RunRequest{
				Dir: root, ReadOnly: phase == setupagent.Inspection,
			}, loaded, ui)
			if err != nil || reply == nil {
				t.Fatalf("recover saved reply: %+v, error %v", reply, err)
			}
			saved, err := loadSetupManifest(root)
			if err != nil || saved.PendingReply != nil || len(saved.Request.Answers) != 1 ||
				saved.Plan == nil || len(saved.Plan.Expectations.RequiredChecks) != 1 || saved.Plan.Expectations.RequiredChecks[0] != "keep-check" {
				t.Fatalf("lost saved state: %+v, error %v", saved, err)
			}
			if strings.Contains(output.String(), "malformed") {
				t.Fatal("recoverable saved reply displayed a malformed JSON warning")
			}
			for _, name := range []string{"original-calls", "correction-calls"} {
				if _, err := os.Stat(filepath.Join(fixture, name)); !os.IsNotExist(err) {
					t.Fatalf("recoverable saved reply invoked %s: %v", name, err)
				}
			}
		})
	}
}

func TestSetupSavedReplyCannotReplaceAcceptedPlan(t *testing.T) {
	agent, _ := setupReplyFixture(t)
	var output bytes.Buffer
	ui := tui.NewSetupUI(context.Background(), false, &output)
	defer ui.Close()
	state := &setupManifest{PendingReply: &setupReplyRecovery{
		Phase:   setupagent.Setup,
		Message: `{"status":"plan","plan":{"summary":"Weaken checks","expectations":{"version":1,"config":[{"path":["enable"],"equals":true}]}}`,
	}}
	_, err := runSetupAgentReply(context.Background(), agent, setupagent.Setup, setupagent.RunRequest{Dir: t.TempDir()}, state, ui)
	if err == nil || !strings.Contains(err.Error(), "unexpected status") || state.PendingReply == nil {
		t.Fatalf("accepted replacement plan from saved reply: %v", err)
	}
}

func TestSetupSavedBlockedInspectionReplyFallsBackToFreshInspection(t *testing.T) {
	setupStateTestEnvironment(t)
	agent, fixture := setupReplyFixture(t)
	root := t.TempDir()
	planMsg := `{"status":"plan","plan":{"summary":"Configure Rust app","expectations":{"version":1,"config":[{"path":["enable"],"equals":true}]}}}`
	writeSetupReplyEvents(t, fixture, "original", planMsg)
	writeSetupReplyEvents(t, fixture, "correction", `{"status":"blocked","summary":"Inspection is incomplete: zsh attempted to create a temporary file on the read-only filesystem"}`)

	// Case 1: Saved non-JSON prose from a failed earlier run is discarded immediately in inspection.
	state := &setupManifest{
		Version: 1,
		Root:    root,
		Stage:   "inspection",
		path:    setupStatePath(root),
		PendingReply: &setupReplyRecovery{
			Phase:   setupagent.Inspection,
			Message: "Inspection is incomplete: zsh attempted to create a temporary file on the read-only filesystem.",
			Problem: "invalid setup reply: invalid character 'I' looking for beginning of value",
		},
	}
	if err := state.save(); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	ui := tui.NewSetupUI(context.Background(), false, &output)
	defer ui.Close()
	reply, err := runSetupAgentReply(context.Background(), agent, setupagent.Inspection, setupagent.RunRequest{
		Dir: root, ReadOnly: true,
	}, state, ui)
	if err != nil || reply == nil || reply.Status != "plan" {
		t.Fatalf("expected fresh inspection plan, got reply=%+v err=%v", reply, err)
	}
	if state.PendingReply != nil {
		t.Fatalf("expected PendingReply to be cleared, got %+v", state.PendingReply)
	}

	// Case 2: Saved truncated JSON whose correction returns status="blocked" in inspection
	// clears PendingReply and runs a fresh inspection instead of trapping the manifest.
	state.PendingReply = &setupReplyRecovery{
		Agent:   agent.ID,
		Phase:   setupagent.Inspection,
		Message: `{"status":"plan","plan":`,
		Problem: "invalid setup reply: unexpected EOF",
	}
	reply, err = runSetupAgentReply(context.Background(), agent, setupagent.Inspection, setupagent.RunRequest{
		Dir: root, ReadOnly: true,
	}, state, ui)
	if err != nil || reply == nil || reply.Status != "plan" {
		t.Fatalf("expected fallback to fresh inspection after blocked recovery, got reply=%+v err=%v", reply, err)
	}
	if state.PendingReply != nil {
		t.Fatalf("expected PendingReply to be cleared after blocked recovery, got %+v", state.PendingReply)
	}
}
