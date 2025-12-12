package server

import "encoding/json"

// Message is the base WebSocket message format
type Message struct {
	ID      string          `json:"id"`
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

// Response is the WebSocket response format
type Response struct {
	ID      string      `json:"id"`
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

// ExecRequest executes a command
type ExecRequest struct {
	Command string   `json:"command"`
	Args    []string `json:"args,omitempty"`
	Cwd     string   `json:"cwd,omitempty"`
	Env     []string `json:"env,omitempty"`
}

// ExecResult is the result of command execution
type ExecResult struct {
	ExitCode int    `json:"exit_code"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
}

// NixEvalRequest evaluates a Nix expression
type NixEvalRequest struct {
	Expression string `json:"expression"`
	File       string `json:"file,omitempty"`
}

// FileRequest reads a file
type FileRequest struct {
	Path string `json:"path"`
}

// FileWriteRequest writes a file
type FileWriteRequest struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

// FileContent is the content of a file
type FileContent struct {
	Path    string `json:"path"`
	Content string `json:"content"`
	Exists  bool   `json:"exists"`
}
