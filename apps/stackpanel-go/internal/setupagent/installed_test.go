package setupagent

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

// Exercise the installed provider with the missing outer brace seen in a real
// onboarding plan. One read-only request; no application setup or acceptance.
func TestInstalledCodexReplyCorrection(t *testing.T) {
	if os.Getenv("STACKPANEL_TEST_INSTALLED_AGENTS") != "1" {
		t.Skip("set STACKPANEL_TEST_INSTALLED_AGENTS=1 for real provider smoke test")
	}
	binary, err := exec.LookPath("codex")
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	if err := exec.Command("git", "init", root).Run(); err != nil {
		t.Fatal(err)
	}
	message := `{"status":"plan","plan":{"summary":"Create a TypeScript/Bun dashboard with PostgreSQL persistence and Redis caching","services":["postgres","redis"],"expectations":{"version":1,"config":[{"path":["enable"],"equals":true},{"path":["apps","web"],"exists":true}],"requiredChecks":[],"files":["package.json","src/server.ts","tests/server.test.ts"],"commands":[{"id":"test","scope":"build","dir":".","argv":["bun","test"]},{"id":"build","scope":"build","dir":".","argv":["bun","run","build"]}]}}}`
	var events []Event
	result, err := Run(context.Background(), Agent{ID: "codex", Path: binary}, RunRequest{
		Dir: root, ReadOnly: true, Prompt: ReplyCorrectionPrompt(Inspection, strings.TrimSuffix(message, "}"), "unexpected EOF"),
		Timeout: 90 * time.Second, OnEvent: func(e Event) { events = append(events, e) },
	})
	if err != nil {
		t.Fatal(err)
	}
	actual, err := ParseReply(result.Message)
	if err != nil {
		t.Fatalf("invalid correction: %v", err)
	}
	expected, err := ParseReply(message)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(actual, expected) {
		t.Fatalf("correction changed plan contents: %s", result.Message)
	}
	for _, e := range events {
		if e.Kind == "tool" {
			t.Fatalf("formatting used a tool: %+v", e)
		}
	}
}

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

// This opt-in regression makes one real model request. It intentionally denies
// an unapproved read of a harmless test reference, then verifies native file tools can
// finish repository edits without granting that read or exposing Bash.
func TestInstalledClaudeFileToolsAndDeniedRead(t *testing.T) {
	if os.Getenv("STACKPANEL_TEST_INSTALLED_AGENTS") != "1" {
		t.Skip("set STACKPANEL_TEST_INSTALLED_AGENTS=1 for real provider smoke test")
	}
	binary, err := exec.LookPath("claude")
	if err != nil {
		t.Fatal(err)
	}
	base := t.TempDir()
	root := filepath.Join(base, "repo")
	for _, dir := range []string{".claude", ".stack"} {
		if err := os.MkdirAll(filepath.Join(root, dir), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	reference := filepath.Join(base, "optional-reference.txt")
	if err := os.WriteFile(reference, []byte("Harmless test reference; leave unread.\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	settings, _ := json.Marshal(map[string]any{"permissions": map[string]any{"ask": []string{"Read(/" + reference + ")"}}})
	if err := os.WriteFile(filepath.Join(root, ".claude/settings.local.json"), settings, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ".stack/config.nix"), []byte("{ enable = false; }\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		".stack/config.nix":      "{ enable = true; }\n",
		"go.mod":                 "module example.test/onboarding\n\ngo 1.25\n",
		"cmd/hello/main.go":      "package main\nimport \"fmt\"\nfunc greeting() string { return \"Hello, world!\" }\nfunc main() { fmt.Println(greeting()) }\n",
		"cmd/hello/main_test.go": "package main\nimport \"testing\"\nfunc TestGreeting(t *testing.T) { if greeting() != \"Hello, world!\" { t.Fatal(greeting()) } }\n",
	}
	encoded, _ := json.Marshal(files)
	prompt := fmt.Sprintf(`This is a bounded test in an isolated temporary repository.
First call the Read tool exactly once on %q. This harmless fixture intentionally
requires permission and the read should be denied. Leave it unread; do not retry
or use another tool to read it. That optional read is not required for the edits.
Then use native file tools to write exactly the repository files in this JSON map,
reading the existing .stack/config.nix before editing it. Write creates parent
directories. Do not run any commands, modify permissions/settings, use integrations,
or read other paths. Return exactly {"status":"complete","summary":"Created fixture"}
after writing the files. The host will run build and test commands.
Your entire final response must be only that JSON object, with no explanation,
Markdown, commentary, or trailing text. Files: %s`, reference, encoded)
	var events []Event
	result, err := Run(context.Background(), Agent{ID: "claude", Path: binary}, RunRequest{
		Dir: root, Prompt: prompt, Timeout: 3 * time.Minute,
		OnEvent: func(e Event) { events = append(events, e) },
	})
	if err != nil {
		t.Fatalf("%v; reply: %.1000s", err, result.Message)
	}
	warned, edited, wrote := false, false, false
	for _, e := range events {
		warned = warned || e.Kind == "warning" && strings.Contains(e.Text, "Read")
		edited = edited || e.Kind == "tool" && e.Text == "Edit"
		wrote = wrote || e.Kind == "tool" && e.Text == "Write"
		if e.Kind == "tool" && e.Text == "Bash" {
			t.Fatal("Claude used a shell during repository edits")
		}
	}
	if !warned || !edited || !wrote {
		t.Fatalf("expected denied read and successful native edits: %+v", events)
	}
	for name, expected := range files {
		data, err := os.ReadFile(filepath.Join(root, name))
		if err != nil || string(data) != expected {
			t.Fatalf("file %s differs: %v", name, err)
		}
	}
	for _, args := range [][]string{{"test", "./..."}, {"build", "./..."}} {
		cmd := exec.Command("go", args...)
		cmd.Dir = root
		if output, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("host go %v: %v\n%s", args, err, output)
		}
	}
}
