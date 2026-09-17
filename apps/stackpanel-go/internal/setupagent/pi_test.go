package setupagent

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// These fixtures exercise Pi's actual HTTP/SSE adapter and agent/tool loop;
// they never invoke installed agents or send credentials to a real provider.
func piFixture(t *testing.T, handler http.HandlerFunc) Agent {
	t.Helper()
	t.Setenv("OPENAI_API_KEY", "test-pi-secret")
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	agent, err := NewPiAgent("openai/gpt-5")
	if err != nil {
		t.Fatal(err)
	}
	model := *agent.pi.model
	model.BaseURL = server.URL
	agent.pi.model = &model
	return agent
}

func piSSE(w http.ResponseWriter, tool string, args any, reply string) {
	w.Header().Set("Content-Type", "text/event-stream")
	emit := func(v any) { data, _ := json.Marshal(v); fmt.Fprintf(w, "data: %s\n\n", data) }
	emit(map[string]any{"type": "response.created", "response": map[string]any{"id": "resp_1"}})
	if tool != "" {
		data, _ := json.Marshal(args)
		item := map[string]any{"type": "function_call", "id": "fc_1", "call_id": "call_1", "name": tool, "arguments": ""}
		emit(map[string]any{"type": "response.output_item.added", "item": item})
		emit(map[string]any{"type": "response.function_call_arguments.delta", "delta": string(data)})
		item["arguments"] = string(data)
		emit(map[string]any{"type": "response.output_item.done", "item": item})
	} else {
		item := map[string]any{"type": "message", "id": "msg_1"}
		emit(map[string]any{"type": "response.output_item.added", "item": item})
		emit(map[string]any{"type": "response.content_part.added", "part": map[string]string{"type": "output_text", "text": ""}})
		emit(map[string]any{"type": "response.output_text.delta", "delta": reply})
		item["content"] = []any{map[string]string{"type": "output_text", "text": reply}}
		emit(map[string]any{"type": "response.output_item.done", "item": item})
	}
	emit(map[string]any{"type": "response.completed", "response": map[string]any{"id": "resp_1", "status": "completed", "usage": map[string]int{"input_tokens": 10, "output_tokens": 10}}})
}

func TestPiConversationResumesAndUsesNativeTools(t *testing.T) {
	root := t.TempDir()
	var mu sync.Mutex
	var bodies []string
	a := piFixture(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-pi-secret" {
			t.Error("API key not sent")
		}
		data, _ := io.ReadAll(r.Body)
		mu.Lock()
		defer mu.Unlock()
		bodies = append(bodies, string(data))
		switch len(bodies) {
		case 1:
			piSSE(w, "", nil, `{"status":"needs_input","questions":[{"id":"name","prompt":"Project name?","kind":"text","required":true}]}`)
		case 2:
			piSSE(w, "write", map[string]string{"path": "hello.txt", "content": "hello from Pi"}, "")
		case 3:
			piSSE(w, "edit", map[string]any{"path": "hello.txt", "edits": []any{map[string]string{"oldText": "hello from Pi", "newText": "resumed project"}}}, "")
		default:
			piSSE(w, "", nil, `{"status":"complete","summary":"Created the project"}`)
		}
	})
	state := &PiState{}
	saves := 0
	req := RunRequest{Dir: root, Prompt: "schema-marker inspect only", ReadOnly: true, PiState: state, SavePiState: func() error { saves++; return nil }}
	result, err := Run(context.Background(), a, req)
	if err != nil || !strings.Contains(result.Message, "needs_input") {
		t.Fatalf("inspection: %v %s", err, result.Message)
	}
	// Reconstruct both the host manifest and embedded backend, as on a rerun.
	data, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	state = &PiState{}
	if err := json.Unmarshal(data, state); err != nil {
		t.Fatal(err)
	}
	a = Agent{ID: "pi", pi: &piBackend{model: a.pi.model, key: a.pi.key}}
	req.PiState, req.ReadOnly, req.Prompt = state, false, "schema-marker accepted name=resumed project"
	result, err = Run(context.Background(), a, req)
	if err != nil || !strings.Contains(result.Message, "complete") {
		t.Fatalf("setup: %v %s", err, result.Message)
	}
	data, err = os.ReadFile(filepath.Join(root, "hello.txt"))
	if err != nil || string(data) != "resumed project" {
		t.Fatalf("file: %s %v", data, err)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(bodies) != 4 || !strings.Contains(bodies[1], "Project name?") {
		t.Fatalf("conversation not resumed: %d requests", len(bodies))
	}
	for _, body := range bodies {
		if strings.Count(body, "schema-marker") != 1 {
			t.Error("setup schema duplicated in history")
		}
		if strings.Contains(body, `"name":"bash"`) {
			t.Error("shell tool exposed")
		}
	}
	if strings.Contains(bodies[0], `"name":"write"`) {
		t.Error("inspection exposed writes")
	}
	if saves < 6 {
		t.Fatalf("missing message checkpoints: %d", saves)
	}
}

func TestPiCancellationAndCheckpointFailure(t *testing.T) {
	t.Run("cancel HTTP request", func(t *testing.T) {
		a := piFixture(t, func(w http.ResponseWriter, r *http.Request) {
			io.Copy(io.Discard, r.Body)
			select {
			case <-r.Context().Done():
			case <-time.After(2 * time.Second):
			}
		})
		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer cancel()
		_, err := Run(ctx, a, RunRequest{Dir: t.TempDir(), Prompt: "inspect", ReadOnly: true})
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("cancellation: %v", err)
		}
	})
	t.Run("failed checkpoint prevents request", func(t *testing.T) {
		a := piFixture(t, func(http.ResponseWriter, *http.Request) { t.Error("request after failed checkpoint") })
		_, err := Run(context.Background(), a, RunRequest{Dir: t.TempDir(), Prompt: "inspect", ReadOnly: true, SavePiState: func() error { return errors.New("disk full") }})
		if err == nil || !strings.Contains(err.Error(), "disk full") {
			t.Fatalf("checkpoint: %v", err)
		}
	})
}

func TestPiCredentialsAndModel(t *testing.T) {
	t.Setenv("OPENAI_API_KEY", "")
	t.Setenv("ANTHROPIC_API_KEY", "")
	for _, spec := range []string{"", "openai-codex/gpt-5", "openai/gpt-5", "anthropic/claude-sonnet-4-5"} {
		if _, err := NewPiAgent(spec); err == nil {
			t.Fatalf("accepted unavailable model %q", spec)
		}
	}
	a := piFixture(t, func(http.ResponseWriter, *http.Request) { t.Error("request with mismatched saved model") })
	_, err := Run(context.Background(), a, RunRequest{Dir: t.TempDir(), PiState: &PiState{Model: "anthropic/old-model"}})
	if err == nil || !strings.Contains(err.Error(), "--restart") {
		t.Fatalf("model mismatch: %v", err)
	}
}

func TestPiProviderErrorsDoNotLeakCredentials(t *testing.T) {
	a := piFixture(t, func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "rejected test-pi-secret", http.StatusUnauthorized)
	})
	state := &PiState{}
	var log bytes.Buffer
	_, err := Run(context.Background(), a, RunRequest{Dir: t.TempDir(), ReadOnly: true, PiState: state, Stdout: &log})
	data, _ := json.Marshal(state)
	if err == nil {
		t.Fatal("accepted authentication failure")
	}
	if strings.Contains(err.Error()+string(data)+log.String(), "test-pi-secret") {
		t.Fatal("credential leaked")
	}
}

func TestPiFileToolPolicy(t *testing.T) {
	root, outside := t.TempDir(), t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "user.txt"), []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(outside, "secret.txt"), []byte("private"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(root, "link")); err != nil {
		t.Fatal(err)
	}
	tools, err := piTools(root, false, []string{"user.txt"})
	if err != nil {
		t.Fatal(err)
	}
	for _, tool := range tools {
		for _, path := range []string{"../escape", filepath.Join(outside, "secret.txt"), "link/secret.txt", ".git/config", ".env", ".stack/secrets/key", ".stack/state/data", "packages/gen/env/src/web.ts"} {
			t.Run(tool.Name+"/"+path, func(t *testing.T) {
				_, err := tool.Execute(context.Background(), "test", map[string]any{"path": path, "content": "bad"}, nil)
				if err == nil {
					t.Fatalf("allowed %s %s", tool.Name, path)
				}
			})
		}
		if tool.Name == "write" {
			_, err := tool.Execute(context.Background(), "test", map[string]any{"path": "user.txt", "content": "bad"}, nil)
			if err == nil {
				t.Fatal("overwrote protected user file")
			}
		}
	}
}
