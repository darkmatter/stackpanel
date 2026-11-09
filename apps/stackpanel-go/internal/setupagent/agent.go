// Package setupagent runs a coding agent for repository onboarding. The agent
// edits the repository; the host verifies the result with stack doctor.
package setupagent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	probeTimeout      = 10 * time.Second
	defaultRunTimeout = 45 * time.Minute
	maxMessageBytes   = 1 << 20
)

type Agent struct {
	ID   string `json:"id"`
	Path string `json:"path"`
	pi   *piBackend
}

type RunRequest struct {
	Dir    string
	Prompt string
	// ReadOnly runs an inspection turn, which must not change files.
	ReadOnly bool
	Stdout   io.Writer
	Stderr   io.Writer
	OnEvent  func(Event)
	// Env defaults to the current process environment. Authentication and model
	// selection remain the installed CLI's responsibility.
	Env         []string
	Timeout     time.Duration
	PiState     *PiState
	SavePiState func() error
}

// Event is provider-independent progress. Provider JSON stays in the debug log.
type Event struct {
	Kind string // tool, warning, or activity
	Text string
}

type RunResult struct {
	ExitCode int
	Message  string
}

// Discover resolves supported agent CLIs on the caller's PATH, before a target
// repository's shell can change it. It does not execute or authenticate them.
func Discover() []Agent {
	var agents []Agent
	for _, id := range []string{"codex", "claude"} {
		path, err := exec.LookPath(id)
		if err != nil {
			continue
		}
		if path, err = filepath.Abs(path); err == nil {
			agents = append(agents, Agent{ID: id, Path: path})
		}
	}
	return agents
}

// Probe checks that the installed CLI runs. It makes no model request, so it
// does not establish that the CLI is signed in.
func Probe(ctx context.Context, agent Agent) error {
	ctx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, agent.Path, "--version")
	configureProcess(cmd)
	output := &limitedBuffer{}
	cmd.Stdout, cmd.Stderr = output, output
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			err = ctx.Err()
		}
		return fmt.Errorf("%s --version: %w %s", agent.ID, err, strings.TrimSpace(output.String()))
	}
	return nil
}

func commandFor(agent Agent, req RunRequest) ([]string, error) {
	switch agent.ID {
	case "codex":
		sandbox := "workspace-write"
		if req.ReadOnly {
			sandbox = "read-only"
		}
		// Keep the user's auth and model configuration, but leave out
		// integrations that would act outside the repository.
		return []string{
			"exec", "--json", "--sandbox", sandbox, "--color", "never",
			"-c", `approval_policy="never"`, "-c", "mcp_servers={}",
			"-c", "features.apps=false", "-c", "features.plugins=false",
			"-c", "features.hooks=false", "-c", "features.multi_agent=false",
			"-c", "features.multi_agent_v2=false", "-c", "features.recommended_plugins=false",
			"-c", "features.skill_mcp_dependency_install=false", "-",
		}, nil
	case "claude":
		// Native file tools need no shell. The host runs Nix, installs, and checks.
		mode, tools := "acceptEdits", "Read,Glob,Grep,Edit,Write"
		if req.ReadOnly {
			mode, tools = "plan", "Read,Glob,Grep"
		}
		return []string{
			"--print", "--output-format", "stream-json", "--verbose",
			"--permission-mode", mode,
			"--tools", tools, "--strict-mcp-config", "--mcp-config", `{"mcpServers":{}}`,
			"--settings", `{"disableAllHooks":true}`,
		}, nil
	default:
		return nil, fmt.Errorf("unsupported setup agent %q", agent.ID)
	}
}

// Run executes one agent turn and returns its final message. Only a turn that
// failed outright is an error: progress noise, provider warnings, and denied
// tool requests are reported as events, and the reply is parsed leniently by
// ParseReply.
func Run(ctx context.Context, agent Agent, req RunRequest) (RunResult, error) {
	if agent.ID == "pi" {
		return runPi(ctx, agent.pi, req)
	}
	result := RunResult{ExitCode: -1}
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
	cmd.Env = agentCommandEnv(agent, req.Env)
	cmd.Stdin = strings.NewReader(req.Prompt)
	// Stdout and stderr often share a terminal or a caller's buffer, and
	// os/exec copies them concurrently.
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
	switch {
	case ctx.Err() != nil:
		return result, ctx.Err()
	case events.err != nil:
		return result, events.err
	case err != nil:
		diagnostic := strings.TrimSpace(stderr.String())
		if len(diagnostic) > 2000 {
			diagnostic = diagnostic[len(diagnostic)-2000:]
		}
		return result, fmt.Errorf("exited unsuccessfully: %w: %s", err, diagnostic)
	case strings.TrimSpace(result.Message) == "":
		return result, fmt.Errorf("finished without a reply")
	}
	return result, nil
}

func agentCommandEnv(agent Agent, env []string) []string {
	if agent.ID != "codex" || len(env) == 0 {
		return env
	}
	// Codex runs shell commands with $SHELL -lc. zsh startup files and heredocs
	// create temporary files, which fails in the read-only inspection sandbox.
	out := make([]string, 0, len(env)+1)
	for _, kv := range env {
		if strings.HasPrefix(kv, "SHELL=") || strings.HasPrefix(kv, "ZDOTDIR=") {
			continue
		}
		out = append(out, kv)
	}
	return append(out, "SHELL=/bin/sh")
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

// limitedBuffer keeps at most maxMessageBytes of output.
type limitedBuffer struct {
	bytes.Buffer
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	n := len(p)
	if available := maxMessageBytes - b.Len(); len(p) > available {
		p = p[:available]
	}
	_, _ = b.Buffer.Write(p)
	return n, nil
}

// eventWriter parses the provider's JSONL stream one line at a time and keeps
// only the latest reply, so a verbose agent cannot exhaust memory.
type eventWriter struct {
	provider string
	out      io.Writer
	pending  []byte
	message  string
	err      error
	onEvent  func(Event)
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

func (w *eventWriter) emit(kind, text string) {
	if w.onEvent != nil && text != "" {
		w.onEvent(Event{Kind: kind, Text: text})
	}
}

func (w *eventWriter) consume(line []byte) {
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
	if w.err != nil || json.Unmarshal(line, &event) != nil {
		return // Not an event, such as a CLI notice. It remains in the debug log.
	}
	switch w.provider {
	case "codex":
		switch event.Type {
		case "item.started":
			if event.Item.Type == "command_execution" {
				w.emit("tool", event.Item.Command)
			}
		case "item.completed":
			if event.Item.Type == "agent_message" {
				w.message = event.Item.Text
			}
		case "error":
			// Codex also reports retried stream errors this way.
			w.emit("warning", "codex: "+rawText(event.Message))
		case "turn.failed":
			w.err = fmt.Errorf("turn failed: %s", rawText(event.Error))
		}
	case "claude":
		switch event.Type {
		case "assistant":
			var msg struct {
				Content []struct {
					Type string `json:"type"`
					Name string `json:"name"`
				} `json:"content"`
			}
			if json.Unmarshal(event.Message, &msg) == nil {
				for _, part := range msg.Content {
					if part.Type == "tool_use" {
						w.emit("tool", part.Name)
					}
				}
			}
		case "result":
			if event.IsError {
				w.err = fmt.Errorf("claude reported an error (%s): %s", event.Subtype, event.Result)
				return
			}
			if event.Subtype != "success" {
				w.emit("warning", "claude ended its turn early: "+event.Subtype)
			}
			for _, denial := range event.PermissionDenials {
				w.emit("warning", claudeDenial(denial))
			}
			w.message = event.Result
		}
	}
}

// rawText renders an event's message or error field, which providers send as
// a string or as an object with a message.
func rawText(raw json.RawMessage) string {
	var text string
	if json.Unmarshal(raw, &text) == nil {
		return text
	}
	var object struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(raw, &object) == nil && object.Message != "" {
		return object.Message
	}
	return string(raw)
}

// Claude reports tool requests it refused, even when the turn succeeded. They
// are worth knowing about but do not mean the setup failed; doctor decides that.
// Only file paths are shown: command inputs can contain anything.
func claudeDenial(raw json.RawMessage) string {
	var denial struct {
		ToolName  string `json:"tool_name"`
		ToolInput struct {
			FilePath string `json:"file_path"`
			Path     string `json:"path"`
			Pattern  string `json:"pattern"`
		} `json:"tool_input"`
	}
	_ = json.Unmarshal(raw, &denial)
	detail := denial.ToolName
	if detail == "" {
		detail = "a tool"
	}
	if denial.ToolName == "Read" || denial.ToolName == "Glob" || denial.ToolName == "Grep" {
		path := denial.ToolInput.FilePath
		if path == "" {
			path = denial.ToolInput.Path
		}
		if path == "" && denial.ToolName == "Glob" {
			path = denial.ToolInput.Pattern
		}
		if len(path) > 300 {
			path = path[:300] + "…"
		}
		if path != "" {
			detail += fmt.Sprintf(" (%q)", path)
		}
	}
	return "Claude was denied " + detail + " and continued without it."
}
