package setupagent

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	piagent "github.com/sky-valley/pi/agent"
	"github.com/sky-valley/pi/ai"
	"github.com/sky-valley/pi/coding"
)

// PiState lives in the host's private setup manifest. Authentication is never
// serialized. The current setup prompt is supplied once as the system prompt,
// rather than appended to the conversation on every question or repair.
type PiState struct {
	Model    string            `json:"model"`
	Messages []json.RawMessage `json:"messages,omitempty"`
}

type piBackend struct {
	model *ai.Model
	key   string
}

// NewPiAgent resolves a pinned catalog model and API credential without making
// a network request. This experiment deliberately leaves subscription OAuth to
// the existing native CLI backends.
func NewPiAgent(spec string) (Agent, error) {
	if !strings.HasPrefix(spec, "openai/") && !strings.HasPrefix(spec, "anthropic/") {
		return Agent{}, errors.New("Pi requires --agent-model=openai/<model> or --agent-model=anthropic/<model>")
	}
	model, err := coding.ResolveModel(spec)
	if err != nil {
		return Agent{}, err
	}
	env := "OPENAI_API_KEY"
	if model.Provider == "anthropic" {
		env = "ANTHROPIC_API_KEY"
	}
	key := strings.TrimSpace(os.Getenv(env))
	if key == "" {
		return Agent{}, fmt.Errorf("Pi needs %s for direct API access (metered usage); subscription sign-ins are not supported by this Go port. Use --experimental-agent=codex or claude for CLI fallback", env)
	}
	return Agent{ID: "pi", pi: &piBackend{model: model, key: key}}, nil
}

func runPi(ctx context.Context, backend *piBackend, req RunRequest) (result RunResult, retErr error) {
	result.ExitCode = -1
	if backend == nil || !filepath.IsAbs(req.Dir) {
		return result, errors.New("Pi requires a configured provider and absolute repository directory")
	}
	// Provider errors can echo request headers. Keep the selected credential out
	// of errors, diagnostics, and the manifest even in that case.
	defer func() {
		if retErr != nil && strings.Contains(retErr.Error(), backend.key) {
			retErr = errors.New(strings.ReplaceAll(retErr.Error(), backend.key, "[redacted]"))
		}
	}()
	timeout := req.Timeout
	if timeout <= 0 {
		timeout = defaultRunTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	state := req.PiState
	if state == nil {
		state = &PiState{}
	}
	spec := string(backend.model.Provider) + "/" + backend.model.ID
	if state.Model != "" && state.Model != spec {
		return result, errors.New("Pi model differs from the saved conversation; use --restart to start a new plan")
	}
	state.Model = spec
	messages, err := decodePiMessages(state.Messages)
	if err != nil {
		return result, err
	}
	tools, err := piTools(req.Dir, req.ReadOnly, req.ProtectedPaths)
	if err != nil {
		return result, err
	}
	turns := 0
	a := piagent.NewAgent(piagent.AgentOptions{
		InitialState: &piagent.AgentState{Model: backend.model, SystemPrompt: req.Prompt,
			Messages: messages, Tools: tools, ThinkingLevel: piagent.ThinkLow},
		GetApiKey:     func(string) string { return backend.key },
		ToolExecution: piagent.ToolSequential,
		MaxRetries:    1,
		StreamFn: func(ctx context.Context, model *ai.Model, input ai.Context, opts *ai.SimpleStreamOptions) *ai.AssistantMessageEventStream {
			// Do not let ambient subscription tokens replace the selected API key.
			opts.Env = map[string]string{"ANTHROPIC_AUTH_TOKEN": "", "ANTHROPIC_OAUTH_TOKEN": ""}
			return ai.StreamSimple(ctx, model, input, opts)
		},
		ShouldStopAfterTurn: func(context.Context, piagent.ShouldStopAfterTurnContext) bool {
			turns++
			return turns >= 32
		},
	})
	var saveErr error
	a.Subscribe(func(_ context.Context, event piagent.AgentEvent) error {
		activity := ""
		switch event.Type {
		case piagent.EvTurnStart:
			activity = "Pi · waiting for " + spec
		case piagent.EvToolExecutionStart:
			activity = "Pi · " + event.ToolName
		case piagent.EvMessageEnd:
			data, err := json.Marshal(a.State().Messages)
			data = bytes.ReplaceAll(data, []byte(backend.key), []byte("[redacted]"))
			if err == nil && len(data) > 8<<20 {
				err = errors.New("Pi conversation exceeded 8 MiB; start a new plan with --restart")
			}
			if err == nil {
				err = json.Unmarshal(data, &state.Messages)
			}
			if err == nil && req.SavePiState != nil {
				err = req.SavePiState()
			}
			if err != nil {
				saveErr = err
				return err
			}
		}
		if activity != "" {
			if req.OnEvent != nil {
				req.OnEvent(Event{Kind: "activity", Text: activity})
			}
			if req.Stdout != nil {
				fmt.Fprintln(req.Stdout, activity)
			}
		}
		return nil
	})
	err = a.Prompt(ctx, "Continue from the current repository state using the setup request and saved answers above. Return the required setup JSON reply.")
	if saveErr != nil {
		return result, fmt.Errorf("save Pi conversation: %w", saveErr)
	}
	if ctx.Err() != nil {
		return result, ctx.Err()
	}
	if err != nil {
		return result, err
	}
	if a.State().ErrorMessage != "" {
		return result, errors.New(a.State().ErrorMessage)
	}
	if turns >= 32 {
		return result, errors.New("Pi exceeded 32 model turns; progress was saved")
	}
	completed := a.State().Messages
	if len(completed) == 0 {
		return result, errors.New("Pi ended without a response")
	}
	data, err := json.Marshal(completed[len(completed)-1])
	if err != nil {
		return result, err
	}
	message, err := ai.UnmarshalMessage(data)
	if err != nil {
		return result, err
	}
	assistant, ok := message.(ai.AssistantMessage)
	if !ok || assistant.StopReason != ai.StopStop {
		return result, fmt.Errorf("Pi did not finish its response (stop reason %q); progress was saved", assistant.StopReason)
	}
	for _, content := range assistant.Content {
		if text, ok := content.(ai.TextContent); ok {
			result.Message += text.Text
		}
	}
	if strings.TrimSpace(result.Message) == "" {
		return result, errors.New("Pi ended without a complete setup reply")
	}
	result.ExitCode = 0
	reply, err := ParseReply(result.Message)
	if err != nil {
		return result, err
	}
	if !req.ReadOnly && reply.Status != "complete" && reply.Status != "needs_input" {
		return result, fmt.Errorf("Pi did not complete (%s): %s", reply.Status, reply.Summary)
	}
	return result, nil
}

func decodePiMessages(raw []json.RawMessage) ([]piagent.AgentMessage, error) {
	messages := make([]piagent.AgentMessage, 0, len(raw))
	for _, data := range raw {
		message, err := ai.UnmarshalMessage(data)
		if err != nil {
			return nil, err
		}
		messages = append(messages, message)
	}
	return messages, nil
}
