// ws.go implements a legacy multiplexed WebSocket API that predates the REST endpoints.
//
// Clients send JSON frames with a type field (e.g., "exec", "nix.eval", "secrets.write")
// and receive JSON responses with matching IDs. Each message type maps to the same
// logic as the corresponding REST handler. This is kept for backwards compatibility
// with older studio UI versions; new features should use REST/Connect-RPC instead.
package server

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gorilla/websocket"
	"github.com/rs/zerolog/log"
)

// wsUpgrader is shared across WebSocket endpoints (legacy WS + process-compose log streaming).
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
		// Secrets are now written to group YAML files via SOPS
		var req GroupSecretRequest
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			// Fall back to legacy format
			var legacyReq AgenixSecretRequest
			if err2 := json.Unmarshal(msg.Payload, &legacyReq); err2 != nil {
				return wsResponse{ID: msg.ID, Success: false, Error: "invalid secrets.write payload"}
			}
			req.Key = legacyReq.Key
			req.Value = legacyReq.Value
			req.Description = legacyReq.Description
			req.Group = "dev"
			if len(legacyReq.Environments) > 0 {
				req.Group = legacyReq.Environments[0]
			}
		}
		if strings.TrimSpace(req.Key) == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "key is required"}
		}
		if strings.TrimSpace(req.Group) == "" {
			req.Group = "dev"
		}
		safeGroup := sanitizeSecretID(req.Group)
		recipients, err := s.getGroupRecipients(safeGroup)
		if err != nil || len(recipients) == 0 {
			return wsResponse{ID: msg.ID, Success: false, Error: "no recipients found for group"}
		}
		secrets, err := s.readGroupSecrets(safeGroup)
		if err != nil {
			secrets = make(map[string]interface{})
		}
		secrets[req.Key] = req.Value
		if err := s.writeGroupSecrets(safeGroup, secrets, recipients); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		groupPath, _ := s.getGroupFilePath(safeGroup)
		relPath, _ := filepath.Rel(s.config.ProjectRoot, groupPath)
		return wsResponse{ID: msg.ID, Success: true, Data: GroupSecretResponse{
			Key:            req.Key,
			Group:          safeGroup,
			Path:           relPath,
			RecipientCount: len(recipients),
		}}

	case "secrets.read":
		// Read a secret from a group's SOPS file
		var req GroupSecretReadRequest
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			// Fall back to legacy format
			var legacyReq AgenixDecryptRequest
			if err2 := json.Unmarshal(msg.Payload, &legacyReq); err2 != nil {
				return wsResponse{ID: msg.ID, Success: false, Error: "invalid secrets.read payload"}
			}
			req.Key = legacyReq.ID
			req.Group = "dev"
		}
		if strings.TrimSpace(req.Key) == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "key is required"}
		}
		if strings.TrimSpace(req.Group) == "" {
			req.Group = "dev"
		}
		safeGroup := sanitizeSecretID(req.Group)
		groupSecrets, err := s.readGroupSecrets(safeGroup)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "failed to decrypt group secrets: " + err.Error()}
		}
		value, exists := groupSecrets[req.Key]
		if !exists {
			return wsResponse{ID: msg.ID, Success: false, Error: "secret not found in group"}
		}
		return wsResponse{ID: msg.ID, Success: true, Data: GroupSecretReadResponse{
			Key:   req.Key,
			Group: safeGroup,
			Value: fmt.Sprintf("%v", value),
		}}

	case "secrets.delete":
		var req struct {
			Key   string `json:"key"`
			ID    string `json:"id"`
			Group string `json:"group"`
		}
		if err := json.Unmarshal(msg.Payload, &req); err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "invalid secrets.delete payload"}
		}
		key := req.Key
		if key == "" {
			key = req.ID
		}
		if strings.TrimSpace(key) == "" {
			return wsResponse{ID: msg.ID, Success: false, Error: "key is required"}
		}
		group := req.Group
		if group == "" {
			group = "dev"
		}
		safeGroup := sanitizeSecretID(group)
		recipients, err := s.getGroupRecipients(safeGroup)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "failed to get recipients: " + err.Error()}
		}
		groupSecrets, err := s.readGroupSecrets(safeGroup)
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "failed to decrypt group secrets: " + err.Error()}
		}
		if _, exists := groupSecrets[key]; !exists {
			return wsResponse{ID: msg.ID, Success: false, Error: "secret not found in group"}
		}
		delete(groupSecrets, key)
		if len(groupSecrets) == 0 {
			groupPath, _ := s.getGroupFilePath(safeGroup)
			_ = os.Remove(groupPath)
		} else {
			if err := s.writeGroupSecrets(safeGroup, groupSecrets, recipients); err != nil {
				return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
			}
		}
		_ = s.removeVariableEntry(key)
		return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{"deleted": true, "key": key, "group": safeGroup}}

	case "secrets.list":
		// List all groups and their keys
		groupsDir, err := s.getGroupsDir()
		if err != nil {
			return wsResponse{ID: msg.ID, Success: false, Error: "failed to get groups directory: " + err.Error()}
		}
		entries, err := os.ReadDir(groupsDir)
		if err != nil {
			if os.IsNotExist(err) {
				return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{"groups": map[string][]string{}}}
			}
			return wsResponse{ID: msg.ID, Success: false, Error: err.Error()}
		}
		groups := make(map[string][]string)
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".yaml") {
				continue
			}
			groupName := strings.TrimSuffix(entry.Name(), ".yaml")
			groupSecrets, err := s.readGroupSecrets(groupName)
			if err != nil {
				groups[groupName] = []string{}
				continue
			}
			keys := make([]string, 0, len(groupSecrets))
			for k := range groupSecrets {
				keys = append(keys, k)
			}
			groups[groupName] = keys
		}
		return wsResponse{ID: msg.ID, Success: true, Data: map[string]any{"groups": groups}}

	default:
		return wsResponse{ID: msg.ID, Success: false, Error: "unknown message type"}
	}
}
