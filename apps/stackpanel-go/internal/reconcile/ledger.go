package reconcile

import (
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
)

// LedgerEntry records that an offer was shown at a revision and what the user
// said. It records what the user has BEEN SHOWN, not what they want: an offer
// often maps to no single config key, so a decline must not assert "never".
type LedgerEntry struct {
	Revision int    `json:"revision"`
	Answer   any    `json:"answer"`
	At       string `json:"at,omitempty"`
}

// Ledger is `.stack/reconcile.json`: the discovery ledger for adoption offers.
type Ledger struct {
	Version int                    `json:"version"`
	Seen    map[string]LedgerEntry `json:"seen"`

	path       string
	root       string
	rootInfo   os.FileInfo
	configInfo os.FileInfo
	current    ledgerFile
}

const (
	ledgerVersion = 1
	ledgerName    = "reconcile.json"
)

// LedgerPath is the project's .stack/reconcile.json.
func LedgerPath(projectRoot string) string {
	return filepath.Join(projectRoot, nixdata.ConfigDirName, ledgerName)
}

// LoadLedger reads the current ledger without creating any files.
func LoadLedger(projectRoot string) (*Ledger, error) {
	root, err := filepath.Abs(projectRoot)
	if err != nil {
		return nil, err
	}
	project, err := os.OpenRoot(root)
	if err != nil {
		return nil, err
	}
	defer project.Close()
	rootInfo, err := project.Stat(".")
	if err != nil {
		return nil, err
	}
	l := &Ledger{
		path:     LedgerPath(projectRoot),
		root:     root,
		rootInfo: rootInfo,
	}
	dir, err := project.OpenRoot(nixdata.ConfigDirName)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	if dir != nil {
		defer dir.Close()
		l.configInfo, err = dir.Stat(".")
		if err != nil {
			return nil, err
		}
		l.current, err = readLedgerFile(dir, false)
		if err != nil {
			return nil, err
		}
	}
	if l.current.info != nil {
		if err := json.Unmarshal(l.current.data, l); err != nil {
			return nil, fmt.Errorf("parse %s: %w", l.path, err)
		}
		if l.Version != ledgerVersion {
			return nil, fmt.Errorf("%s: unsupported ledger version %d", l.path, l.Version)
		}
	} else {
		l.Version = ledgerVersion
	}
	if l.Seen == nil {
		l.Seen = map[string]LedgerEntry{}
	}
	return l, nil
}

// Path is where Save writes.
func (l *Ledger) Path() string {
	return l.path
}

// ShouldOffer decides whether an addon is presented. Never seen: yes. Seen at
// an older revision: yes (the author bumped it). Seen at this revision: only
// with reconsider.
func (l *Ledger) ShouldOffer(id string, revision int, reconsider bool) (bool, string) {
	entry, seen := l.Seen[id]
	switch {
	case !seen:
		return true, "new"
	case entry.Revision < revision:
		return true, "revised"
	case reconsider:
		return true, "reconsider"
	default:
		return false, ""
	}
}

// Record stores the answer shown for an offer at a revision.
func (l *Ledger) Record(id string, revision int, answer any, now time.Time) {
	l.Seen[id] = LedgerEntry{
		Revision: revision,
		Answer:   answer,
		At:       now.UTC().Format(time.RFC3339),
	}
}

// SaveDecisions commits a batch against the snapshot taken by LoadLedger.
// The caller holds the selected project's lock. A stale snapshot must be
// reloaded, not merged: the offers themselves may have changed. An empty
// batch is a no-op.
func (l *Ledger) SaveDecisions(root string, records map[string]LedgerEntry) error {
	if len(records) == 0 {
		return nil
	}
	if l == nil || l.rootInfo == nil {
		return errors.New("recording decisions requires a loaded ledger")
	}
	next := *l
	next.Seen = make(map[string]LedgerEntry, len(l.Seen)+len(records))
	maps.Copy(next.Seen, l.Seen)
	now := time.Now()
	for id, record := range records {
		next.Record(id, record.Revision, record.Answer, now)
	}
	if err := next.save(root); err != nil {
		return err
	}
	*l = next
	return nil
}

// Save writes the recorded ledger with the same snapshot checks as SaveDecisions.
// Callers serializing concurrent writes must hold the project lock across the save.
func (l *Ledger) Save() error {
	if l == nil || l.rootInfo == nil {
		return errors.New("saving requires a loaded ledger")
	}
	return l.save(l.root)
}
