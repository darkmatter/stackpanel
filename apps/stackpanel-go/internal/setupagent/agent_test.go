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
	helpText  = "--print --output-format stream-json --verbose --permission-mode plan acceptEdits --permission-prompts --tools --strict-mcp-config --mcp-config --settings --json --sandbox --config --color read-only workspace-write"
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
	for _, arg := range args {
		if arg == "--help" {
			_, _ = io.WriteString(os.Stdout, os.Getenv("STACKPANEL_TEST_AGENT_HELP"))
			os.Exit(0)
		}
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
	t.Setenv("STACKPANEL_TEST_AGENT_HELP", helpText)
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

func TestProbeChecksCapabilitiesWithoutRunningAgent(t *testing.T) {
	for _, id := range []string{"codex", "claude"} {
		t.Run(id, func(t *testing.T) {
			agent := fakeAgent(t, id)
			caps, err := Probe(context.Background(), agent)
			if err != nil || !caps.ReadOnly || !caps.Write {
				t.Fatalf("Probe = %+v, %v", caps, err)
			}
			t.Setenv("STACKPANEL_TEST_AGENT_HELP", "old CLI --help")
			caps, err = Probe(context.Background(), agent)
			if err != nil || caps.ReadOnly || caps.Write || caps.Reason == "" {
				t.Fatalf("old CLI Probe = %+v, %v", caps, err)
			}
		})
	}
	caps, err := Probe(context.Background(), Agent{ID: "opencode", Path: "/unused/opencode"})
	if err != nil || caps.ReadOnly || caps.Write || caps.Reason == "" {
		t.Fatalf("OpenCode Probe = %+v, %v", caps, err)
	}
}

func TestProbeHonorsCancellation(t *testing.T) {
	agent := fakeAgent(t, "codex")
	t.Setenv("STACKPANEL_TEST_AGENT_DELAY", "1")
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	_, err := Probe(ctx, agent)
	if !errors.Is(err, context.DeadlineExceeded) {
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

func TestRunPassesLiteralPromptAndStreamsCompletedResult(t *testing.T) {
	for _, id := range []string{"codex", "claude"} {
		for _, readOnly := range []bool{true, false} {
			t.Run(id+map[bool]string{true: "/inspect", false: "/write"}[readOnly], func(t *testing.T) {
				agent := fakeAgent(t, id)
				root := t.TempDir()
				record := filepath.Join(root, "invocation.json")
				message := complete
				if readOnly {
					message = validPlan
				}
				events := codexEvents(message)
				if id == "claude" {
					events = claudeEvents(message)
				}
				t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", events)
				t.Setenv("STACKPANEL_TEST_AGENT_RECORD", record)
				var output bytes.Buffer
				prompt := "literal `touch broken` $(touch broken)\n'quoted' \"text\""
				result, err := Run(context.Background(), agent, RunRequest{Dir: root, Prompt: prompt, ReadOnly: readOnly, Stdout: &output, Env: os.Environ()})
				if err != nil || result.ExitCode != 0 || result.Message != message {
					t.Fatalf("Run = %+v, %v", result, err)
				}
				if output.String() != events {
					t.Fatal("provider progress was not streamed")
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
				for _, arg := range invocation.Args {
					if strings.Contains(arg, "bypass") || strings.Contains(arg, "skip-permissions") || arg == "--model" || arg == prompt {
						t.Fatalf("unsafe/overriding argument: %q", arg)
					}
				}
				joined := strings.Join(invocation.Args, " ")
				if id == "codex" {
					wantSandbox := "workspace-write"
					if readOnly {
						wantSandbox = "read-only"
					}
					if !strings.Contains(joined, "--sandbox "+wantSandbox) || !strings.Contains(joined, "mcp_servers={}") {
						t.Fatalf("missing sandbox/integration constraints: %s", joined)
					}
				} else if !strings.Contains(joined, "--permission-prompts none") || (readOnly && !strings.Contains(joined, "--tools Read,Glob,Grep --strict-mcp-config")) {
					t.Fatalf("missing headless permission constraints: %s", joined)
				}
			})
		}
	}
}

func TestRunRejectsIncompleteAndFailedProviderResults(t *testing.T) {
	tests := []struct {
		name, provider, events, want string
	}{
		{"no completion", "codex", `{"type":"thread.started"}` + "\n", "without a complete result"},
		{"turn failed", "codex", "{\"type\":\"turn.failed\",\"error\":{\"message\":\"login required\"}}\n", "provider reported failure"},
		{"error despite exit zero", "codex", "{\"type\":\"error\",\"message\":\"permission denied\"}\n" + codexEvents(complete), "provider reported failure"},
		{"blocked", "codex", codexEvents(`{"status":"blocked","summary":"permission required"}`), "did not complete"},
		{"unstructured success", "codex", codexEvents("I am done"), "did not return a completion status"},
		{"invalid event", "codex", "not json\n", "invalid agent event"},
		{"claude denied", "claude", "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"done\",\"permission_denials\":[{\"tool_name\":\"Bash\"}]}\n", "permissions that were denied"},
		{"claude incomplete", "claude", "{\"type\":\"result\",\"subtype\":\"error_max_turns\"}\n", "provider result was"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			agent := fakeAgent(t, tt.provider)
			t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", tt.events)
			_, err := Run(context.Background(), agent, RunRequest{Dir: t.TempDir()})
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("Run error = %v, want %q", err, tt.want)
			}
		})
	}
}

func TestRunRejectsExitFailureAndOversizeOutput(t *testing.T) {
	agent := fakeAgent(t, "codex")
	t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", codexEvents(complete))
	t.Setenv("STACKPANEL_TEST_AGENT_FAIL", "1")
	result, err := Run(context.Background(), agent, RunRequest{Dir: t.TempDir()})
	if err == nil || result.ExitCode != 7 {
		t.Fatalf("Run = %+v, %v", result, err)
	}
	t.Setenv("STACKPANEL_TEST_AGENT_FAIL", "0")
	t.Setenv("STACKPANEL_TEST_AGENT_LARGE", "1")
	_, err = Run(context.Background(), agent, RunRequest{Dir: t.TempDir()})
	if err == nil {
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

func TestParsePlanRejectsInvalidContracts(t *testing.T) {
	plan, err := ParsePlan(validPlan)
	if err != nil || plan.Summary != "Add web app" {
		t.Fatalf("ParsePlan = %+v, %v", plan, err)
	}
	for _, message := range []string{
		validPlan + " {}",
		"```json\n" + validPlan + "\n```",
		strings.Replace(validPlan, `"summary"`, `"unknown"`, 1),
		strings.Replace(validPlan, `"version":1`, `"version":99`, 1),
		strings.Replace(validPlan, `"exists":true`, `"exists":"yes"`, 1),
		`{"summary":"nothing","expectations":{"version":1,"config":[],"requiredChecks":[]}}`,
	} {
		if _, err := ParsePlan(message); err == nil {
			t.Fatalf("accepted invalid plan: %s", message)
		}
	}
}

func TestBuildPromptContainsFrozenContractAndLiteralArguments(t *testing.T) {
	plan, err := ParsePlan(validPlan)
	if err != nil {
		t.Fatal(err)
	}
	req := SetupRequest{Root: "/repo", StackExecutable: "/path with spaces/stack", FlakeRef: "github:owner/repo/deadbeef", Template: "default", Context: "addon metadata", Constraints: "keep web"}
	inspection := BuildPrompt(req, Inspection, nil, "")
	if !strings.Contains(inspection, "Inspect only") || !strings.Contains(inspection, req.Context) {
		t.Fatal("inspection prompt lacks repository context or read-only instruction")
	}
	repair := BuildPrompt(req, Repair, plan, "missing web app")
	for _, required := range []string{`["/path with spaces/stack","setup","--yes","--only","scaffold","--flake","github:owner/repo/deadbeef"`, "Frozen onboarding plan", "apps", "missing web app", "single repair attempt", req.Constraints, "Never manually edit .stack/gen", "explicitly set inputs.stackpanel", "pure nix flake lock", "retain only options needed", "Leave the Git index unchanged"} {
		if !strings.Contains(repair, required) {
			t.Fatalf("repair prompt missing %q", required)
		}
	}
	req.InspectionRef = "path:/nix/store/inspection-source"
	repair = BuildPrompt(req, Repair, plan, "missing web app")
	if !strings.Contains(repair, `"--flake","path:/nix/store/inspection-source"`) || !strings.Contains(repair, `reference to persist in the target flake: "github:owner/repo/deadbeef"`) {
		t.Fatal("prompt must separate immutable scaffold source from durable input reference")
	}
}
