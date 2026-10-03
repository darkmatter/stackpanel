package cmd

import (
	"os"
	"path/filepath"
	"testing"

	svc "github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
)

// Every checkout of a project (e.g. each git worktree) links the same
// generated snippet into the shared sites.d/, but Caddy rejects the whole
// config if a domain is defined twice or an imported link dangles.
func TestLinkCaddySitesAcrossCheckouts(t *testing.T) {
	root := t.TempDir()
	prevConfigDir, prevSitesDir := caddyConfigDir, caddySitesDir
	prevProject, prevBaseDir := svc.GetProjectRoot(), svc.BaseDir
	t.Cleanup(func() {
		caddyConfigDir, caddySitesDir = prevConfigDir, prevSitesDir
		svc.InitForProject(prevProject)
		svc.BaseDir = prevBaseDir
	})
	caddyConfigDir = filepath.Join(root, "caddy")
	caddySitesDir = filepath.Join(caddyConfigDir, "sites.d")

	const site = "docs_example_localhost.caddy"
	checkout := func(name string) string {
		dir := filepath.Join(root, name)
		gen := filepath.Join(dir, ".stack", "gen", "caddy")
		if err := os.MkdirAll(gen, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(gen, site), []byte("docs.example.localhost {\n}\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	mainDir, worktreeDir := checkout("main"), checkout("worktree")
	mainLink := filepath.Join(caddySitesDir, "main__"+site)
	worktreeLink := filepath.Join(caddySitesDir, "worktree__"+site)
	linked := func(link string) bool {
		_, err := os.Lstat(link)
		return err == nil
	}

	// A link into a deleted checkout is pruned.
	if err := os.MkdirAll(caddySitesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	dangling := filepath.Join(caddySitesDir, "deleted__"+site)
	if err := os.Symlink(filepath.Join(root, "deleted", site), dangling); err != nil {
		t.Fatal(err)
	}
	svc.InitForProject(mainDir)
	linkCaddySites("")
	if linked(dangling) || !linked(mainLink) {
		t.Fatalf("main: want dangling link pruned and %s linked", mainLink)
	}

	// Another checkout leaves an already-linked domain alone...
	svc.InitForProject(worktreeDir)
	linkCaddySites("")
	if linked(worktreeLink) || !linked(mainLink) {
		t.Fatal("worktree: want the domain to stay linked from main only")
	}

	// ...unless the domain is named explicitly, which takes it over.
	linkCaddySites("docs.example.localhost")
	if !linked(worktreeLink) || linked(mainLink) {
		t.Fatal("worktree: want explicit add to move the domain to the worktree")
	}

	// Re-linking a checkout that already has its link clears other copies.
	if err := os.Symlink(filepath.Join(mainDir, ".stack", "gen", "caddy", site), mainLink); err != nil {
		t.Fatal(err)
	}
	linkCaddySites("")
	if !linked(worktreeLink) || linked(mainLink) {
		t.Fatal("worktree: want the duplicate link from main removed")
	}
}
