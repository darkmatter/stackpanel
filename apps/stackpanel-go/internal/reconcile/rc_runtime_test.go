package reconcile

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupsession"
)

func TestRuntimeRequiresCurrentAgentAndBrowser(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	root := t.TempDir()
	health := setupsession.Health{AgentID: "one", Status: "ok", SetupVersion: 1, ProjectRoot: root, DevshellReady: true}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _ = json.NewEncoder(w).Encode(health) }))
	defer server.Close()
	s, err := setupsession.Create(setupsession.Session{Root: root, ProjectID: "p", AgentID: "one", Endpoint: server.URL, RequireBrowser: true})
	if err != nil {
		t.Fatal(err)
	}
	r := &RuntimeReconciler{SessionID: s.ID}
	ctx := &Context{Ctx: context.Background(), ProjectRoot: root}
	d, err := r.Diagnose(ctx)
	if err != nil || d.CheckResults[1].Status != "fail" {
		t.Fatalf("accepted unopened browser: %+v %v", d, err)
	}
	if err := setupsession.Update(s.ID, func(s *setupsession.Session) error {
		s.Connection = "c"
		s.ConnectedAt = time.Now()
		s.ReadyAt = time.Now()
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	d, err = r.Diagnose(ctx)
	if err != nil || d.CheckResults[1].Status != "pass" {
		t.Fatalf("not ready: %+v %v", d, err)
	}
	health.AgentID = "restarted"
	d, _ = r.Diagnose(ctx)
	if d.CheckResults[0].Status != "fail" {
		t.Fatal("accepted restarted agent")
	}
	ctx.ProjectRoot = t.TempDir()
	if _, err := r.Diagnose(ctx); err == nil {
		t.Fatal("accepted wrong repository")
	}
}
