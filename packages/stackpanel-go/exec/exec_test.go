package executor

import (
	"strings"
	"testing"
)

func TestExecutorRun(t *testing.T) {
	exec, err := New(t.TempDir(), nil)
	if err != nil {
		t.Fatalf("executor.New returned error: %v", err)
	}

	res, err := exec.Run("echo", "hello")
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}
	if res.ExitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", res.ExitCode)
	}
	if strings.TrimSpace(res.Stdout) != "hello" {
		t.Fatalf("unexpected stdout: %q", res.Stdout)
	}
}
