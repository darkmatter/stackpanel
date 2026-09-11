package setupsession

import (
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestStudioBookmarkPreservesEndpointWithoutExpiredSession(t *testing.T) {
	link, err := StudioURL("https://studio.example/studio?setup=expired&demo=1", Session{ProjectID: "project", Endpoint: "http://localhost:12345"})
	if err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(link)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if q.Has("setup") || q.Has("demo") || q.Get("agent") != "http://localhost:12345" || q.Get("project") != "project" {
		t.Fatalf("invalid Studio bookmark: %s", link)
	}
}

func TestSessionRequiresFreshBoundEvidence(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	s, err := Create(Session{Root: t.TempDir(), AgentID: "agent", ProjectID: "project", Origin: "http://localhost", RequireBrowser: true})
	if err != nil {
		t.Fatal(err)
	}
	if err := RecordReady(s.ID, "agent", s.Origin, "project"); err == nil {
		t.Fatal("accepted no connection")
	}
	if err := Update(s.ID, func(s *Session) error { s.Connection = "stream"; s.ConnectedAt = time.Now(); return nil }); err != nil {
		t.Fatal(err)
	}
	if err := RecordReady(s.ID, "agent", s.Origin, "project"); err == nil {
		t.Fatal("accepted unloaded project")
	}
	if err := Update(s.ID, func(s *Session) error { s.ConfigLoadedAt = time.Now(); return nil }); err != nil {
		t.Fatal(err)
	}
	for _, wrong := range []struct{ agent, origin, project string }{{"other", s.Origin, "project"}, {"agent", "http://other", "project"}, {"agent", s.Origin, "other"}} {
		if err := RecordReady(s.ID, wrong.agent, wrong.origin, wrong.project); err == nil {
			t.Fatal("accepted mismatched evidence")
		}
	}
	if err := RecordReady(s.ID, "agent", s.Origin, "project"); err != nil {
		t.Fatal(err)
	}
	loaded, err := Load(s.ID)
	if err != nil || loaded.ReadyAt.IsZero() {
		t.Fatalf("no ready evidence: %+v %v", loaded, err)
	}
	path, _ := sessionPath(s.ID)
	stat, _ := os.Stat(path)
	if stat.Mode().Perm() != 0o600 {
		t.Fatalf("insecure session mode: %v", stat.Mode())
	}
	if _, err := Load("../../other"); err == nil {
		t.Fatal("accepted traversal")
	}
	if err := Update(s.ID, func(s *Session) error { s.Expires = time.Now().Add(-time.Second); return nil }); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(s.ID); err == nil {
		t.Fatal("accepted expired session")
	}
}
