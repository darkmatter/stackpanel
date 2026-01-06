// Package server provides the HTTP/SSE server for the stackpanel agent.
package server

import (
	"fmt"
	"html/template"
	"net/http"
	"sync"

	"github.com/darkmatter/stackpanel/agent/internal/config"
	"github.com/darkmatter/stackpanel/agent/internal/project"
	sharedexec "github.com/darkmatter/stackpanel/packages/stackpanel-go/exec"
	"github.com/fsnotify/fsnotify"
	"github.com/rs/zerolog/log"
)

// Server is the main agent server.
type Server struct {
	config     *config.Config
	httpServer *http.Server
	exec       *sharedexec.Executor

	// Project manager for handling project selection and validation
	projectMgr *project.Manager

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
	// Initialize project manager
	projectMgr, err := project.NewManager(cfg.DataDir)
	if err != nil {
		return nil, fmt.Errorf("failed to create project manager: %w", err)
	}

	// Check if we have a current project from saved state
	if currentPath := projectMgr.CurrentProjectPath(); currentPath != "" {
		// Validate the saved project still exists and is valid
		if err := project.QuickValidate(currentPath); err != nil {
			log.Warn().
				Str("path", currentPath).
				Err(err).
				Msg("Saved project is no longer valid, clearing")
			_ = projectMgr.CloseProject()
		} else {
			// Use the saved project
			cfg.ProjectRoot = currentPath
			log.Info().
				Str("path", currentPath).
				Msg("Restored project from saved state")
		}
	}

	// Initialize executor (may have empty project root if no project selected)
	var exec *sharedexec.Executor
	if cfg.ProjectRoot != "" {
		exec, err = sharedexec.New(cfg.ProjectRoot, cfg.AllowedCommands)
		if err != nil {
			return nil, fmt.Errorf("failed to create executor: %w", err)
		}
		log.Info().
			Bool("in_devshell", exec.InDevshell()).
			Bool("has_devshell_env", exec.HasDevshellEnv()).
			Msg("Executor initialized with devshell support")
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
		projectMgr:     projectMgr,
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

	// Project management endpoints (some don't require a project to be open)
	mux.HandleFunc("/api/project/current", s.withCORS(s.requireAuth(s.handleProjectCurrent)))
	mux.HandleFunc("/api/project/list", s.withCORS(s.requireAuth(s.handleProjectList)))
	mux.HandleFunc("/api/project/open", s.withCORS(s.requireAuth(s.handleProjectOpen)))
	mux.HandleFunc("/api/project/close", s.withCORS(s.requireAuth(s.handleProjectClose)))
	mux.HandleFunc("/api/project/validate", s.withCORS(s.requireAuth(s.handleProjectValidate)))
	mux.HandleFunc("/api/project/remove", s.withCORS(s.requireAuth(s.handleProjectRemove)))

	// HTTP API (used by apps/web fallback client and by other tools)
	// These require a project to be open
	mux.HandleFunc("/api/exec", s.withCORS(s.requireAuth(s.requireProject(s.handleExec))))
	mux.HandleFunc("/api/nix/eval", s.withCORS(s.requireAuth(s.requireProject(s.handleNixEval))))
	mux.HandleFunc("/api/nix/generate", s.withCORS(s.requireAuth(s.requireProject(s.handleNixGenerate))))
	mux.HandleFunc("/api/nix/data", s.withCORS(s.requireAuth(s.requireProject(s.handleNixData))))
	mux.HandleFunc("/api/nix/data/list", s.withCORS(s.requireAuth(s.requireProject(s.handleNixDataList))))
	mux.HandleFunc("/api/files", s.withCORS(s.requireAuth(s.requireProject(s.handleFiles))))
	mux.HandleFunc("/api/secrets/set", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsSet))))

	// SSE endpoint for real-time config updates
	mux.HandleFunc("/api/events", s.withCORS(s.requireAuth(s.handleSSE)))

	// WebSocket API (legacy, prefer HTTP API + SSE)
	mux.HandleFunc("/ws", s.withCORS(s.requireAuth(s.requireProject(s.handleWS))))

	s.httpServer = &http.Server{
		Addr:    fmt.Sprintf("127.0.0.1:%d", cfg.Port),
		Handler: mux,
	}

	projectInfo := cfg.ProjectRoot
	if projectInfo == "" {
		projectInfo = "(no project selected)"
	}

	log.Info().
		Str("addr", s.httpServer.Addr).
		Str("project_root", projectInfo).
		Msg("Agent server configured (loopback only)")

	return s, nil
}

// Start begins serving requests and starts the config file watcher.
func (s *Server) Start() error {
	// Start watching config files for changes (only if we have a project)
	if s.config.ProjectRoot != "" {
		go s.watchConfigFiles()
	}

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

// requireProject is middleware that ensures a project is open before handling the request.
func (s *Server) requireProject(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.config.ProjectRoot == "" {
			s.writeAPI(w, http.StatusPreconditionRequired, map[string]any{
				"error":   "no_project",
				"message": "No project is currently open. Use /api/project/open to select a project.",
			})
			return
		}
		next(w, r)
	}
}

// reinitializeExecutor creates a new executor for the current project root.
// Called after changing projects.
func (s *Server) reinitializeExecutor() error {
	if s.config.ProjectRoot == "" {
		s.exec = nil
		return nil
	}

	exec, err := sharedexec.New(s.config.ProjectRoot, s.config.AllowedCommands)
	if err != nil {
		return fmt.Errorf("failed to create executor: %w", err)
	}

	s.exec = exec

	log.Info().
		Str("project_root", s.config.ProjectRoot).
		Bool("in_devshell", exec.InDevshell()).
		Bool("has_devshell_env", exec.HasDevshellEnv()).
		Msg("Executor reinitialized for new project")

	// Restart file watcher for new project
	go s.watchConfigFiles()

	return nil
}
