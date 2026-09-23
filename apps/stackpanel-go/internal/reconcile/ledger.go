package reconcile

import (
	"encoding/json"
	"errors"
	"fmt"
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
// It generalizes the old `.stack/addons.json` marker (auto-migrated on read).
type Ledger struct {
	Version int                    `json:"version"`
	Seen    map[string]LedgerEntry `json:"seen"`

	path         string
	migratedFrom string
}

const ledgerVersion = 1

// LedgerPath is <config dir>/reconcile.json (next to config.nix, committed).
func LedgerPath(projectRoot string) string {
	return filepath.Join(
		filepath.Dir(nixdata.NewPaths(projectRoot).ConfigFilePath()),
		"reconcile.json",
	)
}

// LegacyMarkerPath is the pre-ledger `.stack/addons.json`.
func LegacyMarkerPath(projectRoot string) string {
	return filepath.Join(
		filepath.Dir(nixdata.NewPaths(projectRoot).ConfigFilePath()),
		"addons.json",
	)
}

// LoadLedger reads reconcile.json, or migrates addons.json when only the old
// marker exists. Legacy entries carried no revision; they are stamped with the
// addon's current revision (when known, else 1) so migration never re-nags.
func LoadLedger(projectRoot string, currentRevisions map[string]int) (*Ledger, error) {
	l := &Ledger{
		Version: ledgerVersion,
		Seen:    map[string]LedgerEntry{},
		path:    LedgerPath(projectRoot),
	}

	data, err := os.ReadFile(l.path)
	switch {
	case err == nil:
		if err := json.Unmarshal(data, l); err != nil {
			return nil, fmt.Errorf("parse %s: %w", l.path, err)
		}
		if l.Seen == nil {
			l.Seen = map[string]LedgerEntry{}
		}
		l.path = LedgerPath(projectRoot)
		return l, nil
	case !errors.Is(err, os.ErrNotExist):
		return nil, fmt.Errorf("read %s: %w", l.path, err)
	}

	legacyPath := LegacyMarkerPath(projectRoot)
	legacy, err := os.ReadFile(legacyPath)
	if errors.Is(err, os.ErrNotExist) {
		return l, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", legacyPath, err)
	}
	var marker struct {
		Addons map[string]any `json:"addons"`
	}
	if err := json.Unmarshal(legacy, &marker); err != nil {
		return nil, fmt.Errorf("parse %s: %w", legacyPath, err)
	}
	for id, answer := range marker.Addons {
		rev := 1
		if r, ok := currentRevisions[id]; ok && r > 0 {
			rev = r
		}
		l.Seen[id] = LedgerEntry{Revision: rev, Answer: answer}
	}
	l.migratedFrom = legacyPath
	return l, nil
}

// MigratedFrom returns the legacy marker path when this ledger was converted
// from addons.json during load (empty otherwise).
func (l *Ledger) MigratedFrom() string {
	return l.migratedFrom
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

// Save writes reconcile.json and removes a migrated addons.json so there is a
// single source of truth.
func (l *Ledger) Save() error {
	l.Version = ledgerVersion
	data, err := json.MarshalIndent(struct {
		Version int                    `json:"version"`
		Seen    map[string]LedgerEntry `json:"seen"`
	}{l.Version, l.Seen}, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(l.path), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(l.path, append(data, '\n'), 0o644); err != nil {
		return err
	}
	if l.migratedFrom != "" {
		if err := os.Remove(l.migratedFrom); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove migrated %s: %w", l.migratedFrom, err)
		}
		l.migratedFrom = ""
	}
	return nil
}
