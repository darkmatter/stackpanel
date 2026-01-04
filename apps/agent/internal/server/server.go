// Package server provides the HTTP/SSE server for the stackpanel agent.
package server

import (
	"fmt"
	"html/template"
	"net/http"
	"sync"

	"github.com/darkmatter/stackpanel/agent/internal/config"
	sharedexec "github.com/darkmatter/stackpanel/packages/stackpanel-go/exec"
	"github.com/fsnotify/fsnotify"
	"github.com/rs/zerolog/log"
)

// Server is the main agent server.
type Server struct {
	config     *config.Config
	httpServer *http.Server
	exec       *sharedexec.Executor

	// pairToken is a per-process token used by the hosted UI to authenticate.
	// It is only delivered to an allowed origin via the /pair handshake page.
	pairToken    string
	pairTemplate *template.Template

	// SSE subscribers for config change notifications
	sseSubscribers   map[chan SSEEvent]struct{}
	sseSubscribersMu sync.RWMutex

	// File watcher for config changes
	watcher *fsnotify.Watcher
}

// New creates a new server instance.
func New(cfg *config.Config) (*Server, error) {
	exec, err := sharedexec.New(cfg.ProjectRoot, cfg.AllowedCommands)
	if err != nil {
		return nil, err
	}

	pairTmpl, err := template.ParseFS(templatesFS, "templates/pair.html")
	if err != nil {
		return nil, fmt.Errorf("failed to parse pair template: %w", err)
	}

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, fmt.Errorf("failed to create file watcher: %w", err)
	}

	s := &Server{
		config:         cfg,
		exec:           exec,
		pairToken:      generateToken(32),
		pairTemplate:   pairTmpl,
		sseSubscribers: make(map[chan SSEEvent]struct{}),
		watcher:        watcher,
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
	mux.HandleFunc("/api/nix/data", s.withCORS(s.requireAuth(s.handleNixData)))
	mux.HandleFunc("/api/nix/data/list", s.withCORS(s.requireAuth(s.handleNixDataList)))
	mux.HandleFunc("/api/files", s.withCORS(s.requireAuth(s.handleFiles)))
	mux.HandleFunc("/api/secrets/set", s.withCORS(s.requireAuth(s.handleSecretsSet)))

	// SSE endpoint for real-time config updates
	mux.HandleFunc("/api/events", s.withCORS(s.requireAuth(s.handleSSE)))

	// WebSocket API (legacy, prefer HTTP API + SSE)
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

// Start begins serving requests and starts the config file watcher.
func (s *Server) Start() error {
	// Start watching config files for changes
	go s.watchConfigFiles()

	return s.httpServer.ListenAndServe()
}

// Stop gracefully shuts down the server.
func (s *Server) Stop() {
	if s.watcher != nil {
		_ = s.watcher.Close()
	}
	if s.httpServer != nil {
		_ = s.httpServer.Close()
	}
}
