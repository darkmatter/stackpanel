package setupagent

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

const (
	validPlan = `{"summary":"Add web app","expectations":{"version":1,"config":[{"path":["apps","web"],"exists":true}],"requiredChecks":[]}}`
	complete  = `{"status":"complete","summary":"Configured web"}`
)

// TestAgentProcess is an installed CLI stand-in. It never contacts a provider.
func TestAgentProcess(t *testing.T) {
	if os.Getenv("STACKPANEL_TEST_AGENT_PROCESS") != "1" {
		return
	}
	if os.Getenv("STACKPANEL_TEST_AGENT_DELAY") == "1" {
		time.Sleep(10 * time.Second)
	}
	var args []string
	for i, arg := range os.Args {
		if arg == "--" {
			args = os.Args[i+1:]
			break
		}
	}
	if len(args) == 1 && args[0] == "--version" {
		_, _ = io.WriteString(os.Stdout, "fixture-cli 1.0.0\n")
		if os.Getenv("STACKPANEL_TEST_AGENT_FAIL") == "1" {
			os.Exit(7)
		}
		os.Exit(0)
	}
	input, _ := io.ReadAll(os.Stdin)
	if path := os.Getenv("STACKPANEL_TEST_AGENT_RECORD"); path != "" {
		data, _ := json.Marshal(struct {
			Args  []string
			Input string
			Dir   string
		}{args, string(input), mustWorkingDir()})
		_ = os.WriteFile(path, data, 0o600)
	}
	if path := os.Getenv("STACKPANEL_TEST_AGENT_CHILD"); path != "" {
		child := exec.Command("/bin/sh", "-c", `sleep 1; printf survived > "$STACKPANEL_TEST_AGENT_CHILD"`)
		child.Stdout, child.Stderr = os.Stdout, os.Stderr
		_ = child.Start()
		time.Sleep(10 * time.Second)
	}
	if os.Getenv("STACKPANEL_TEST_AGENT_LARGE") == "1" {
		_, _ = io.WriteString(os.Stdout, strings.Repeat("x", maxMessageBytes+1))
	}
	_, _ = io.WriteString(os.Stderr, os.Getenv("STACKPANEL_TEST_AGENT_STDERR"))
	_, _ = io.WriteString(os.Stdout, os.Getenv("STACKPANEL_TEST_AGENT_EVENTS"))
	if os.Getenv("STACKPANEL_TEST_AGENT_FAIL") == "1" {
		os.Exit(7)
	}
	os.Exit(0)
}

func mustWorkingDir() string {
	dir, _ := os.Getwd()
	return dir
}

func fakeAgent(t *testing.T, id string) Agent {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("fake CLI uses a Unix executable script")
	}
	path := filepath.Join(t.TempDir(), id)
	script := "#!/bin/sh\nexec " + shellQuote(os.Args[0]) + " -test.run=^TestAgentProcess$ -- \"$@\"\n"
	if err := os.WriteFile(path, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STACKPANEL_TEST_AGENT_PROCESS", "1")
	return Agent{ID: id, Path: path}
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func codexEvents(message string) string {
	encoded, _ := json.Marshal(message)
	return `{"type":"item.completed","item":{"type":"agent_message","text":` + string(encoded) + "}}\n" + "{\"type\":\"turn.completed\"}\n"
}

func claudeEvents(message string) string {
	encoded, _ := json.Marshal(message)
	return `{"type":"assistant","message":{"content":[]}}` + "\n" + `{"type":"result","subtype":"success","is_error":false,"result":` + string(encoded) + ",\"permission_denials\":[]}\n"
}

func TestDiscoverResolvesOnlyKnownExecutables(t *testing.T) {
	installed := fakeAgent(t, "codex")
	t.Setenv("PATH", filepath.Dir(installed.Path))
	agents := Discover()
	if len(agents) != 1 || agents[0] != installed {
		t.Fatalf("discovered %v, want %v", agents, installed)
	}
}

func TestProbeRunsTheInstalledCLI(t *testing.T) {
	agent := fakeAgent(t, "claude")
	if err := Probe(context.Background(), agent); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STACKPANEL_TEST_AGENT_FAIL", "1")
	if err := Probe(context.Background(), agent); err == nil || !strings.Contains(err.Error(), "fixture-cli") {
		t.Fatalf("broken CLI accepted or its output dropped: %v", err)
	}
	t.Setenv("STACKPANEL_TEST_AGENT_FAIL", "")
	t.Setenv("STACKPANEL_TEST_AGENT_DELAY", "1")
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	if err := Probe(ctx, agent); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("Probe error = %v", err)
	}
}

func TestRunSerializesSharedOutputWriter(t *testing.T) {
	agent := fakeAgent(t, "codex")
	events := codexEvents(complete)
	progress := strings.Repeat("working\n", 10000)
	t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", events)
	t.Setenv("STACKPANEL_TEST_AGENT_STDERR", progress)
	var stream bytes.Buffer
	_, err := Run(context.Background(), agent, RunRequest{Dir: t.TempDir(), Stdout: &stream, Stderr: &stream})
	if err != nil || stream.Len() != len(events)+len(progress) {
		t.Fatalf("shared output length = %d, error = %v", stream.Len(), err)
	}
}

func TestRunPassesLiteralPromptAndStreamsResult(t *testing.T) {
	for _, id := range []string{"codex", "claude"} {
		for _, readOnly := range []bool{true, false} {
			t.Run(id+map[bool]string{true: "/inspect", false: "/write"}[readOnly], func(t *testing.T) {
				agent := fakeAgent(t, id)
				root := t.TempDir()
				record := filepath.Join(root, "invocation.json")
				events := codexEvents(complete)
				if id == "claude" {
					events = claudeEvents(complete)
				}
				t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", events)
				t.Setenv("STACKPANEL_TEST_AGENT_RECORD", record)
				var output bytes.Buffer
				prompt := "literal `touch broken` $(touch broken)\n'quoted' \"text\""
				result, err := Run(context.Background(), agent, RunRequest{Dir: root, Prompt: prompt, ReadOnly: readOnly, Stdout: &output, Env: os.Environ()})
				if err != nil || result.ExitCode != 0 || result.Message != complete {
					t.Fatalf("Run = %+v, %v", result, err)
				}
				if output.String() != events {
					t.Fatal("provider output was not streamed")
				}
				data, err := os.ReadFile(record)
				if err != nil {
					t.Fatal(err)
				}
				var invocation struct {
					Args       []string
					Input, Dir string
				}
				if err := json.Unmarshal(data, &invocation); err != nil {
					t.Fatal(err)
				}
				if invocation.Input != prompt || invocation.Dir != root {
					t.Fatalf("wrong input or directory: %+v", invocation)
				}
				joined := strings.Join(invocation.Args, " ")
				if strings.Contains(joined, "bypass") || strings.Contains(joined, "skip-permissions") || strings.Contains(joined, prompt) {
					t.Fatalf("unsafe argument: %s", joined)
				}
				if id == "codex" {
					sandbox := map[bool]string{true: "read-only", false: "workspace-write"}[readOnly]
					if !strings.Contains(joined, "--sandbox "+sandbox) || !strings.Contains(joined, "mcp_servers={}") {
						t.Fatalf("wrong sandbox or integrations: %s", joined)
					}
				} else {
					tools := map[bool]string{true: "Read,Glob,Grep", false: "Read,Glob,Grep,Edit,Write"}[readOnly]
					if !strings.Contains(joined, "--tools "+tools+" ") {
						t.Fatalf("wrong tools: %s", joined)
					}
				}
			})
		}
	}
}

func TestRunToleratesNoiseWarningsAndDenials(t *testing.T) {
	denials := `[{"tool_name":"Glob","tool_input":{"pattern":"/nix/store/*/**/*.nix"}},{"tool_name":"Bash","tool_input":{"command":"private-command-input"}}]`
	for _, tt := range []struct {
		name, provider, events, warning string
	}{
		{"codex", "codex", "Reading prompt from stdin...\n" +
			`{"type":"error","message":"Reconnecting... 1/5"}` + "\n" + codexEvents(complete), "Reconnecting"},
		{"claude denials", "claude", `{"type":"result","subtype":"success","result":` + jsonString(complete) + `,"permission_denials":` + denials + "}\n", "denied Bash"},
		{"claude turn limit", "claude", `{"type":"result","subtype":"error_max_turns","result":` + jsonString(complete) + "}\n", "error_max_turns"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", tt.events)
			var warnings []string
			result, err := Run(context.Background(), fakeAgent(t, tt.provider), RunRequest{Dir: t.TempDir(), OnEvent: func(e Event) {
				if e.Kind == "warning" {
					warnings = append(warnings, e.Text)
				}
			}})
			if err != nil || result.Message != complete {
				t.Fatalf("Run = %+v, %v", result, err)
			}
			joined := strings.Join(warnings, "\n")
			if !strings.Contains(joined, tt.warning) || strings.Contains(joined, "private-command-input") {
				t.Fatalf("warnings = %q", joined)
			}
		})
	}
}

func jsonString(s string) string {
	data, _ := json.Marshal(s)
	return string(data)
}

func TestRunReportsFailedTurns(t *testing.T) {
	for _, tt := range []struct {
		name, provider, events, want string
	}{
		{"no reply", "codex", `{"type":"thread.started"}` + "\n", "without a reply"},
		{"turn failed", "codex", `{"type":"turn.failed","error":{"message":"login required"}}` + "\n", "login required"},
		{"claude error", "claude", `{"type":"result","is_error":true,"result":"Login required: run claude auth login"}` + "\n", "Login required"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", tt.events)
			_, err := Run(context.Background(), fakeAgent(t, tt.provider), RunRequest{Dir: t.TempDir()})
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("Run error = %v, want %q", err, tt.want)
			}
		})
	}
	agent := fakeAgent(t, "codex")
	t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", codexEvents(complete))
	t.Setenv("STACKPANEL_TEST_AGENT_STDERR", "fixture diagnostic")
	t.Setenv("STACKPANEL_TEST_AGENT_FAIL", "1")
	result, err := Run(context.Background(), agent, RunRequest{Dir: t.TempDir()})
	if err == nil || result.ExitCode != 7 || !strings.Contains(err.Error(), "fixture diagnostic") {
		t.Fatalf("Run = %+v, %v", result, err)
	}
	t.Setenv("STACKPANEL_TEST_AGENT_FAIL", "")
	t.Setenv("STACKPANEL_TEST_AGENT_LARGE", "1")
	if _, err := Run(context.Background(), agent, RunRequest{Dir: t.TempDir()}); err == nil {
		t.Fatal("oversize output succeeded")
	}
}

func TestRunCancellationKillsDescendants(t *testing.T) {
	if runtime.GOOS != "linux" && runtime.GOOS != "darwin" {
		t.Skip("process group cancellation is Unix-specific")
	}
	agent := fakeAgent(t, "codex")
	root := t.TempDir()
	marker := filepath.Join(root, "surviving-child")
	t.Setenv("STACKPANEL_TEST_AGENT_CHILD", marker)
	start := time.Now()
	_, err := Run(context.Background(), agent, RunRequest{Dir: root, Timeout: 150 * time.Millisecond})
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("Run error = %v", err)
	}
	if time.Since(start) > 2*time.Second {
		t.Fatal("cancellation did not terminate promptly")
	}
	time.Sleep(1100 * time.Millisecond)
	if _, err := os.Stat(marker); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("descendant survived cancellation: %v", err)
	}
}

func TestBuildPromptLetsTheAgentEditAndKeepsNixOnHost(t *testing.T) {
	req := SetupRequest{Root: "/repo", FlakeRef: "github:owner/repo/deadbeef", InspectionRef: "path:/nix/store/inspection-source",
		Template: "default", Context: `{"optionSchema":"schema-marker"}`, Constraints: `{"with":["go"]}`, Mode: "existing",
		Answers: []Answer{{ID: "language", Values: []string{"Go"}}}, Resuming: true, PreviousError: "fixture interruption"}
	inspection := BuildPrompt(req, Inspection, nil, "")
	for _, want := range []string{"phase inspection.", "Do not change files yet", "schema-marker", `"with":["go"]`, `"values":["Go"]`,
		`inputs.stackpanel.url = "github:owner/repo/deadbeef"`, `"status":"plan"`, "fixture interruption", "Do not run nix"} {
		if !strings.Contains(inspection, want) {
			t.Fatalf("inspection prompt lacks %q:\n%s", want, inspection)
		}
	}
	if strings.Contains(inspection, req.InspectionRef) {
		t.Fatal("the agent must persist the durable reference, not the scaffold source")
	}
	plan := &Plan{Summary: "Add the web app", Prepare: []PrepareCommand{{ID: "deps", Dir: ".", Argv: []string{"bun", "install"}}}}
	repair := BuildPrompt(req, Repair, plan, "config:apps.web is missing")
	for _, want := range []string{"phase repair.", "Add the web app", `"bun"`, "config:apps.web is missing", "any repository files", `"status":"complete"`} {
		if !strings.Contains(repair, want) {
			t.Fatalf("repair prompt lacks %q:\n%s", want, repair)
		}
	}
}
