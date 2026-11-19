package reconcile_test

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
)

func TestSaveDecisionsCreatesCanonicalLedgerOnlyWhenRecording(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	oldPath := filepath.Join(root, ".stackpanel", "reconcile.json")
	if err := os.Mkdir(filepath.Dir(oldPath), 0o755); err != nil {
		t.Fatal(err)
	}
	const oldLedger = `{"version":1,"seen":{"old":{"revision":2,"answer":true}}}`
	writeLedgerFile(t, oldPath, oldLedger)
	ledger := loadLedger(t, root)
	wantPath := filepath.Join(root, ".stack", "reconcile.json")
	if ledger.Path() != wantPath || reconcile.LedgerPath(root) != wantPath {
		t.Fatalf("ledger path = %q; want %q", ledger.Path(), wantPath)
	}
	if err := ledger.SaveDecisions(root, nil); err != nil {
		t.Fatal(err)
	}
	assertAbsent(t, filepath.Dir(ledger.Path()))

	start := time.Now().UTC().Truncate(time.Second)
	records := map[string]reconcile.LedgerEntry{
		"new": {Revision: 4, Answer: false, At: "caller timestamp"},
	}
	if err := ledger.SaveDecisions(root, records); err != nil {
		t.Fatal(err)
	}
	assertLedgerFile(t, oldPath, oldLedger)
	reloaded := loadLedger(t, root)
	entry := reloaded.Seen["new"]
	if when, err := time.Parse(
		time.RFC3339,
		entry.At,
	); err != nil || when.Before(start) ||
		when.After(time.Now()) {
		t.Fatalf("decision timestamp = %q", entry.At)
	}
	if entry.Answer != false || entry.Revision != 4 || ledger.Seen["new"] != entry {
		t.Fatalf("committed decision = %+v, receiver = %+v", entry, ledger)
	}
	// A second commit with the same receiver must preserve the first decision.
	if err := ledger.SaveDecisions(
		root,
		map[string]reconcile.LedgerEntry{"another": {Revision: 1, Answer: "fly"}},
	); err != nil {
		t.Fatal(err)
	}
	seen := loadLedger(t, root).Seen
	if len(seen) != 2 || seen["another"].Answer != "fly" || seen["new"] != entry {
		t.Fatalf("saved entries = %+v", seen)
	}
}

func TestSaveDecisionsRejectsStaleSnapshot(t *testing.T) {
	t.Parallel()
	const current = `{"version":1,"seen":{"old":{"revision":2,"answer":true}}}`
	for _, tc := range []struct{ name, initial, changed string }{
		{"edited after load", current, `{"version":1,"seen":{"old":{"revision":3,"answer":true}}}`},
		{"created after load", "", current},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			dir := filepath.Join(root, ".stack")
			if err := os.Mkdir(dir, 0o755); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "reconcile.json")
			// Leave size, permissions, inode and timestamp unchanged for edits:
			// the saved bytes, not just file metadata, are part of the guard.
			stamp := time.Unix(1_700_000_000, 0)
			write := func(data string) {
				writeLedgerFile(t, path, data)
				if err := os.Chtimes(path, stamp, stamp); err != nil {
					t.Fatal(err)
				}
			}
			if tc.initial != "" {
				write(tc.initial)
			}
			ledger := loadLedger(t, root)
			write(tc.changed)
			err := ledger.SaveDecisions(
				root,
				map[string]reconcile.LedgerEntry{"new": {Revision: 1, Answer: false}},
			)
			if err == nil {
				t.Fatal("saved a decision against a stale snapshot")
			}
			if _, ok := ledger.Seen["new"]; ok {
				t.Fatal("failed save changed the loaded ledger")
			}
			assertLedgerFile(t, path, tc.changed)
		})
	}
}

func TestSaveDecisionsConfinedToLoadedProject(t *testing.T) {
	t.Parallel()
	root, outside := t.TempDir(), t.TempDir()
	dir := filepath.Join(root, ".stack")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	ledger := loadLedger(t, root)
	records := map[string]reconcile.LedgerEntry{"new": {Revision: 1, Answer: true}}
	if err := ledger.SaveDecisions(outside, records); err == nil {
		t.Fatal("accepted a different project root")
	}
	assertAbsent(t, filepath.Dir(reconcile.LedgerPath(outside)))
	if err := os.Remove(dir); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, dir); err != nil {
		t.Fatal(err)
	}
	if err := ledger.SaveDecisions(root, records); err == nil {
		t.Fatal("saved through a config directory symlink out of the project")
	}
	assertAbsent(t, filepath.Join(outside, "reconcile.json"))
	if _, err := reconcile.LoadLedger(root); err == nil {
		t.Fatal("loaded through a config directory symlink out of the project")
	}
}

func TestSaveDecisionsRejectsLinkedLedger(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	path := reconcile.LedgerPath(root)
	if err := os.Mkdir(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	const current = `{"version":1,"seen":{}}`
	writeLedgerFile(t, path, current)
	ledger := loadLedger(t, root)
	// The target is the original file, with identical contents and inode.
	target := filepath.Join(t.TempDir(), "ledger.json")
	if err := os.Rename(path, target); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, path); err != nil {
		t.Fatal(err)
	}
	if err := ledger.SaveDecisions(
		root,
		map[string]reconcile.LedgerEntry{"new": {Answer: false}},
	); err == nil {
		t.Fatal("saved through a ledger symlink")
	}
	if _, err := reconcile.LoadLedger(root); err == nil {
		t.Fatal("loaded through a ledger symlink")
	}
	if link, err := os.Readlink(path); err != nil || link != target {
		t.Fatalf("ledger link = %q, %v", link, err)
	}
	assertLedgerFile(t, target, current)
}

func TestLoadLedgerRejectsUnsupportedVersion(t *testing.T) {
	t.Parallel()
	for _, data := range []string{`{"version":2,"decisions":["keep"]}`, `{"decisions":["keep"]}`} {
		root := t.TempDir()
		path := reconcile.LedgerPath(root)
		if err := os.Mkdir(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		writeLedgerFile(t, path, data)
		if ledger, err := reconcile.LoadLedger(root); err == nil || ledger != nil {
			t.Fatalf("loaded unsupported ledger %s: %+v, %v", data, ledger, err)
		}
		assertLedgerFile(t, path, data)
	}
}

func loadLedger(t *testing.T, root string) *reconcile.Ledger {
	t.Helper()
	ledger, err := reconcile.LoadLedger(root)
	if err != nil {
		t.Fatal(err)
	}
	return ledger
}

func writeLedgerFile(t *testing.T, path, data string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertLedgerFile(t *testing.T, path, want string) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil || string(got) != want {
		t.Fatalf("%s = %q, %v; want %q", path, got, err, want)
	}
}

func assertAbsent(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("expected %s to be absent, got %v", path, err)
	}
}
