package project

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFlakeOnlyProjectRecognition(t *testing.T) {
	root := t.TempDir()
	for _, folder := range []string{".stack-unknown", ".stackpanel"} {
		if err := os.Mkdir(filepath.Join(root, folder), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, folder, "config.nix"), []byte("{}"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for _, tc := range []struct {
		flake string
		want  bool
	}{
		{`{ outputs = { self }: import ./.stack-unknown/config.nix; }`, false},
		{`{ outputs = { self }: import ./.stackpanel/config.nix; }`, false},
		{`{ inputs.stackpanel.url = "path:../framework"; outputs = _: {}; }`, true},
		{`{ outputs = inputs: inputs.stackpanel.lib.mkFlake { inherit inputs; }; }`, true},
		{`{ outputs = { self }: { stackpanelConfig.name = "example"; }; }`, true},
	} {
		file := filepath.Join(root, "flake.nix")
		if err := os.WriteFile(file, []byte(tc.flake), 0o644); err != nil {
			t.Fatal(err)
		}
		if got, _ := checkFlakeForStackpanelWithOptions(file, ValidationOptions{SkipNixEval: true}); got != tc.want {
			t.Errorf("recognized %s: got %v, want %v", tc.flake, got, tc.want)
		}
	}
}
