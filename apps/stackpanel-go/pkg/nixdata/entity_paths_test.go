package nixdata

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEntityPathsRejectInvalidSelectors(t *testing.T) {
	store := NewStore(t.TempDir(), nil)
	paths := store.Paths()
	if err := paths.EnsureDir(); err != nil {
		t.Fatal(err)
	}
	const original = "{ name = \"untouched\"; }\n"
	if err := os.WriteFile(paths.ConfigFilePath(), []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"", "../config", "sub/../apps", `sub\apps`, "external-../config"} {
		t.Run(name, func(t *testing.T) {
			if got := paths.EntityPath(name); got != "" {
				t.Errorf("EntityPath returned %q for invalid selector", got)
			}
			if got := paths.ExternalEntityPath(name); got != "" {
				t.Errorf("ExternalEntityPath returned %q for invalid selector", got)
			}
			if paths.IsUsingConsolidatedConfig(name) {
				t.Error("invalid selector was routed to config.nix")
			}
			if got := paths.TreeEntityKeyFilePath(name, "web"); got != "" {
				t.Errorf("tree entry returned %q for invalid selector", got)
			}
			if err := paths.EnsureTreeEntityDir(name); err == nil {
				t.Error("EnsureTreeEntityDir accepted invalid selector")
			}
			if _, err := store.ReadRawNixFile(name); err == nil {
				t.Error("ReadRawNixFile accepted invalid selector")
			}
			if _, err := store.DeleteEntity(name); err == nil {
				t.Error("DeleteEntity accepted invalid selector")
			}
		})
	}
	got, err := os.ReadFile(paths.ConfigFilePath())
	if err != nil || string(got) != original {
		t.Fatalf("config.nix = %q, %v; want original contents", got, err)
	}
}

func TestCustomLegacyEntityRouting(t *testing.T) {
	store := NewStore(t.TempDir(), nil)
	paths := store.Paths()
	if err := os.MkdirAll(paths.LegacyDataDir(), 0o755); err != nil {
		t.Fatal(err)
	}
	const entity = "_custom-2"
	legacy := filepath.Join(paths.LegacyDataDir(), entity+".nix")
	if err := os.WriteFile(legacy, []byte("{}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got, err := store.WriteEntity(entity, "updated"); err != nil || got != legacy {
		t.Fatalf("WriteEntity = %q, %v; want %q", got, err, legacy)
	}
	if got, err := os.ReadFile(legacy); err != nil || strings.TrimSpace(string(got)) != `"updated"` {
		t.Fatalf("legacy contents = %q, %v", got, err)
	}
	if got, err := store.DeleteEntity(entity); err != nil || got != legacy {
		t.Fatalf("DeleteEntity = %q, %v; want %q", got, err, legacy)
	}
	if _, err := os.Stat(legacy); !os.IsNotExist(err) {
		t.Fatalf("legacy file after delete: %v", err)
	}
	if got := paths.EntityPath(entity); got != paths.ConfigFilePath() {
		t.Fatalf("missing legacy entity routed to %q; want config.nix", got)
	}
	if got := paths.ExternalEntityPath("external-2custom"); got != filepath.Join(paths.ExternalDataDir(), "2custom.nix") {
		t.Fatalf("external selector routed to %q", got)
	}
}

func TestDeleteEntityKeepsConfigOnLookupError(t *testing.T) {
	store := NewStore(t.TempDir(), nil)
	paths := store.Paths()
	if err := paths.EnsureDir(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(paths.ConfigFilePath(), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	// A file where the data directory should be makes lookup fail, not just miss.
	if err := os.WriteFile(paths.LegacyDataDir(), []byte("not a directory"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := store.DeleteEntity("custom"); err == nil {
		t.Fatal("expected deletion to report the invalid data directory")
	}
	if got, err := os.ReadFile(paths.ConfigFilePath()); err != nil || string(got) != "{}" {
		t.Fatalf("config after failed delete: %q, %v", got, err)
	}
}

func TestLegacyEntityPreservesProjectSymlink(t *testing.T) {
	root := t.TempDir()
	store := NewStore(root, nil)
	paths := store.Paths()
	if err := os.MkdirAll(paths.LegacyDataDir(), 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(root, "shared.nix")
	if err := os.WriteFile(target, []byte("{}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(paths.LegacyDataDir(), "custom.nix")
	if err := os.Symlink(target, link); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if got, err := store.WriteEntity("custom", "linked"); got != link || err != nil {
		t.Fatalf("WriteEntity = %q, %v; want %q", got, err, link)
	}
	if got, err := os.ReadFile(target); err != nil || strings.TrimSpace(string(got)) != `"linked"` {
		t.Fatalf("linked target = %q, %v", got, err)
	}
}
