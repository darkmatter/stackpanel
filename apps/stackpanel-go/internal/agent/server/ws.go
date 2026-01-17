package server

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gorilla/websocket"
	"github.com/rs/zerolog/log"
)

// -----------------------------
// WebSocket handler
// -----------------------------

var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  32 * 1024,
	WriteBufferSize: 32 * 1024,
	// Origin is validated in requireAuth + isOriginAllowed, but gorilla requires a CheckOrigin too.
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		// Require Origin for browser-based WebSocket connections.
		return origin != ""
	},
}

type wsMessage struct {
	ID      string          `json:"id"`
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

type wsResponse struct {
	ID      string `json:"id"`
	Success bool   `json:"success"`
	Data    any    `json:"data,omitempty"`
	Error   string `json:"error,omitempty"`
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Warn().Err(err).Msg("websocket upgrade failed")
		return
	}
	defer conn.Close()

	for {
		_, b, err := conn.ReadMessage()
		if err != nil {
			return
		}

		var msg wsMessage
		if err := json.Unmarshal(b, &msg); err != nil {
			_ = conn.WriteJSON(wsResponse{ID: "0", Success: false, Error: "invalid message"})
			continue
		}

		resp := s.handleWSMessage(msg)
		_ = conn.WriteJSON(resp)
	}
}

func (s *Server) handleWSMessage(msg wsMessage) wsResponse {
	switch msg.Type {
	case "exec":
		var req execRequest
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid exec payload"}
		}
		req.Command = strings.TrimSpace(req.Command)
		if req.Command == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "command is required"}
		}
		if strings.Contains(req.Command, " ") || strings.Contains(req.Command, "\t") {
			return wsResponse{ID: msg.ID, Success: false, Error: "command must not contain spaces"}
		}

		cwd := s.config.ProjectRoot
		if strings.TrimSpace(req.Cwd) != "" {
			abs, err := safeJoin(s.config.ProjectRoot, req.Cwd)
			if err != nil {
				return wsResponse{ID: msg.ID, Success: false, Error: "invalid cwd"}
			}
			cwd = abs
		}

		res, err := s.exec.RunWithOptions(req.Command, cwd, req.Env, req.Args...)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		return wsResponse{ID: msg.ID, Success: true, Data: res}

	case "nix.eval":
		var req nixEvalRequest
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid nix.eval payload"}
		}
		expr := strings.TrimSpace(req.Expression)
		if expr == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "expression is required"}
		}

		args := buildNixEvalArgs(expr)
		res, err := s.exec.RunNix(args...)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		if res.ExitCode != 0 {
			return wsResponse{ID: msg.ID, Success: false, Error: strings.TrimSpace(res.Stderr)}
		}

		var v any
		if err := json.Unmarshal([]byte(res.Stdout), &v); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "failed to parse nix eval output as JSON"}
		}
		return wsResponse{ID: msg.ID, Success: true, Data: v}

	case "nix.generate":
		res, err := s.exec.RunNix("run", ".#generate")
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		out := res.Stdout
		if strings.TrimSpace(res.Stderr) != "" {
			out += res.Stderr
		}
		return wsResponse{
			ID:      msg.ID,
			Success: true,
			Data: map[string]any{
				"success": res.ExitCode == 0,
				"output":  out,
				"error":   strings.TrimSpace(res.Stderr),
			},
		}

	case "file.read":
		var req struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid file.read payload"}
		}
		path := strings.TrimSpace(req.Path)
		if path == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "path is required"}
		}
		abs, err := safeJoin(s.config.ProjectRoot, path)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid path"}
		}

		b, err := os.ReadFile(abs)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{
					"path":    path,
					"content": "",
					"exists":  false,
				}}
			}
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}

		return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{
			"path":    path,
			"content": string(b),
			"exists":  true,
		}}

	case "file.write":
		var req fileWriteRequest
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid file.write payload"}
		}
		req.Path = strings.TrimSpace(req.Path)
		if req.Path == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "path is required"}
		}

		abs, err := safeJoin(s.config.ProjectRoot, req.Path)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid path"}
		}

		if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		if err := os.WriteFile(abs, []byte(req.Content), 0o644); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}

		return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{"ok": true}}

	case "secrets.set":
		var req secretSetRequest
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid secrets.set payload"}
		}
		env, err := normalizeEnv(req.Env)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		key := strings.TrimSpace(req.Key)
		if key == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "key is required"}
		}
		path, err := s.setSopsSecret(env, key, req.Value)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{"path": path}}

	case "secrets.write":
		var req AgenixSecretRequest
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid secrets.write payload"}
		}
		if strings.TrimSpace(req.ID) == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "id is required"}
		}
		if strings.TrimSpace(req.Key) == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "key is required"}
		}
		safeID := sanitizeSecretID(req.ID)
		if safeID == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid secret id"}
		}
		recipients, err := s.getAgenixRecipients(req.Environments)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		if len(recipients) == 0 {
			return wsResponse{ID: msg.ID, Success: false, Error: "no recipients found"}
		}
		secretsDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "vars")
		if err := os.MkdirAll(secretsDir, 0o755); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "failed to create secrets directory"}
		}
		agePath := filepath.Join(secretsDir, safeID+".age")
		if err := s.writeAgeSecret(agePath, req.Value, recipients); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		_ = s.updateVariableEntry(req.ID, req.Key, req.Description, req.Environments)
		_ = s.updateSecretsNix()
		relPath, _ := filepath.Rel(s.config.ProjectRoot, agePath)
		return wsResponse{ID: msg.ID, Success: true, Data: AgenixSecretResponse{
			ID:       req.ID,
			Path:     relPath,
			AgePath:  agePath,
			KeyCount: len(recipients),
		}}

	case "secrets.read":
		var req AgenixDecryptRequest
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid secrets.read payload"}
		}
		if strings.TrimSpace(req.ID) == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "id is required"}
		}
		safeID := sanitizeSecretID(req.ID)
		if safeID == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid secret id"}
		}
		agePath := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "vars", safeID+".age")
		if _, err := os.Stat(agePath); os.IsNotExist(err) {
			return wsResponse{ID: msg.ID, Success: false, Error: "secret not found"}
		}
		identityPath := req.IdentityPath
		if identityPath == "" {
			identityPath = s.findAgeIdentity()
		}
		if identityPath == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "no identity file found - specify identityPath or create ~/.config/age/key.txt"}
		}
		if strings.HasPrefix(identityPath, "~/") {
			home, _ := os.UserHomeDir()
			identityPath = filepath.Join(home, identityPath[2:])
		}
		value, err := s.decryptAgeSecret(agePath, identityPath)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "failed to decrypt: " + err.Error()}
		}
		return wsResponse{ID: msg.ID, Success: true, Data: AgenixDecryptResponse{ID: req.ID, Value: value}}

	case "secrets.delete":
		var req struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid secrets.delete payload"}
		}
		if strings.TrimSpace(req.ID) == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "id is required"}
		}
		safeID := sanitizeSecretID(req.ID)
		if safeID == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid secret id"}
		}
		agePath := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "vars", safeID+".age")
		if err := os.Remove(agePath); err != nil && !os.IsNotExist(err) {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		_ = s.removeVariableEntry(req.ID)
		_ = s.updateSecretsNix()
		return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{"deleted": true, "id": req.ID}}

	case "secrets.list":
		secretsDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "secrets", "vars")
		entries, err := os.ReadDir(secretsDir)
		if err != nil {
			if os.IsNotExist(err) {
				return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{"secrets": []string{}}}
			}
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		var secrets []map[string]any
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".age") {
				continue
			}
			id := strings.TrimSuffix(entry.Name(), ".age")
			info, _ := entry.Info()
			secret := map[string]any{"id": id, "file": entry.Name()}
			if info != nil {
				secret["modTime"] = info.ModTime().Unix()
				secret["size"] = info.Size()
			}
			secrets = append(secrets, secret)
		}
		return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{"secrets": secrets}}

	default:
		return wsResponse{ID: msg.ID, Success: false, Error: "unknown message type"}
	}
}
