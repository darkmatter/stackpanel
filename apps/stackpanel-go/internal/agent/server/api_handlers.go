package server

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// handleValidateToken checks if the provided token is valid.
// GET /api/auth/validate
// This endpoint requires auth, so if it succeeds, the token is valid.
func (s *Server) handleValidateToken(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// If we get here, the token is valid (requireAuth middleware passed)
	s.writeAPI(w, http.StatusOK, map[string]any{
		"valid": true,
	})
}

// -----------------------------
// HTTP endpoints
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

type nixEvalRequest struct {
	Expression string `json:"expression"`
	File       string `json:"file,omitempty"`
}

type fileWriteRequest struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

type secretSetRequest struct {
	Env   string `json:"env"`
	Key   string `json:"key"`
	Value string `json:"value"`
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	hasProject := s.config.ProjectRoot != ""
	resp := map[string]any{
		"status":      "ok",
		"has_project": hasProject,
		"agent_id":    s.jwtManager.GetAgentID(),
		"test_mode":   s.jwtManager.IsTestMode(),
	}
	if hasProject {
		resp["project_root"] = s.config.ProjectRoot
	}
	s.writeJSON(w, http.StatusOK, resp)
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	hasProject := s.config.ProjectRoot != ""
	resp := map[string]any{
		"status":      "running",
		"has_project": hasProject,
	}
	if hasProject {
		resp["project_root"] = s.config.ProjectRoot
		if proj, err := s.projectMgr.CurrentProject(); err == nil {
			resp["project"] = map[string]any{
				"path":        proj.Path,
				"name":        proj.Name,
				"last_opened": proj.LastOpened,
			}
		}
	}

	// Add devshell status information
	if s.exec != nil {
		resp["devshell"] = map[string]any{
			"in_devshell":      s.exec.InDevshell(),
			"has_devshell_env": s.exec.HasDevshellEnv(),
		}
	} else {
		resp["devshell"] = map[string]any{
			"in_devshell":      false,
			"has_devshell_env": false,
		}
	}

	s.writeJSON(w, http.StatusOK, resp)
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

// handleFilesList lists files in a directory
// GET /api/files/list?path=.stackpanel/state
func (s *Server) handleFilesList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

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

	entries, err := os.ReadDir(abs)
	if err != nil {
		if os.IsNotExist(err) {
			s.writeAPI(w, http.StatusOK, map[string]any{
				"path":   path,
				"exists": false,
				"files":  []string{},
			})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	var files []map[string]any
	for _, entry := range entries {
		info, _ := entry.Info()
		file := map[string]any{
			"name":  entry.Name(),
			"isDir": entry.IsDir(),
		}
		if info != nil {
			file["size"] = info.Size()
			file["modTime"] = info.ModTime().Unix()
		}
		files = append(files, file)
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"path":   path,
		"exists": true,
		"files":  files,
	})
}

// handleScriptSource gets the source code of a script/command
// GET /api/scripts/source?name=<script-name>
func (s *Server) handleScriptSource(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	name := strings.TrimSpace(r.URL.Query().Get("name"))
	if name == "" {
		s.writeAPIError(w, http.StatusBadRequest, "name is required")
		return
	}

	// Use 'which' to find the script path
	result, err := s.exec.Run("which", name)
	if err != nil || result.ExitCode != 0 {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"name":   name,
			"found":  false,
			"reason": "not found in PATH",
		})
		return
	}

	scriptPath := strings.TrimSpace(result.Stdout)
	if scriptPath == "" {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"name":   name,
			"found":  false,
			"reason": "not found in PATH",
		})
		return
	}

	// Check if it's a binary or script by reading the first bytes
	content, err := os.ReadFile(scriptPath)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to read script: "+err.Error())
		return
	}

	// Check if it's a binary (non-text file)
	isBinary := false
	if len(content) > 0 {
		// Check for shebang or common text patterns
		contentStr := string(content)
		if !strings.HasPrefix(contentStr, "#!") && !strings.HasPrefix(contentStr, "//") {
			// Check for null bytes which indicate binary
			for i := 0; i < len(content) && i < 512; i++ {
				if content[i] == 0 {
					isBinary = true
					break
				}
			}
		}
	}

	if isBinary {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"name":     name,
			"found":    true,
			"path":     scriptPath,
			"isBinary": true,
			"source":   "",
		})
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"name":     name,
		"found":    true,
		"path":     scriptPath,
		"isBinary": false,
		"source":   string(content),
	})
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
