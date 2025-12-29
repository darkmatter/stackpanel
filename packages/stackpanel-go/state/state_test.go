package state

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadFromProjectRoot(t *testing.T) {
	tmp := t.TempDir()
	stateDir := filepath.Join(tmp, ".stackpanel", "state")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatalf("failed to create state dir: %v", err)
	}

	data := `{"version":1,"projectName":"demo","basePort":6400,"paths":{"state":".stackpanel/state","gen":".stackpanel/gen","data":".stackpanel"},"apps":{},"services":{},"network":{"step":{"enable":false}}}`
	if err := os.WriteFile(filepath.Join(stateDir, DefaultStateFile), []byte(data), 0o644); err != nil {
		t.Fatalf("failed to write state file: %v", err)
	}

	st, err := LoadFromProjectRoot(tmp)
	if err != nil {
		t.Fatalf("LoadFromProjectRoot returned error: %v", err)
	}
	if st.ProjectName != "demo" {
		t.Fatalf("unexpected project name: %s", st.ProjectName)
	}
}
