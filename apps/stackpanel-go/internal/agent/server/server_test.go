package server

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
)

// TestHandleHealth verifies the basic happy-path server wiring.
func TestHandleHealth(t *testing.T) {
	tempDir := t.TempDir()
	cfg := &config.Config{
		ProjectRoot: tempDir,
		Port:        0,
		DataDir:     tempDir,
	}

	srv, err := New(cfg)
	// New should succeed with a minimal config so long as the project root exists.
	if err != nil {
		t.Fatalf("New() returned error: %v", err)
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	srv.handleHealth(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200 OK, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"status":"ok"`) {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

func TestModulesAreNotADataEntity(t *testing.T) {
	s := &Server{}
	for _, tc := range []struct{ method, query, body string }{
		{"GET", "?entity=modules", ""},
		{"GET", "?entity=external-modules", ""},
		{"POST", "", `{"entity":"modules","data":{}}`},
		{"POST", "", `{"entity":"modules","key":"db","delete":true}`},
		{"DELETE", "?entity=modules", ""},
	} {
		w := httptest.NewRecorder()
		s.handleNixData(w, httptest.NewRequest(tc.method, "/api/nix/data"+tc.query, strings.NewReader(tc.body)))
		if w.Code != http.StatusBadRequest {
			t.Errorf("%s %s: expected unsupported entity, got %d", tc.method, tc.query, w.Code)
		}
	}
}

func TestHandlePairIncludesNoOpenerRedirectFallback(t *testing.T) {
	tempDir := t.TempDir()
	cfg := &config.Config{
		ProjectRoot: tempDir,
		Port:        0,
		DataDir:     tempDir,
	}

	srv, err := New(cfg)
	if err != nil {
		t.Fatalf("New() returned error: %v", err)
	}

	rec := httptest.NewRecorder()
	state := strings.Repeat("ab", 32)
	verifier := strings.Repeat("cd", 32)
	form := url.Values{
		"state":     {state},
		"verifier":  {verifier},
		"return_to": {"http://localhost:3001/studio/m/demo?project=p&token=secret#private"},
	}
	req := httptest.NewRequest(
		http.MethodPost,
		"/pair?origin=https://elsewhere.example",
		strings.NewReader(form.Encode()),
	)
	req.Header.Set("Origin", "http://localhost:3001")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	srv.handlePair(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200 OK, got %d", rec.Code)
	}

	body := rec.Body.String()
	for _, want := range []string{
		"stackpanel_pair_code: code",
		"window.location.replace",
		"const targetOrigin = \"http://localhost:3001\"",
		"const returnUrl = \"http://localhost:3001/studio/m/demo?project=p\"",
		"const state = \"" + state + "\"",
		"stackpanel_pair_state: state",
		"window.opener.postMessage",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("expected pair page to contain %q", want)
		}
	}
	if strings.Contains(body, "stackpanel_agent_token") ||
		strings.Contains(body, verifier) ||
		strings.Contains(body, "secret") ||
		strings.Contains(body, "#private") ||
		strings.Contains(body, "elsewhere.example") {
		t.Fatal("approval page propagated untrusted recipient or legacy URL credential")
	}
}

func TestPairRequiresBrowserOriginAndPostedState(t *testing.T) {
	s := &Server{config: &config.Config{}}
	state := strings.Repeat("ab", 32)
	for _, tc := range []struct {
		name, method, origin, form string
		want                       int
	}{
		{"GET", "GET", "http://localhost:3001", "", 403},
		{"missing Origin", "POST", "", "state=" + state, 403},
		{"opaque Origin", "POST", "null", "state=" + state, 403},
		{"disallowed Origin", "POST", "https://other.example", "state=" + state, 403},
		{"path is not an origin", "POST", "http://localhost:3001/path", "state=" + state, 403},
		{"receiving agent origin (canonical host and effective port)", "POST", "http://localhost", "state=" + state, 403},
		{"no posted state", "POST", "http://localhost:3001", "", 400},
		{"invalid state", "POST", "http://localhost:3001", "state=invalid", 400},
	} {
		r := httptest.NewRequest(
			tc.method,
			"/pair?origin=http://localhost:3001&state="+state,
			strings.NewReader(tc.form),
		)
		r.Host = "LOCALHOST:80"
		r.Header.Set("Origin", tc.origin)
		r.Header.Set("Referer", "http://localhost:3001/studio")
		r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		w := httptest.NewRecorder()
		s.handlePair(w, r)
		if w.Code != tc.want {
			t.Errorf("%s: got %d, want %d", tc.name, w.Code, tc.want)
		}
	}
}

func TestPairRejectsAgentAsItsOwnPeer(t *testing.T) {
	const agent = "http://localhost:9876"
	r := httptest.NewRequest(
		http.MethodPost,
		agent+"/pair",
		strings.NewReader("state="+strings.Repeat("a", 64)),
	)
	r.Header.Set("Origin", agent)
	r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	r.Header.Set("Sec-Fetch-Site", "same-origin")
	w := httptest.NewRecorder()
	(&Server{}).handlePair(w, r)
	if w.Code != http.StatusForbidden {
		t.Fatal("agent must not be its own pairing peer")
	}
}

func TestPairReturnURLCannotChangeRecipients(t *testing.T) {
	const origin = "http://localhost:3001"
	for _, invalid := range []string{"//other.example/studio", "http://127.0.0.1:3001/studio", origin + "0/studio", "http://user@localhost:3001/studio", origin + "/outside"} {
		if got := pairReturnURL(invalid, origin); got != origin+"/studio" {
			t.Errorf("invalid return address %q accepted", invalid)
		}
	}
}
