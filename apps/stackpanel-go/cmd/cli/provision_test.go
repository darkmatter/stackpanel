package cmd

import (
	"path/filepath"
	"testing"
)

func TestMachineHardwareConfigPaths(t *testing.T) {
	projectRoot := t.TempDir()

	absPath, relPath, err := machineHardwareConfigPaths(projectRoot, "volt-2")
	if err != nil {
		t.Fatalf("machineHardwareConfigPaths returned error: %v", err)
	}

	wantRel := filepath.Join(".stack", "machines", "volt-2", "hardware-configuration.nix")
	if relPath != wantRel {
		t.Fatalf("relPath = %q, want %q", relPath, wantRel)
	}

	wantAbs := filepath.Join(projectRoot, wantRel)
	if absPath != wantAbs {
		t.Fatalf("absPath = %q, want %q", absPath, wantAbs)
	}
}
