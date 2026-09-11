// Package setupagent runs an installed coding agent for repository onboarding.
// An agent's completion is never evidence that onboarding passed verification.
package setupagent

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	probeTimeout      = 5 * time.Second
	defaultRunTimeout = 15 * time.Minute
	maxMessageBytes   = 1 << 20
)

type Agent struct {
	ID   string `json:"id"`
	Path string `json:"path"`
}

type Capabilities struct {
	ReadOnly bool   `json:"readOnly"`
	Write    bool   `json:"write"`
	Reason   string `json:"reason,omitempty"`
}

type RunRequest struct {
	Dir      string
	Prompt   string
	ReadOnly bool
	Stdout   io.Writer
	Stderr   io.Writer
	OnEvent  func(Event)
	// Env defaults to the current process environment. Authentication and model
	// selection remain the installed CLI's responsibility.
	Env     []string
	Timeout time.Duration
}

// Event is provider-independent progress. Provider JSON stays in the debug log.
type Event struct {
	Kind string
	Text string
}

type RunResult struct {
	ExitCode int
	Message  string
}

// Discover resolves known executables on the caller's PATH before a target
// repository's shell can replace it. It does not execute or authenticate them.
func Discover() []Agent {
	var agents []Agent
	for _, id := range []string{"codex", "claude", "opencode"} {
		path, err := exec.LookPath(id)
		if err != nil {
			continue
		}
		path, err = filepath.Abs(path)
		if err == nil {
			agents = append(agents, Agent{ID: id, Path: path})
		}
	}
	return agents
}

// Probe checks the installed command's flags without making a model request.
// Installation and suitable flags do not establish authentication readiness.
func Probe(ctx context.Context, agent Agent) (Capabilities, error) {
	if !filepath.IsAbs(agent.Path) {
		return Capabilities{}, fmt.Errorf("agent executable must have an absolute path")
	}
	var args, required []string
	switch agent.ID {
	case "codex":
		args = []string{"exec", "--help"}
		required = []string{"--json", "--sandbox", "--config", "--color", "read-only", "workspace-write"}
	// Claude hides SDK-oriented flags such as --tools and --verbose from
	// some help variants. Invocation still passes them and fails closed if
	// unsupported; help omission is not evidence of incompatibility.
	case "claude":
		args = []string{"--help"}
		required = []string{"--print", "--output-format", "stream-json", "--permission-mode", "plan", "acceptEdits", "--strict-mcp-config", "--mcp-config", "--settings"}
	case "opencode":
		return Capabilities{Reason: "OpenCode is installed, but this experiment cannot enforce read-only inspection with its configurable agents; select codex or claude"}, nil
	default:
		return Capabilities{}, fmt.Errorf("unsupported setup agent %q", agent.ID)
	}
	ctx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, agent.Path, args...)
	configureProcess(cmd)
	output := &limitedBuffer{}
	cmd.Stdout, cmd.Stderr = output, output
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			err = ctx.Err()
		}
		return Capabilities{}, fmt.Errorf("probe %s: %w", agent.ID, err)
	}
	if output.truncated {
		return Capabilities{}, fmt.Errorf("probe %s: help output exceeded limit", agent.ID)
	}
	for _, flag := range required {
		if !strings.Contains(output.String(), flag) {
			return Capabilities{Reason: fmt.Sprintf("installed %s does not advertise required capability %s", agent.ID, flag)}, nil
		}
	}
	return Capabilities{ReadOnly: true, Write: true}, nil
}

func commandFor(agent Agent, req RunRequest) ([]string, error) {
	switch agent.ID {
	case "codex":
		sandbox := "workspace-write"
		if req.ReadOnly {
			sandbox = "read-only"
		}
		// Overrides replace these tables for this invocation. Keep user auth and
		// model configuration, while disabling integrations outside the sandbox.
		return []string{
			"exec", "--json", "--sandbox", sandbox, "--color", "never",
			"-c", `approval_policy="never"`, "-c", "mcp_servers={}",
			"-c", "features.apps=false", "-c", "features.plugins=false",
			"-c", "features.hooks=false", "-c", "features.multi_agent=false",
			"-c", "features.multi_agent_v2=false", "-c", "features.recommended_plugins=false",
			"-c", "features.skill_mcp_dependency_install=false", "-",
		}, nil
	case "claude":
		mode, allowedTools := "acceptEdits", "Read,Glob,Grep,Edit,Write,Bash"
		if req.ReadOnly {
			mode, allowedTools = "plan", "Read,Glob,Grep"
		}
		return []string{
			"--print", "--output-format", "stream-json", "--verbose",
			"--permission-mode", mode,
			"--tools", allowedTools, "--strict-mcp-config", "--mcp-config", `{"mcpServers":{}}`,
			"--settings", `{"disableAllHooks":true}`,
		}, nil
	default:
		return nil, fmt.Errorf("unsupported setup agent %q", agent.ID)
	}
}

// Run streams JSON events without retaining the transcript. It requires a
// provider completion event, rejects provider/permission errors, and bounds
// execution time and individual event size. It does not approve shell commands
// denied by the CLI's configured policy.
func Run(ctx context.Context, agent Agent, req RunRequest) (RunResult, error) {
	result := RunResult{ExitCode: -1}
	if !filepath.IsAbs(agent.Path) || !filepath.IsAbs(req.Dir) {
		return result, fmt.Errorf("agent executable and repository directory must be absolute")
	}
	args, err := commandFor(agent, req)
	if err != nil {
		return result, err
	}
	timeout := req.Timeout
	if timeout <= 0 {
		timeout = defaultRunTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, agent.Path, args...)
	configureProcess(cmd)
	cmd.Dir = req.Dir
	cmd.Env = req.Env
	cmd.Stdin = strings.NewReader(req.Prompt)
	// Stdout and stderr frequently share a terminal or a caller's buffer.
	// os/exec copies them concurrently because stdout also parses events.
	var streamMu sync.Mutex
	events := &eventWriter{provider: agent.ID, out: &lockedWriter{mu: &streamMu, out: req.Stdout}, onEvent: req.OnEvent}
	cmd.Stdout = events
	stderr := &limitedBuffer{}
	cmd.Stderr = io.MultiWriter(&lockedWriter{mu: &streamMu, out: req.Stderr}, stderr)
	err = cmd.Run()
	events.finish()
	result.Message = events.message
	if cmd.ProcessState != nil {
		result.ExitCode = cmd.ProcessState.ExitCode()
	}
	if ctx.Err() != nil {
		return result, fmt.Errorf("%s setup agent: %w", agent.ID, ctx.Err())
	}
	if events.err != nil {
		return result, fmt.Errorf("%s setup agent: %w", agent.ID, events.err)
	}
	if err != nil {
		diagnostic := strings.TrimSpace(stderr.String())
		if len(diagnostic) > 2000 {
			diagnostic = diagnostic[len(diagnostic)-2000:]
		}
		return result, fmt.Errorf("%s setup agent exited unsuccessfully: %w: %s", agent.ID, err, diagnostic)
	}
	if !events.completed || strings.TrimSpace(events.message) == "" {
		return result, fmt.Errorf("%s setup agent exited without a complete result", agent.ID)
	}
	if !req.ReadOnly {
		reply, err := ParseReply(events.message)
		if err != nil {
			return result, err
		}
		if reply.Status != "complete" && reply.Status != "needs_input" {
			return result, fmt.Errorf("%s setup agent did not complete (%s): %s", agent.ID, reply.Status, reply.Summary)
		}
	}
	return result, nil
}

type lockedWriter struct {
	mu  *sync.Mutex
	out io.Writer
}

func (w *lockedWriter) Write(p []byte) (int, error) {
	if w.out == nil {
		return len(p), nil
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.out.Write(p)
}

// limitedBuffer bounds probes. A large CLI response is consumed but is never
// mistaken for a complete, parseable response.
type limitedBuffer struct {
	bytes.Buffer
	truncated bool
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	n := len(p)
	available := maxMessageBytes - b.Len()
	if len(p) > available {
		b.truncated = true
		p = p[:available]
	}
	_, _ = b.Buffer.Write(p)
	return n, nil
}

// eventWriter parses one JSONL event at a time. Only the final message and first
// error survive, so a verbose long-running agent cannot exhaust memory.
type eventWriter struct {
	provider  string
	out       io.Writer
	pending   []byte
	message   string
	completed bool
	err       error
	onEvent   func(Event)
}

func (w *eventWriter) Write(p []byte) (int, error) {
	n := len(p)
	if w.out != nil {
		if _, err := w.out.Write(p); err != nil {
			return 0, err
		}
	}
	for len(p) > 0 {
		end := bytes.IndexByte(p, '\n')
		if end < 0 {
			end = len(p)
		}
		if len(w.pending)+end > maxMessageBytes {
			return n, fmt.Errorf("agent event exceeded %d bytes", maxMessageBytes)
		}
		w.pending = append(w.pending, p[:end]...)
		if end == len(p) {
			break
		}
		w.consume(w.pending)
		w.pending = w.pending[:0]
		p = p[end+1:]
	}
	return n, nil
}

func (w *eventWriter) finish() {
	if len(bytes.TrimSpace(w.pending)) != 0 {
		w.consume(w.pending)
	}
}

func (w *eventWriter) consume(line []byte) {
	if len(bytes.TrimSpace(line)) == 0 || w.err != nil {
		return
	}
	var event struct {
		Type              string            `json:"type"`
		Subtype           string            `json:"subtype"`
		Result            string            `json:"result"`
		IsError           bool              `json:"is_error"`
		PermissionDenials []json.RawMessage `json:"permission_denials"`
		Error             json.RawMessage   `json:"error"`
		Message           json.RawMessage   `json:"message"`
		Item              struct {
			Type    string `json:"type"`
			Text    string `json:"text"`
			Command string `json:"command"`
		} `json:"item"`
	}
	if err := json.Unmarshal(line, &event); err != nil {
		w.err = fmt.Errorf("invalid agent event: %w", err)
		return
	}
	if event.Type == "error" || event.Type == "turn.failed" || event.IsError {
		w.err = fmt.Errorf("provider reported failure: %s %s %s", event.Result, event.Message, event.Error)
		return
	}
	if w.onEvent != nil {
		if event.Item.Type == "command_execution" && event.Type == "item.started" {
			w.onEvent(Event{Kind: "tool", Text: event.Item.Command})
		}
		if event.Type == "assistant" {
			var msg struct {
				Content []struct {
					Type string `json:"type"`
					Name string `json:"name"`
				} `json:"content"`
			}
			if json.Unmarshal(event.Message, &msg) == nil {
				for _, part := range msg.Content {
					if part.Type == "tool_use" {
						w.onEvent(Event{Kind: "tool", Text: part.Name})
					}
				}
			}
		}
	}
	switch w.provider {
	case "codex":
		if event.Type == "item.completed" && event.Item.Type == "agent_message" {
			w.message = event.Item.Text
		}
		if event.Type == "turn.completed" {
			w.completed = true
		}
	case "claude":
		if event.Type == "result" {
			if event.Subtype != "success" {
				w.err = fmt.Errorf("provider result was %q", event.Subtype)
				return
			}
			if len(event.PermissionDenials) != 0 {
				w.err = errors.New("agent requested permissions that were denied; configure the CLI permissions and retry")
				return
			}
			w.message, w.completed = event.Result, true
		}
	}
}
