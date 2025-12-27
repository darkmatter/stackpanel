// Package server provides the HTTP/WebSocket server for the stackpanel agent.
package server

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/agent/internal/config"
	"github.com/darkmatter/stackpanel/agent/internal/executor"
	"github.com/gorilla/websocket"
	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// Server is the main agent server.
type Server struct {
	config     *config.Config
	httpServer *http.Server
	exec       *executor.Executor

	// pairToken is a per-process token used by the hosted UI to authenticate.
	// It is only delivered to an allowed origin via the /pair handshake page.
	pairToken    string
	pairTemplate *template.Template
}

// New creates a new server instance.
func New(cfg *config.Config) (*Server, error) {
	exec, err := executor.New(cfg.ProjectRoot, cfg.AllowedCommands)
	if err != nil {
		return nil, err
	}

	pairTmpl, err := template.ParseFS(templatesFS, "templates/pair.html")
	if err != nil {
		return nil, fmt.Errorf("failed to parse pair template: %w", err)
	}

	s := &Server{
		config:       cfg,
		exec:         exec,
		pairToken:    generateToken(32),
		pairTemplate: pairTmpl,
	}

	mux := http.NewServeMux()
	// Public endpoints (still CORS-enabled so the web UI can health-check from a different origin)
	mux.HandleFunc("/health", s.withCORS(s.handleHealth))
	mux.HandleFunc("/status", s.withCORS(s.handleStatus))
	mux.HandleFunc("/pair", s.handlePair)

	// HTTP API (used by apps/web fallback client and by other tools)
	mux.HandleFunc("/api/exec", s.withCORS(s.requireAuth(s.handleExec)))
	mux.HandleFunc("/api/nix/eval", s.withCORS(s.requireAuth(s.handleNixEval)))
	mux.HandleFunc("/api/nix/generate", s.withCORS(s.requireAuth(s.handleNixGenerate)))
	mux.HandleFunc("/api/files", s.withCORS(s.requireAuth(s.handleFiles)))
	mux.HandleFunc("/api/secrets/set", s.withCORS(s.requireAuth(s.handleSecretsSet)))

	// WebSocket API (primary UI transport)
	mux.HandleFunc("/ws", s.withCORS(s.requireAuth(s.handleWS)))

	s.httpServer = &http.Server{
		Addr:    fmt.Sprintf("127.0.0.1:%d", cfg.Port),
		Handler: mux,
	}

	log.Info().
		Str("addr", s.httpServer.Addr).
		Str("project_root", cfg.ProjectRoot).
		Msg("Agent server configured (loopback only)")

	return s, nil
}

// Start begins serving requests.
func (s *Server) Start() error {
	return s.httpServer.ListenAndServe()
}

// Stop gracefully shuts down the server.
func (s *Server) Stop() {
	if s.httpServer != nil {
		_ = s.httpServer.Close()
	}
}

// -----------------------------
// HTTP endpoints
// -----------------------------

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	s.writeJSON(w, http.StatusOK, map[string]any{
		"status":       "ok",
		"project_root": s.config.ProjectRoot,
	})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	s.writeJSON(w, http.StatusOK, map[string]any{
		"status": "running",
	})
}

// -----------------------------
// Security / CORS helpers
// -----------------------------

func (s *Server) withCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && s.isOriginAllowed(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "content-type, authorization, x-stackpanel-token")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			// Private Network Access (PNA) preflight support (Chrome)
			w.Header().Set("Access-Control-Allow-Private-Network", "true")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next(w, r)
	}
}

func (s *Server) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && !s.isOriginAllowed(origin) {
			s.writeAPIError(w, http.StatusForbidden, "origin not allowed")
			return
		}

		if !s.hasValidToken(r) {
			s.writeAPIError(w, http.StatusUnauthorized, "missing or invalid token")
			return
		}

		next(w, r)
	}
}

func (s *Server) hasValidToken(r *http.Request) bool {
	if token := strings.TrimSpace(r.Header.Get("X-Stackpanel-Token")); token != "" {
		return s.isValidToken(token)
	}

	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(auth), "bearer ") {
		return s.isValidToken(strings.TrimSpace(auth[7:]))
	}

	// Browser WebSocket connections can't set custom headers, so we also allow
	// providing the token via the query string, e.g. /ws?token=...
	if token := strings.TrimSpace(r.URL.Query().Get("token")); token != "" {
		return s.isValidToken(token)
	}

	return false
}

func (s *Server) isValidToken(token string) bool {
	if token == "" {
		return false
	}
	if token == s.pairToken {
		return true
	}
	if s.config.AuthToken != "" && token == s.config.AuthToken {
		return true
	}
	return false
}

func (s *Server) isOriginAllowed(origin string) bool {
	// Always allow loopback + *.localhost (Caddy/dev domains).
	if u, err := url.Parse(origin); err == nil {
		host := strings.ToLower(u.Hostname())
		if host == "localhost" || host == "127.0.0.1" || host == "::1" || strings.HasSuffix(host, ".localhost") {
			return true
		}
	}

	// If configured, enforce allowlist.
	if len(s.config.AllowedOrigins) > 0 {
		for _, allowed := range s.config.AllowedOrigins {
			if origin == allowed {
				return true
			}
		}
		return false
	}

	// Default allowlist for hosted UI.
	return origin == "https://stackpanel.com" || origin == "https://stackpanel.dev"
}

// -----------------------------
// Pairing UI
// -----------------------------

// pairTemplateData holds the data for the pair.html template.
type pairTemplateData struct {
	ProjectRoot  string
	TargetOrigin template.JS
	Token        template.JS
}

func (s *Server) handlePair(w http.ResponseWriter, r *http.Request) {
	origin := s.getPairOrigin(r)
	if origin == "" || !s.isOriginAllowed(origin) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte("Pairing not allowed from this origin. Open Stackpanel first."))
		return
	}

	data := pairTemplateData{
		ProjectRoot:  s.config.ProjectRoot,
		TargetOrigin: template.JS(fmt.Sprintf("%q", origin)),
		Token:        template.JS(fmt.Sprintf("%q", s.pairToken)),
	}

	var buf bytes.Buffer
	if err := s.pairTemplate.Execute(&buf, data); err != nil {
		log.Error().Err(err).Msg("failed to render pair template")
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(buf.Bytes())
}

func (s *Server) getPairOrigin(r *http.Request) string {
	if q := strings.TrimSpace(r.URL.Query().Get("origin")); q != "" {
		origin, ok := normalizeOrigin(q)
		if ok {
			return origin
		}
		return ""
	}

	ref := strings.TrimSpace(r.Referer())
	if ref == "" {
		return ""
	}
	u, err := url.Parse(ref)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host
}

// -----------------------------
// API handlers
// -----------------------------

type apiResponse struct {
	Success bool `json:"success"`
	Data    any  `json:"data,omitempty"`
	Error   any  `json:"error,omitempty"`
}

type execRequest struct {
	Command string   `json:"command"`
	Args    []string `json:"args,omitempty"`
	Cwd     string   `json:"cwd,omitempty"`
	Env     []string `json:"env,omitempty"`
}

func (s *Server) handleExec(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req execRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	req.Command = strings.TrimSpace(req.Command)
	if req.Command == "" {
		s.writeAPIError(w, http.StatusBadRequest, "command is required")
		return
	}
	if strings.Contains(req.Command, " ") || strings.Contains(req.Command, "\t") {
		s.writeAPIError(w, http.StatusBadRequest, "command must not contain spaces")
		return
	}

	cwd := s.config.ProjectRoot
	if strings.TrimSpace(req.Cwd) != "" {
		abs, err := safeJoin(s.config.ProjectRoot, req.Cwd)
		if err != nil {
			s.writeAPIError(w, http.StatusBadRequest, "invalid cwd")
			return
		}
		cwd = abs
	}

	res, err := s.exec.RunWithOptions(req.Command, cwd, req.Env, req.Args...)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	// Note: command exit codes are returned in the payload; outer success indicates request success.
	s.writeAPI(w, http.StatusOK, res)
}

type nixEvalRequest struct {
	Expression string `json:"expression"`
	File       string `json:"file,omitempty"`
}

func (s *Server) handleNixEval(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req nixEvalRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	expr := strings.TrimSpace(req.Expression)
	if expr == "" {
		s.writeAPIError(w, http.StatusBadRequest, "expression is required")
		return
	}

	args := buildNixEvalArgs(expr)

	res, err := s.exec.RunNix(args...)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if res.ExitCode != 0 {
		s.writeAPIError(w, http.StatusBadRequest, strings.TrimSpace(res.Stderr))
		return
	}

	var v any
	if err := json.Unmarshal([]byte(res.Stdout), &v); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse nix eval output as JSON")
		return
	}

	s.writeAPI(w, http.StatusOK, v)
}

func (s *Server) handleNixGenerate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	res, err := s.exec.RunNix("run", ".#generate")
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	out := res.Stdout
	if strings.TrimSpace(res.Stderr) != "" {
		out += res.Stderr
	}

	payload := map[string]any{
		"success": res.ExitCode == 0,
		"output":  out,
	}
	if res.ExitCode != 0 {
		payload["error"] = strings.TrimSpace(res.Stderr)
	}

	s.writeAPI(w, http.StatusOK, payload)
}

type fileWriteRequest struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

func (s *Server) handleFiles(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		path := strings.TrimSpace(r.URL.Query().Get("path"))
		if path == "" {
			s.writeAPIError(w, http.StatusBadRequest, "path is required")
			return
		}
		abs, err := safeJoin(s.config.ProjectRoot, path)
		if err != nil {
			s.writeAPIError(w, http.StatusBadRequest, "invalid path")
			return
		}

		b, err := os.ReadFile(abs)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				s.writeAPI(w, http.StatusOK, map[string]any{
					"path":    path,
					"content": "",
					"exists":  false,
				})
				return
			}
			s.writeAPIError(w, http.StatusInternalServerError, err.Error())
			return
		}

		s.writeAPI(w, http.StatusOK, map[string]any{
			"path":    path,
			"content": string(b),
			"exists":  true,
		})

	case http.MethodPost:
		var req fileWriteRequest
		if err := s.readJSON(r.Body, &req); err != nil {
			s.writeAPIError(w, http.StatusBadRequest, err.Error())
			return
		}

		req.Path = strings.TrimSpace(req.Path)
		if req.Path == "" {
			s.writeAPIError(w, http.StatusBadRequest, "path is required")
			return
		}

		abs, err := safeJoin(s.config.ProjectRoot, req.Path)
		if err != nil {
			s.writeAPIError(w, http.StatusBadRequest, "invalid path")
			return
		}

		if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, err.Error())
			return
		}
		if err := os.WriteFile(abs, []byte(req.Content), 0o644); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, err.Error())
			return
		}

		s.writeAPI(w, http.StatusOK, map[string]any{"ok": true})

	default:
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

type secretSetRequest struct {
	Env   string `json:"env"`
	Key   string `json:"key"`
	Value string `json:"value"`
}

func (s *Server) handleSecretsSet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req secretSetRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	env, err := normalizeEnv(req.Env)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	key := strings.TrimSpace(req.Key)
	if key == "" {
		s.writeAPIError(w, http.StatusBadRequest, "key is required")
		return
	}

	path, err := s.setSopsSecret(env, key, req.Value)
	if err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{"path": path})
}

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

	default:
		return wsResponse{ID: msg.ID, Success: false, Error: "unknown message type"}
	}
}

// -----------------------------
// Small helpers
// -----------------------------

func (s *Server) writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *Server) writeAPI(w http.ResponseWriter, status int, data any) {
	s.writeJSON(w, status, apiResponse{Success: true, Data: data})
}

func (s *Server) writeAPIError(w http.ResponseWriter, status int, message string) {
	s.writeJSON(w, status, apiResponse{Success: false, Error: message})
}

func (s *Server) readJSON(body io.ReadCloser, v any) error {
	defer body.Close()
	dec := json.NewDecoder(io.LimitReader(body, 2<<20)) // 2 MiB
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return fmt.Errorf("invalid json: %w", err)
	}
	return nil
}

func generateToken(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err == nil {
		return base64.RawURLEncoding.EncodeToString(b)
	}
	// Extremely unlikely, but ensure we still generate something.
	fallback := []byte(fmt.Sprintf("stackpanel-%d", time.Now().UnixNano()))
	return base64.RawURLEncoding.EncodeToString(fallback)
}

func normalizeOrigin(raw string) (string, bool) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return "", false
	}
	return u.Scheme + "://" + u.Host, true
}

func safeJoin(root string, rel string) (string, error) {
	rel = strings.TrimSpace(rel)
	if rel == "" {
		return "", errors.New("empty path")
	}
	if filepath.IsAbs(rel) {
		return "", errors.New("absolute paths not allowed")
	}
	clean := filepath.Clean(rel)
	if clean == "." {
		return root, nil
	}
	if clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
		return "", errors.New("path escapes project root")
	}
	full := filepath.Join(root, clean)
	rel2, err := filepath.Rel(root, full)
	if err != nil {
		return "", err
	}
	if rel2 == ".." || strings.HasPrefix(rel2, ".."+string(os.PathSeparator)) {
		return "", errors.New("path escapes project root")
	}
	return full, nil
}

func buildNixEvalArgs(expression string) []string {
	// Heuristic:
	// - If expression already includes a flake ref (#), use it as-is.
	// - Otherwise treat it as an attr path on the current flake.
	// - If it looks like a raw nix expression, use --expr.
	expr := strings.TrimSpace(expression)

	if looksLikeNixExpr(expr) {
		return []string{"eval", "--json", "--expr", expr}
	}

	if strings.Contains(expr, "#") {
		return []string{"eval", "--json", expr}
	}

	return []string{"eval", "--json", ".#" + expr}
}

func looksLikeNixExpr(s string) bool {
	// Very small heuristic: whitespace or obvious expression tokens.
	if strings.ContainsAny(s, " \t\n") {
		return true
	}
	return strings.HasPrefix(s, "{") || strings.HasPrefix(s, "(") || strings.HasPrefix(s, "let")
}

func normalizeEnv(env string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(env)) {
	case "dev", "development":
		return "dev", nil
	case "staging":
		return "staging", nil
	case "prod", "production":
		return "prod", nil
	default:
		return "", fmt.Errorf("invalid env: %s", env)
	}
}

type secretsUser struct {
	Pubkey string `yaml:"pubkey"`
	Github string `yaml:"github,omitempty"`
	Admin  bool   `yaml:"admin,omitempty"`
}

func (s *Server) setSopsSecret(env string, key string, value string) (string, error) {
	usersPath, err := safeJoin(s.config.ProjectRoot, ".stackpanel/secrets/users.yaml")
	if err != nil {
		return "", err
	}
	usersBytes, err := os.ReadFile(usersPath)
	if err != nil {
		return "", fmt.Errorf("failed to read users.yaml: %w", err)
	}

	users := map[string]secretsUser{}
	if err := yaml.Unmarshal(usersBytes, &users); err != nil {
		return "", fmt.Errorf("failed to parse users.yaml: %w", err)
	}

	var recipients []string
	for _, u := range users {
		if strings.TrimSpace(u.Pubkey) != "" {
			recipients = append(recipients, strings.TrimSpace(u.Pubkey))
		}
	}
	if len(recipients) == 0 {
		return "", errors.New("no recipients found in .stackpanel/secrets/users.yaml")
	}

	secretsRel := fmt.Sprintf(".stackpanel/secrets/%s.yaml", env)
	secretsPath, err := safeJoin(s.config.ProjectRoot, secretsRel)
	if err != nil {
		return "", err
	}

	plain := map[string]any{}
	if _, err := os.ReadFile(secretsPath); err == nil {
		// Decrypt existing secrets file.
		res, execErr := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, "--decrypt", secretsRel)
		if execErr != nil {
			return "", execErr
		}
		if res.ExitCode != 0 {
			return "", fmt.Errorf("sops decrypt failed: %s", strings.TrimSpace(res.Stderr))
		}
		if err := yaml.Unmarshal([]byte(res.Stdout), &plain); err != nil {
			return "", fmt.Errorf("failed to parse decrypted secrets yaml: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}

	plain[key] = value
	plainBytes, err := yaml.Marshal(plain)
	if err != nil {
		return "", fmt.Errorf("failed to marshal secrets yaml: %w", err)
	}

	tmp, err := os.CreateTemp("", "stackpanel-secrets-*.yaml")
	if err != nil {
		return "", err
	}
	tmpPath := tmp.Name()
	_ = tmp.Close()
	defer os.Remove(tmpPath)

	if err := os.WriteFile(tmpPath, plainBytes, 0o600); err != nil {
		return "", err
	}

	// Encrypt with SOPS using explicit recipients (so we don't rely on .sops.yaml).
	args := []string{"--encrypt", "--input-type", "yaml", "--output-type", "yaml"}
	for _, r := range recipients {
		args = append(args, "--age", r)
	}
	args = append(args, tmpPath)

	enc, execErr := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, args...)
	if execErr != nil {
		return "", execErr
	}
	if enc.ExitCode != 0 {
		return "", fmt.Errorf("sops encrypt failed: %s", strings.TrimSpace(enc.Stderr))
	}

	if err := os.MkdirAll(filepath.Dir(secretsPath), 0o755); err != nil {
		return "", err
	}
	if err := os.WriteFile(secretsPath, []byte(enc.Stdout), 0o600); err != nil {
		return "", err
	}

	return secretsRel, nil
}


