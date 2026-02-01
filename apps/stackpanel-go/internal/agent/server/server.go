// Package server provides the HTTP/SSE server for the stackpanel agent.
package server

import (
	"fmt"
	"html/template"
	"net/http"
	"sync"

	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/gopbconnect"
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

	// FlakeWatcher for monitoring .#stackpanelConfig and .#stackpanelPackages
	flakeWatcher *FlakeWatcher

	// ShellManager for tracking devshell state and rebuilds
	shellManager *ShellManager
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
	jwtMgr, err := NewJWTManagerWithOptions(JWTManagerOptions{
		TestPairingToken: cfg.TestPairingToken,
	})
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

	// Initialize shell manager for tracking devshell state
	if cfg.ProjectRoot != "" {
		s.shellManager = NewShellManager(cfg.ProjectRoot, s)
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
	mux.HandleFunc("/api/project/resolve", s.withCORS(s.handleProjectResolve))
	// These require auth since they modify state
	mux.HandleFunc("/api/project/open", s.withCORS(s.requireAuth(s.handleProjectOpen)))
	mux.HandleFunc("/api/project/close", s.withCORS(s.requireAuth(s.handleProjectClose)))
	mux.HandleFunc("/api/project/validate", s.withCORS(s.requireAuth(s.handleProjectValidate)))
	mux.HandleFunc("/api/project/remove", s.withCORS(s.requireAuth(s.handleProjectRemove)))
	mux.HandleFunc("/api/project/default", s.withCORS(s.requireAuth(s.handleProjectDefault)))

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
	mux.HandleFunc("/api/files/list", s.withCORS(s.requireAuth(s.requireProject(s.handleFilesList))))
	mux.HandleFunc("/api/scripts/source", s.withCORS(s.requireAuth(s.requireProject(s.handleScriptSource))))
	mux.HandleFunc("/api/secrets/set", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsSet))))

	// Secret management endpoints (dispatch to agenix or chamber based on backend)
	mux.HandleFunc("/api/secrets/write", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsWriteDispatch))))
	mux.HandleFunc("/api/secrets/read", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsReadDispatch))))
	mux.HandleFunc("/api/secrets/delete", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsDeleteDispatch))))
	mux.HandleFunc("/api/secrets/list", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsListDispatch))))
	mux.HandleFunc("/api/secrets/identity", s.withCORS(s.requireAuth(s.requireProject(s.handleAgeIdentity))))
	mux.HandleFunc("/api/secrets/kms", s.withCORS(s.requireAuth(s.requireProject(s.handleKMSConfig))))
	mux.HandleFunc("/api/secrets/backend", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsBackend))))

	// SOPS secret management endpoints (per-environment YAML files)
	mux.HandleFunc("/api/sops/read", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsRead))))
	mux.HandleFunc("/api/sops/write", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsWrite))))
	mux.HandleFunc("/api/sops/delete", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsDelete))))
	mux.HandleFunc("/api/sops/list", s.withCORS(s.requireAuth(s.requireProject(s.handleSecretsList))))

	// Group-based secrets management (SOPS files per access control group)
	mux.HandleFunc("/api/secrets/group/write", s.withCORS(s.requireAuth(s.requireProject(s.handleGroupSecretWrite))))
	mux.HandleFunc("/api/secrets/group/read", s.withCORS(s.requireAuth(s.requireProject(s.handleGroupSecretRead))))
	mux.HandleFunc("/api/secrets/group/delete", s.withCORS(s.requireAuth(s.requireProject(s.handleGroupSecretDelete))))
	mux.HandleFunc("/api/secrets/group/list", s.withCORS(s.requireAuth(s.requireProject(s.handleGroupSecretsList))))
	mux.HandleFunc("/api/secrets/generate-env-package", s.withCORS(s.requireAuth(s.requireProject(s.handleGenerateEnvPackage))))

	// Security status endpoints (AWS session and certificate status)
	mux.HandleFunc("/api/security/status", s.withCORS(s.requireAuth(s.handleSecurityStatus)))
	mux.HandleFunc("/api/security/aws", s.withCORS(s.requireAuth(s.handleAWSStatus)))
	mux.HandleFunc("/api/security/certificate", s.withCORS(s.requireAuth(s.handleCertificateStatus)))

	// Nixpkgs package search and installed packages
	mux.HandleFunc("/api/nixpkgs/search", s.withCORS(s.requireAuth(s.handleNixpkgsSearch)))
	mux.HandleFunc("/api/nixpkgs/installed", s.withCORS(s.requireAuth(s.handleInstalledPackages)))
	mux.HandleFunc("/api/nixpkgs/meta", s.withCORS(s.requireAuth(s.handleNixpkgsPackageMeta)))

	// SST infrastructure management endpoints
	mux.HandleFunc("/api/sst/config", s.withCORS(s.requireAuth(s.requireProject(s.handleSSTConfig))))
	mux.HandleFunc("/api/sst/status", s.withCORS(s.requireAuth(s.requireProject(s.handleSSTStatus))))
	mux.HandleFunc("/api/sst/deploy", s.withCORS(s.requireAuth(s.requireProject(s.handleSSTDeploy))))
	mux.HandleFunc("/api/sst/outputs", s.withCORS(s.requireAuth(s.requireProject(s.handleSSTOutputs))))
	mux.HandleFunc("/api/sst/resources", s.withCORS(s.requireAuth(s.requireProject(s.handleSSTResources))))
	mux.HandleFunc("/api/sst/remove", s.withCORS(s.requireAuth(s.requireProject(s.handleSSTRemove))))

	// Config sync endpoints (check/sync config.nix → data files)
	mux.HandleFunc("/api/config/check", s.withCORS(s.requireAuth(s.requireProject(s.handleConfigCheck))))
	mux.HandleFunc("/api/config/sync", s.withCORS(s.requireAuth(s.requireProject(s.handleConfigSync))))

	// Process-compose process management endpoints
	mux.HandleFunc("/api/process-compose/processes", s.withCORS(s.requireAuth(s.requireProject(s.handleProcessComposeProcesses))))
	mux.HandleFunc("/api/process-compose/project/state", s.withCORS(s.requireAuth(s.requireProject(s.handleProcessComposeProjectState))))
	mux.HandleFunc("/api/process-compose/process/info/", s.withCORS(s.requireAuth(s.requireProject(s.handleProcessComposeProcessInfo))))
	mux.HandleFunc("/api/process-compose/process/ports/", s.withCORS(s.requireAuth(s.requireProject(s.handleProcessComposeProcessPorts))))
	mux.HandleFunc("/api/process-compose/process/logs/", s.withCORS(s.requireAuth(s.requireProject(s.handleProcessComposeProcessLogs))))
	mux.HandleFunc("/api/process-compose/process/start/", s.withCORS(s.requireAuth(s.requireProject(s.handleProcessComposeStart))))
	mux.HandleFunc("/api/process-compose/process/stop/", s.withCORS(s.requireAuth(s.requireProject(s.handleProcessComposeStop))))
	mux.HandleFunc("/api/process-compose/process/restart/", s.withCORS(s.requireAuth(s.requireProject(s.handleProcessComposeRestart))))
	mux.HandleFunc("/api/process-compose/logs/ws", s.withCORS(s.handleProcessComposeLogsWS)) // WebSocket, no auth required for upgrade

	// Healthchecks endpoint for module health status
	mux.HandleFunc("/api/healthchecks", s.withCORS(s.requireAuth(s.requireProject(s.handleHealthchecks))))

	// Modules endpoint for the module browser
	mux.HandleFunc("/api/modules", s.withCORS(s.requireAuth(s.requireProject(s.handleModules))))
	mux.HandleFunc("/api/modules/", s.withCORS(s.requireAuth(s.requireProject(s.handleModules))))

	// Module registry endpoint for browsing and installing external modules
	mux.HandleFunc("/api/registry", s.withCORS(s.requireAuth(s.handleRegistry)))
	mux.HandleFunc("/api/registry/", s.withCORS(s.requireAuth(s.handleRegistry)))

	// Connect-RPC service (type-safe gRPC-Web compatible API)
	// This provides fully typed endpoints generated from proto definitions
	agentService := NewAgentServiceServer(s)
	path, handler := gopbconnect.NewAgentServiceHandler(agentService)
	mux.Handle(path, s.withCORS(s.requireAuth(handler.ServeHTTP)))

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

		// Start the FlakeWatcher for live .#stackpanelConfig and .#stackpanelPackages evaluation
		fw, err := NewFlakeWatcher(FlakeWatcherConfig{
			ProjectRoot: s.config.ProjectRoot,
			Server:      s,
		})
		if err != nil {
			log.Warn().Err(err).Msg("Failed to create FlakeWatcher, config/packages watching disabled")
		} else {
			s.flakeWatcher = fw
			if err := fw.Start(); err != nil {
				log.Warn().Err(err).Msg("Failed to start FlakeWatcher")
			}
		}
	}

	return s.httpServer.ListenAndServe()
}

// Stop gracefully shuts down the server.
func (s *Server) Stop() {
	if s.flakeWatcher != nil {
		_ = s.flakeWatcher.Stop()
	}
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
		s.shellManager = nil
		return nil
	}

	exec, err := sharedexec.New(s.config.ProjectRoot, s.config.AllowedCommands)
	if err != nil {
		return fmt.Errorf("failed to create executor: %w", err)
	}

	s.exec = exec
	s.shellManager = NewShellManager(s.config.ProjectRoot, s)

	log.Info().
		Str("project_root", s.config.ProjectRoot).
		Bool("in_devshell", exec.InDevshell()).
		Bool("has_devshell_env", exec.HasDevshellEnv()).
		Msg("Executor reinitialized for new project")

	// Restart file watcher for new project
	go s.watchConfigFiles()

	// Restart FlakeWatcher for new project
	if s.flakeWatcher != nil {
		_ = s.flakeWatcher.Stop()
	}
	fw, err := NewFlakeWatcher(FlakeWatcherConfig{
		ProjectRoot: s.config.ProjectRoot,
		Server:      s,
	})
	if err != nil {
		log.Warn().Err(err).Msg("Failed to create FlakeWatcher for new project")
	} else {
		s.flakeWatcher = fw
		if err := fw.Start(); err != nil {
			log.Warn().Err(err).Msg("Failed to start FlakeWatcher for new project")
		}
	}

	return nil
}
