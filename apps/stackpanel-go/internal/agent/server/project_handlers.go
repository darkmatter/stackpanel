package server

import (
	"net/http"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/rs/zerolog/log"
)

// projectOpenRequest represents a request to open a project.
type projectOpenRequest struct {
	Path string `json:"path"`
}

// projectValidateRequest represents a request to validate a project path.
type projectValidateRequest struct {
	Path string `json:"path"`
}

// handleProjectCurrent returns the currently active project.
// GET /api/project/current
func (s *Server) handleProjectCurrent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	proj, err := s.projectMgr.CurrentProject()
	if err != nil {
		if err == project.ErrNoProject {
			// Check if there's a default project
			ucm := s.projectMgr.UserConfigManager()
			var defaultProject map[string]any
			if ucm != nil {
				if dp := ucm.GetDefaultProject(); dp != nil {
					id := dp.ID
					if id == "" {
						id = userconfig.GenerateProjectID(dp.Path)
					}
					defaultProject = map[string]any{
						"id":          id,
						"path":        dp.Path,
						"name":        dp.Name,
						"last_opened": dp.LastOpened,
					}
				}
			}
			s.writeAPI(w, http.StatusOK, map[string]any{
				"has_project":     false,
				"project":         nil,
				"default_project": defaultProject,
			})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	// Generate ID if not stored
	id := userconfig.GenerateProjectID(proj.Path)

	s.writeAPI(w, http.StatusOK, map[string]any{
		"has_project": true,
		"project": map[string]any{
			"id":          id,
			"path":        proj.Path,
			"name":        proj.Name,
			"last_opened": proj.LastOpened,
			"active":      proj.Active,
		},
	})
}

// handleProjectList returns all known projects.
// GET /api/project/list
func (s *Server) handleProjectList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	projects := s.projectMgr.ListProjects()
	ucm := s.projectMgr.UserConfigManager()

	// Get default project path for comparison
	var defaultPath string
	if ucm != nil {
		defaultPath = ucm.GetDefaultProjectPath()
	}

	// Convert to response format
	projectList := make([]map[string]any, len(projects))
	for i, p := range projects {
		// Generate ID from path
		id := userconfig.GenerateProjectID(p.Path)

		projectList[i] = map[string]any{
			"id":          id,
			"path":        p.Path,
			"name":        p.Name,
			"last_opened": p.LastOpened,
			"active":      p.Active,
			"is_default":  p.Path == defaultPath,
		}
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"projects":     projectList,
		"default_path": defaultPath,
		"hint":         "Use project 'id' or 'name' in X-Stackpanel-Project header or 'project' query param",
	})
}

// handleProjectOpen opens/selects a project.
// POST /api/project/open
func (s *Server) handleProjectOpen(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req projectOpenRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	req.Path = strings.TrimSpace(req.Path)
	if req.Path == "" {
		s.writeAPIError(w, http.StatusBadRequest, "path is required")
		return
	}

	log.Debug().Str("path", req.Path).Msg("Opening project")

	proj, err := s.projectMgr.OpenProject(req.Path)
	if err != nil {
		// Return specific error types
		switch err {
		case project.ErrNotGitRepo:
			s.writeAPI(w, http.StatusBadRequest, map[string]any{
				"valid":   false,
				"error":   "not_git_repo",
				"message": "Directory is not a git repository (no .git folder found)",
			})
		case project.ErrNotStackpanel:
			s.writeAPI(w, http.StatusBadRequest, map[string]any{
				"valid":   false,
				"error":   "not_stackpanel",
				"message": "Directory is not a valid Stackpanel project (no config.stackpanel found)",
			})
		case project.ErrProjectNotFound:
			s.writeAPI(w, http.StatusBadRequest, map[string]any{
				"valid":   false,
				"error":   "not_found",
				"message": "Directory does not exist",
			})
		default:
			s.writeAPIError(w, http.StatusBadRequest, err.Error())
		}
		return
	}

	// Update the server's config to use this project
	s.config.ProjectRoot = proj.Path

	// Re-initialize the executor with the new project root
	var devshellStatus map[string]any
	if err := s.reinitializeExecutor(); err != nil {
		log.Error().Err(err).Msg("Failed to reinitialize executor after project change")
		// Don't fail - the project is opened, executor will work on next request
		devshellStatus = map[string]any{
			"in_devshell":      false,
			"has_devshell_env": false,
			"error":            err.Error(),
		}
	} else if s.exec != nil {
		devshellStatus = map[string]any{
			"in_devshell":      s.exec.InDevshell(),
			"has_devshell_env": s.exec.HasDevshellEnv(),
		}
		log.Info().
			Str("path", proj.Path).
			Bool("in_devshell", s.exec.InDevshell()).
			Bool("has_devshell_env", s.exec.HasDevshellEnv()).
			Msg("Project opened with devshell support")
	}

	// Generate ID for the project
	id := userconfig.GenerateProjectID(proj.Path)

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
		"project": map[string]any{
			"id":          id,
			"path":        proj.Path,
			"name":        proj.Name,
			"last_opened": proj.LastOpened,
			"active":      proj.Active,
		},
		"devshell": devshellStatus,
	})
}

// handleProjectClose closes the current project.
// POST /api/project/close
func (s *Server) handleProjectClose(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	if err := s.projectMgr.CloseProject(); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	s.config.ProjectRoot = ""

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
	})
}

// handleProjectValidate validates a project path without opening it.
// POST /api/project/validate
func (s *Server) handleProjectValidate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req projectValidateRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	req.Path = strings.TrimSpace(req.Path)
	if req.Path == "" {
		s.writeAPIError(w, http.StatusBadRequest, "path is required")
		return
	}

	log.Debug().Str("path", req.Path).Msg("Validating project")

	// Use detailed validation
	result := project.ValidateProjectDetailed(req.Path, project.ValidationNormal)

	if result.Error != nil {
		errorCode := "unknown"
		message := result.Error.Error()

		switch result.Error {
		case project.ErrNotGitRepo:
			errorCode = "not_git_repo"
			message = "Directory is not a git repository (no .git folder found)"
		case project.ErrNotStackpanel:
			errorCode = "not_stackpanel"
			message = "Directory is not a valid Stackpanel project (no .stack/config.nix found)"
		case project.ErrProjectNotFound:
			errorCode = "not_found"
			message = "Directory does not exist"
		case project.ErrSuspiciousPath:
			errorCode = "suspicious_path"
			message = "Path appears to be a system or temporary directory"
		case project.ErrFlakeNotStackpanel:
			errorCode = "flake_not_stackpanel"
			message = "flake.nix exists but doesn't appear to be a Stackpanel project"
		case project.ErrInvalidConfig:
			errorCode = "invalid_config"
			message = "stackpanel config.nix is invalid or missing required fields"
		}

		s.writeAPI(w, http.StatusOK, map[string]any{
			"valid":    false,
			"error":    errorCode,
			"message":  message,
			"warnings": result.Warnings,
		})
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"valid":        true,
		"project_type": result.ProjectType,
		"warnings":     result.Warnings,
	})
}

// handleProjectRemove removes a project from the known projects list.
// DELETE /api/project/remove?path=...
func (s *Server) handleProjectRemove(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	path := strings.TrimSpace(r.URL.Query().Get("path"))
	if path == "" {
		s.writeAPIError(w, http.StatusBadRequest, "path is required")
		return
	}

	if err := s.projectMgr.RemoveProject(path); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
	})
}

// projectDefaultRequest represents a request to set the default project.
type projectDefaultRequest struct {
	// Path or ID or name of the project to set as default (empty to clear)
	Project string `json:"project"`
}

// handleProjectDefault gets or sets the default project.
// GET /api/project/default - returns the current default project
// POST /api/project/default - sets the default project
// DELETE /api/project/default - clears the default project
func (s *Server) handleProjectDefault(w http.ResponseWriter, r *http.Request) {
	ucm := s.projectMgr.UserConfigManager()
	if ucm == nil {
		s.writeAPIError(w, http.StatusInternalServerError, "user config not available")
		return
	}

	switch r.Method {
	case http.MethodGet:
		// Get current default
		proj := ucm.GetDefaultProject()
		if proj == nil {
			s.writeAPI(w, http.StatusOK, map[string]any{
				"has_default": false,
				"project":     nil,
			})
			return
		}

		id := proj.ID
		if id == "" {
			id = userconfig.GenerateProjectID(proj.Path)
		}

		s.writeAPI(w, http.StatusOK, map[string]any{
			"has_default": true,
			"project": map[string]any{
				"id":          id,
				"path":        proj.Path,
				"name":        proj.Name,
				"last_opened": proj.LastOpened,
			},
		})

	case http.MethodPost:
		// Set default project
		var req projectDefaultRequest
		if err := s.readJSON(r.Body, &req); err != nil {
			s.writeAPIError(w, http.StatusBadRequest, err.Error())
			return
		}

		// Resolve the project identifier
		proj := ucm.ResolveProject(req.Project)
		if proj == nil {
			s.writeAPI(w, http.StatusBadRequest, map[string]any{
				"error":   "project_not_found",
				"message": "Project not found. Use /api/project/list to see available projects.",
				"project": req.Project,
			})
			return
		}

		// Set as default
		if err := ucm.SetDefaultProject(proj.Path); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, err.Error())
			return
		}

		id := proj.ID
		if id == "" {
			id = userconfig.GenerateProjectID(proj.Path)
		}

		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"project": map[string]any{
				"id":          id,
				"path":        proj.Path,
				"name":        proj.Name,
				"last_opened": proj.LastOpened,
			},
		})

	case http.MethodDelete:
		// Clear default
		if err := ucm.ClearDefaultProject(); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, err.Error())
			return
		}

		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"message": "Default project cleared",
		})

	default:
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// handleProjectResolve resolves a project identifier to a project.
// GET /api/project/resolve?project=<id|name|path>
func (s *Server) handleProjectResolve(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	ucm := s.projectMgr.UserConfigManager()
	if ucm == nil {
		s.writeAPIError(w, http.StatusInternalServerError, "user config not available")
		return
	}

	identifier := strings.TrimSpace(r.URL.Query().Get("project"))
	if identifier == "" {
		s.writeAPIError(w, http.StatusBadRequest, "project parameter is required")
		return
	}

	proj := ucm.ResolveProject(identifier)
	if proj == nil {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"found":   false,
			"project": nil,
			"query":   identifier,
		})
		return
	}

	id := proj.ID
	if id == "" {
		id = userconfig.GenerateProjectID(proj.Path)
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"found": true,
		"project": map[string]any{
			"id":          id,
			"path":        proj.Path,
			"name":        proj.Name,
			"last_opened": proj.LastOpened,
		},
		"query": identifier,
	})
}
