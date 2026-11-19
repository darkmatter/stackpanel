package cmd

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// Run the real Cobra tree, local service, and pure Nix evaluator against a
// self-contained consumer. No agent process, default project, or pairing token.
func TestModuleInfoWithoutAgent(t *testing.T) {
	if _, err := exec.LookPath("nix"); err != nil {
		t.Skip("requires Nix")
	}
	root := t.TempDir()
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
	t.Setenv("STACKPANEL_ROOT", t.TempDir()) // another project's shell
	t.Setenv("NIX_CONFIG", "experimental-features = nix-command flakes")
	flake := fmt.Sprintf(`{
  outputs = { self }: {
    legacyPackages.%q.stackpanelSerializable = {
      modulesListAll = [{ id = "db"; enabled = true;
        enablePath = "modules.db.enable"; configPath = "modules.db.settings";
        meta = { name = "Database"; category = "services"; };
        settings.token = "private-value";
        actions.migrate = { label = "Migrate schema"; outputMode = "stream"; };
      }];
      moduleOutputs.db.files = [{ path = "schema.sql"; type = "text"; }];
    };
  };
}`, nixeval.CurrentSystem())
	if err := os.WriteFile(
		filepath.Join(root, "flake.nix"),
		[]byte(flake),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	subdir := filepath.Join(root, "apps")
	if err := os.Mkdir(subdir, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Chdir(subdir)
	cmd := newModuleCmd()
	var out bytes.Buffer
	cmd.SetOut(&out)
	cmd.SetErr(&out)
	cmd.SetArgs([]string{"info", "db"})
	if err := cmd.ExecuteContext(t.Context()); err != nil {
		t.Fatal(err)
	}
	got := out.String()
	if !strings.Contains(got, "schema.sql") || !strings.Contains(got, "Migrate schema") ||
		strings.Contains(got, "private-value") {
		t.Errorf("unexpected module info: %q", got)
	}
}
