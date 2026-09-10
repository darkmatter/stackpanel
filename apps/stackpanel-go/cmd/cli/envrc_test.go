package cmd

import (
	"bytes"
	"os/exec"
	"testing"

	"github.com/spf13/cobra"
)

// The command emits a large shell program assembled from Go string literals.
// A misplaced quote can make an unrelated later `fi` fail when .envrc evals it.
func TestEnvrcEmitsValidBash(t *testing.T) {
	var script bytes.Buffer
	cmd := &cobra.Command{}
	cmd.SetOut(&script)
	if err := initDirenv(cmd, nil); err != nil {
		t.Fatal(err)
	}
	check := exec.Command("bash", "--noprofile", "--norc", "-n")
	check.Stdin = &script
	if output, err := check.CombinedOutput(); err != nil {
		t.Fatalf("stack envrc generated invalid Bash: %v\n%s", err, output)
	}
}
