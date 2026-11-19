package reconcile

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// A no-input flake exercises the same pure projection used for adoption without
// requiring a registry, network, or a copy of the stackpanel flake.
func TestSpeculatePureOverlay(t *testing.T) {
	if _, err := exec.LookPath("nix"); err != nil {
		t.Skip("requires Nix")
	}
	root := t.TempDir()
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
	t.Setenv("NIX_CONFIG", "experimental-features = nix-command flakes")
	flake := fmt.Sprintf(`{
  outputs = { self }: {
    legacyPackages.%q.stackpanelSpeculate = { config }: {
      writerOutPath = config.settings."key.with.dots";
      writerDrvPath = if builtins ? currentSystem then throw "impure evaluation" else "pure";
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
	literal := "${throw \"not Nix code\"}\n$(not a shell) \\ ''"
	spec, err := Speculate(
		t.Context(),
		root,
		map[string]any{"settings": map[string]any{"key.with.dots": literal}},
		0,
	)
	if err != nil {
		t.Fatal(err)
	}
	if spec.WriterOutPath != literal || spec.WriterDrvPath != "pure" {
		t.Fatalf("did not preserve overlay: %+v", spec)
	}
}
