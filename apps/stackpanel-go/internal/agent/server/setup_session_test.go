package server

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupsession"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

func TestSetupAcknowledgementRequiresAuthAndProjectEvidence(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
	root := t.TempDir()
	origin := "http://localhost:3101"
	mgr, err := userconfig.NewManager()
	if err != nil {
		t.Fatal(err)
	}
	project, err := mgr.AddProject(root, "project")
	if err != nil {
		t.Fatal(err)
	}
	jwt, err := NewJWTManagerWithOptions(
		JWTManagerOptions{TestPairingToken: "setup-test"},
	)
	if err != nil {
		t.Fatal(err)
	}
	token, err := jwt.GenerateToken(origin)
	if err != nil {
		t.Fatal(err)
	}
	s := &Server{config: &config.Config{ProjectRoot: root}, jwtManager: jwt}
	session, err := setupsession.Create(
		setupsession.Session{
			Root:           root,
			AgentID:        jwt.GetAgentID(),
			ProjectID:      project.ID,
			Origin:         origin,
			RequireBrowser: true,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	request := func(auth, projectID string) int {
		r := httptest.NewRequest(
			"POST",
			"/api/setup/ready?project="+projectID,
			strings.NewReader(`{"session":"`+session.ID+`"}`),
		)
		r.Header.Set("Origin", origin)
		r.Header.Set("X-Stackpanel-Token", auth)
		w := httptest.NewRecorder()
		s.withCORS(s.requireAuth(s.handleSetupReady))(w, r)
		return w.Code
	}
	if got := request("", project.ID); got != http.StatusUnauthorized {
		t.Fatal(got)
	}
	if got := request(token, "wrong"); got != http.StatusConflict {
		t.Fatal(got)
	}
	if got := request(token, project.ID); got != http.StatusConflict {
		t.Fatal(got)
	}
	if err := setupsession.Update(session.ID, func(s *setupsession.Session) error {
		s.Connection = "stream"
		s.ConnectedAt = time.Now()
		s.ConfigLoadedAt = time.Now()
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if got := request(token, project.ID); got != http.StatusOK {
		t.Fatal(got)
	}
	s.config.ProjectRoot = t.TempDir()
	if got := request(token, project.ID); got != http.StatusConflict {
		t.Fatal(got)
	}
}

func TestStudioRedirectPreservesHandoff(t *testing.T) {
	r := httptest.NewRequest(
		"GET",
		"/studio?project=repo&setup=session&agent=http%3A%2F%2Flocalhost%3A9876&redirect=https://other&token=secret&stackpanel_pair_state=stale",
		nil,
	)
	w := httptest.NewRecorder()
	(&Server{}).handleStudio(w, r)
	location := w.Header().Get("Location")
	if w.Code != http.StatusTemporaryRedirect || !strings.HasSuffix(location, "#") ||
		w.Header().Get("Referrer-Policy") != "no-referrer" {
		t.Fatal("redirect must not inherit or disclose the source URL")
	}
	u, err := url.Parse(location)
	if err != nil {
		t.Fatal(err)
	}
	if u.Host != "local.stackpanel.com" || u.Query().Get("project") != "repo" ||
		u.Query().Get("setup") != "session" ||
		u.Query().Get("agent") != "http://localhost:9876" ||
		len(u.Query()) != 3 {
		t.Fatal(u)
	}
}

func TestStudioRejectsPostedCredentials(t *testing.T) {
	w := httptest.NewRecorder()
	(&Server{}).handleStudio(
		w,
		httptest.NewRequest("POST", "/studio", strings.NewReader("token=secret")),
	)
	if w.Code != http.StatusMethodNotAllowed || w.Header().Get("Location") != "" {
		t.Fatal("must not redirect a request body to Studio")
	}
}

func TestStudioHandoffDoesNotForwardCredentialURLs(t *testing.T) {
	for _, endpoint := range []string{"http://user:secret@localhost:9876", "http://localhost:9876/?token=secret", "http://localhost:9876/#secret", "https://unrelated.example"} {
		q := studioHandoff(
			url.Values{
				"project": {"p"},
				"agent":   {endpoint},
				"origin":  {endpoint},
				"token":   {"secret"},
			},
		)
		if q.Encode() != "project=p" {
			t.Error("unexpected handoff fields")
		}
	}
}
