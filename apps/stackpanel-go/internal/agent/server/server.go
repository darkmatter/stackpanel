// Package server provides the HTTP/SSE server for the stackpanel agent.
package server

import (
	"fmt"
	"html/template"
	"net/http"
	"sync"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
	sharedexec "github.com/darkmatter/stackpanel/stackpanel-go/pkg/exec"
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

	// jwtManager handles JWT token generation and validation
	jwtManager   *JWTManager
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

	// Try to auto-detect and register current project if none is set
	// This happens when running `stackpanel agent` from within a project directory
	if cfg.ProjectRoot == "" {
		if proj, err := projectMgr.AutoRegister(); err != nil {
			log.Warn().Err(err).Msg("Failed to auto-register project")
		} else if proj != nil {
			cfg.ProjectRoot = proj.Path
			log.Info().
				Str("path", proj.Path).
				Str("name", proj.Name).
				Msg("Auto-registered current project")
		}
	} else {
		// ProjectRoot was set from environment, register it with the project manager
		if proj, err := projectMgr.OpenProject(cfg.ProjectRoot); err != nil {
			log.Warn().
				Str("path", cfg.ProjectRoot).
				Err(err).
				Msg("Failed to register project from environment")
		} else {
			log.Info().
				Str("path", proj.Path).
				Str("name", proj.Name).
				Msg("Registered project from environment")
		}
	}

	// Check if we have a current project from saved state (if not auto-detected)
	if cfg.ProjectRoot == "" {
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

	// Initialize JWT manager for token auth
	jwtMgr, err := NewJWTManager()
	if err != nil {
		return nil, fmt.Errorf("failed to create JWT manager: %w", err)
	}

	s := &Server{
		config:         cfg,
		exec:           exec,
		projectMgr:     projectMgr,
		jwtManager:     jwtMgr,
		pairTemplate:   pairTmpl,
		sseSubscribers: make(map[chan SSEEvent]struct{}),
		watcher:        watcher,
	}

	mux := http.NewServeMux()

	// Public endpoints (still CORS-enabled so the web UI can health-check from a different origin)
	mux.HandleFunc("/health", s.withCORS(s.handleHealth))
	mux.HandleFunc("/status", s.withCORS(s.handleStatus))
	mux.HandleFunc("/pair", s.handlePair)

	// Token validation endpoint (requires auth but no project)
	mux.HandleFunc("/api/auth/validate", s.withCORS(s.requireAuth(s.handleValidateToken)))

	// Project management endpoints - list and current are public for UI discovery
	mux.HandleFunc("/api/project/current", s.withCORS(s.handleProjectCurrent))
	mux.HandleFunc("/api/project/list", s.withCORS(s.handleProjectList))
	// These require auth since they modify state
	mux.HandleFunc("/api/project/open", s.withCORS(s.requireAuth(s.handleProjectOpen)))
	mux.HandleFunc("/api/project/close", s.withCORS(s.requireAuth(s.handleProjectClose)))
	mux.HandleFunc("/api/project/validate", s.withCORS(s.requireAuth(s.handleProjectValidate)))
	mux.HandleFunc("/api/project/remove", s.withCORS(s.requireAuth(s.handleProjectRemove)))

	// HTTP API (used by apps/web fallback client and by other tools)
	// These require a project to be open
	mux.HandleFunc("/api/exec", s.withCORS(s.requireAuth(s.requireProject(s.handleExec))))
	mux.HandleFunc("/api/nix/eval", s.withCORS(s.requireAuth(s.requireProject(s.handleNixEval))))
	mux.HandleFunc("/api/nix/generate", s.withCORS(s.requireAuth(s.requireProject(s.handleNixGenerate))))
	mux.HandleFunc("/api/nix/ui/runtime", s.withCORS(s.requireAuth(s.requireProject(s.handleNixUIRuntime))))
	mux.HandleFunc("/api/nix/ui/extensions", s.withCORS(s.requireAuth(s.requireProject(s.handleNixUIExtensions))))
	mux.HandleFunc("/api/nix/config", s.withCORS(s.requireAuth(s.requireProject(s.handleNixConfig))))
	mux.HandleFunc("/api/nix/files", s.withCORS(s.requireAuth(s.requireProject(s.handleNixFiles))))
	mux.HandleFunc("/api/nix/data", s.withCORS(s.requireAuth(s.requireProject(s.handleNixData))))
	mux.HandleFunc("/api/nix/data/list", s.withCORS(s.requireAuth(s.requireProject(s.handleNixDataList))))
	mux.HandleFunc("/api/files", s.withCORS(s.requireAuth(s.requireProject(s.handleFiles))))
	mux.HandleFunc("/api/secrets/set", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsSet))))

	// Security status endpoints (AWS session and certificate status)
	mux.HandleFunc("/api/security/status", s.withCORS(s.requireAuth(s.handleSecurityStatus)))
	mux.HandleFunc("/api/security/aws", s.withCORS(s.requireAuth(s.handleAWSStatus)))
	mux.HandleFunc("/api/security/certificate", s.withCORS(s.requireAuth(s.handleCertificateStatus)))

	// Nixpkgs package search and installed packages
	mux.HandleFunc("/api/nixpkgs/search", s.withCORS(s.requireAuth(s.handleNixpkgsSearch)))
	mux.HandleFunc("/api/nixpkgs/installed", s.withCORS(s.requireAuth(s.handleInstalledPackages)))
	mux.HandleFunc("/api/nixpkgs/meta", s.withCORS(s.requireAuth(s.handleNixpkgsPackageMeta)))

	// SSE endpoint for real-time config updates
	mux.HandleFunc("/api/events", s.withCORS(s.requireAuth(s.handleSSE)))

	// WebSocket API (legacy, prefer HTTP API + SSE)
	mux.HandleFunc("/ws", s.withCORS(s.requireAuth(s.requireProject(s.handleWS))))

	s.httpServer = &http.Server{
		Addr:    fmt.Sprintf("%s:%d", cfg.BindAddress, cfg.Port),
		Handler: s.withLogging(mux.ServeHTTP),
	}

	projectInfo := cfg.ProjectRoot
	if projectInfo == "" {
		projectInfo = "(no project selected)"
	}

	bindMode := "loopback only"
	if cfg.BindAddress == "0.0.0.0" {
		bindMode = "all interfaces (remote access enabled)"
	}

	log.Info().
		Str("addr", s.httpServer.Addr).
		Str("project_root", projectInfo).
		Msgf("Agent server configured (%s)", bindMode)

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
