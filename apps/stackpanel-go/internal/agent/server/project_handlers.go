package server

import (
	"net/http"
	"strings"

	"github.com/darkmatter/stackpanel/apps/stackpanel-go/internal/agent/project"
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
			s.writeAPI(w, http.StatusOK, map[string]any{
				"has_project": false,
				"project":     nil,
			})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"has_project": true,
		"project": map[string]any{
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

	// Convert to response format
	projectList := make([]map[string]any, len(projects))
	for i, p := range projects {
		projectList[i] = map[string]any{
			"path":        p.Path,
			"name":        p.Name,
			"last_opened": p.LastOpened,
			"active":      p.Active,
		}
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"projects": projectList,
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

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
		"project": map[string]any{
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

	err := project.ValidateProject(req.Path)
	if err != nil {
		switch err {
		case project.ErrNotGitRepo:
			s.writeAPI(w, http.StatusOK, map[string]any{
				"valid":   false,
				"error":   "not_git_repo",
				"message": "Directory is not a git repository (no .git folder found)",
			})
		case project.ErrNotStackpanel:
			s.writeAPI(w, http.StatusOK, map[string]any{
				"valid":   false,
				"error":   "not_stackpanel",
				"message": "Directory is not a valid Stackpanel project (no config.stackpanel found)",
			})
		case project.ErrProjectNotFound:
			s.writeAPI(w, http.StatusOK, map[string]any{
				"valid":   false,
				"error":   "not_found",
				"message": "Directory does not exist",
			})
		default:
			s.writeAPI(w, http.StatusOK, map[string]any{
				"valid":   false,
				"error":   "unknown",
				"message": err.Error(),
			})
		}
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"valid": true,
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
