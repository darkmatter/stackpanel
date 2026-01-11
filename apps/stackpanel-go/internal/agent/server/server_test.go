package server

import (
	"net/http"
	"net/http/httptest"
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
