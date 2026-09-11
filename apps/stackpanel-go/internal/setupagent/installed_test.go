package setupagent

import (
	"context"
	"os"
	"os/exec"
	"testing"
	"time"
)

// Explicit opt-in: this uses the installed CLI's credentials and makes two
// small model requests per provider, without repository writes or tool calls.
func TestInstalledAgentQuestionProtocol(t *testing.T) {
	if os.Getenv("STACKPANEL_TEST_INSTALLED_AGENTS") != "1" {
		t.Skip("set STACKPANEL_TEST_INSTALLED_AGENTS=1 for real provider smoke test")
	}
	for _, agent := range Discover() {
		if agent.ID != "codex" && agent.ID != "claude" {
			continue
		}
		t.Run(agent.ID, func(t *testing.T) {
			ctx := context.Background()
			if caps, err := Probe(ctx, agent); err != nil || !caps.ReadOnly {
				t.Fatalf("probe: %+v %v", caps, err)
			}
			root := t.TempDir()
			if err := exec.Command("git", "init", root).Run(); err != nil {
				t.Fatal(err)
			}
			for _, prompt := range []string{
				`This is a protocol smoke test. Do not use any tools. Return exactly {"status":"needs_input","questions":[{"id":"language","prompt":"Language?","kind":"single","options":["Go","TypeScript"],"required":true}]}`,
				`This is the next protocol round. The user answered language=Go. Do not use any tools. Return exactly {"status":"complete","summary":"Selected Go"}`,
			} {
				result, err := Run(ctx, agent, RunRequest{Dir: root, ReadOnly: true, Prompt: prompt, Timeout: 90 * time.Second})
				if err != nil {
					t.Fatal(err)
				}
				if _, err := ParseReply(result.Message); err != nil {
					t.Fatalf("reply: %s: %v", result.Message, err)
				}
			}
		})
	}
}
