package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupsession"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

func (s *Server) validateSetupRequest(r *http.Request, id string) (setupsession.Session, error) {
	session, err := setupsession.Load(id)
	if err != nil {
		return session, err
	}
	if err := setupsession.ValidateBrowser(session, s.jwtManager.GetAgentID(), r.Header.Get("Origin"), r.URL.Query().Get("project")); err != nil {
		return session, err
	}
	if filepath.Clean(s.config.ProjectRoot) != session.Root {
		return session, fmt.Errorf("agent is serving a different repository")
	}
	mgr, err := userconfig.NewManager()
	if err != nil {
		return session, err
	}
	project := mgr.GetProjectByID(session.ProjectID)
	if project == nil {
		return session, fmt.Errorf("setup repository is not registered")
	}
	root, err := filepath.EvalSymlinks(project.Path)
	if err != nil || root != session.Root {
		return session, fmt.Errorf("setup repository path does not match")
	}
	return session, nil
}

func (s *Server) handleSetupReady(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		Session string `json:"session"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "invalid setup acknowledgement")
		return
	}
	session, err := s.validateSetupRequest(r, body.Session)
	if err == nil {
		err = setupsession.RecordReady(body.Session, s.jwtManager.GetAgentID(), r.Header.Get("Origin"), session.ProjectID)
	}
	if err != nil {
		s.writeAPIError(w, http.StatusConflict, err.Error())
		return
	}
	s.writeJSON(w, http.StatusOK, map[string]bool{"ready": true})
}

func (s *Server) handleStudio(w http.ResponseWriter, r *http.Request) {
	u, _ := url.Parse(setupsession.DefaultStudioURL)
	q := u.Query()
	for _, key := range []string{"project", "setup", "agent"} {
		if value := r.URL.Query().Get(key); value != "" {
			q.Set(key, value)
		}
	}
	u.RawQuery = q.Encode()
	http.Redirect(w, r, u.String(), http.StatusTemporaryRedirect)
}

// handleSetupConfig evaluates the session's repository directly. It deliberately
// bypasses the legacy process-wide cache and inherited devshell config.
func (s *Server) handleSetupConfig(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("setup")
	session, err := s.validateSetupRequest(r, id)
	if err != nil {
		s.writeAPIError(w, http.StatusConflict, err.Error())
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 90*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", "eval", "--json", "--no-update-lock-file", "--no-write-lock-file", ".#legacyPackages."+getCurrentSystem()+".stackpanelConfig")
	cmd.Dir = session.Root
	cmd.WaitDelay = time.Second
	data, err := cmd.Output()
	var config map[string]any
	if err == nil {
		err = json.Unmarshal(data, &config)
	}
	if err != nil || len(config) == 0 {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("could not evaluate setup repository configuration: %v", err))
		return
	}
	if err := setupsession.Update(id, func(session *setupsession.Session) error { session.ConfigLoadedAt = time.Now(); return nil }); err != nil {
		s.writeAPIError(w, http.StatusConflict, err.Error())
		return
	}
	s.writeAPI(w, http.StatusOK, map[string]any{"config": config, "source": "setup_pure_eval"})
}
