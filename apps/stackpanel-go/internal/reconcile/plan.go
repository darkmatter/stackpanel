package reconcile

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/fileops"
)

// PlanEntry mirrors one record of `stackpanel.files._plan`: the reconciler's
// view of a files.entries entry with everything needed to diff against disk
// without building. Content is present for text/lines, Structured for
// json/yaml/toml with a whole-file writer, Ops for path writers.
type PlanEntry struct {
	Path          string              `json:"path"`
	Format        string              `json:"format"`
	Writer        string              `json:"writer"`
	Adopt         string              `json:"adopt"`
	Mode          *string             `json:"mode"`
	BlockLabel    string              `json:"blockLabel"`
	CommentPrefix string              `json:"commentPrefix"`
	Source        *string             `json:"source"`
	Description   *string             `json:"description"`
	Target        *string             `json:"target"`
	Kind          string              `json:"kind"`         // pure | preflight
	ManifestType  string              `json:"manifestType"` // pure | symlink | json-ops | yaml-ops | toml-ops | block | full-copy
	StorePath     *string             `json:"storePath"`
	Content       *string             `json:"content"`
	Structured    any                 `json:"structured"`
	Ops           []fileops.JSONOp    `json:"ops"`
	Collisions    []fileops.Collision `json:"collisions"`
}

// DiffPlan compares a plan (typically from a speculative evaluation) against
// the working tree and returns the changes applying it would make. It reuses
// realized store paths when they exist and falls back to the cheap content
// carried by the plan; only derivation-backed files that are not yet realized
// come back as ChangeUnknown.
func DiffPlan(
	projectRoot, stateDir, reconcilerID string,
	entries []PlanEntry,
) *Diagnosis {
	diag := &Diagnosis{}
	managed := fileops.ManagedPaths(stateDir)

	sorted := append([]PlanEntry{}, entries...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Path < sorted[j].Path })

	for _, e := range sorted {
		abs := filepath.Join(projectRoot, e.Path)
		for _, c := range e.Collisions {
			diag.Findings = append(diag.Findings, collisionFinding(reconcilerID, e.Path, c))
		}

		switch e.ManifestType {
		case "symlink":
			diffSymlink(diag, reconcilerID, e, abs)
		case "pure", "full-copy":
			diffWholeFile(diag, reconcilerID, e, abs, managed)
		case "block":
			diffBlock(diag, reconcilerID, e, abs, managed)
		case "json-ops", "yaml-ops", "toml-ops":
			diffOps(diag, reconcilerID, e, abs, managed)
		default:
			diag.Changes = append(
				diag.Changes,
				Change{
					Reconciler: reconcilerID,
					Kind:       ChangeUnknown,
					Path:       e.Path,
					Summary:    "unsupported entry type " + e.ManifestType,
				},
			)
		}
	}
	return diag
}

func collisionFinding(reconcilerID, path string, c fileops.Collision) Finding {
	var ops []string
	for _, op := range c.Ops {
		v, _ := json.Marshal(op.Value)
		ops = append(ops, fmt.Sprintf("%s %s", op.Op, string(v)))
	}
	return Finding{
		Reconciler: reconcilerID,
		ID:         "collision",
		Severity:   SeverityWarning,
		Title: fmt.Sprintf(
			"%d definitions write %s; the last one wins",
			c.Count,
			strings.Join(c.Path, "."),
		),
		Detail: strings.Join(ops, "\n"),
		Path:   path,
	}
}

func diffSymlink(diag *Diagnosis, id string, e PlanEntry, abs string) {
	target := ""
	if e.Target != nil {
		target = *e.Target
	}
	current, err := os.Readlink(abs)
	switch {
	case err != nil:
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeCreate,
				Path:       e.Path,
				Summary:    "symlink -> " + target,
			},
		)
	case current != target:
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeUpdate,
				Path:       e.Path,
				Summary:    fmt.Sprintf("symlink %s -> %s", current, target),
			},
		)
	}
}

// firstContact reports adopt-policy effects for a file stackpanel does not
// manage yet. Returns false when the entry should be skipped (refused).
func firstContact(
	diag *Diagnosis,
	id string,
	e PlanEntry,
	abs string,
	exists bool,
	managed map[string]string,
) bool {
	if _, tracked := managed[e.Path]; tracked || !exists {
		return true
	}
	switch e.Adopt {
	case "refuse":
		diag.Findings = append(diag.Findings, Finding{
			Reconciler: id,
			ID:         "adopt-refuse",
			Severity:   SeverityError,
			Title:      "refusing to adopt existing file (adopt = \"refuse\")",
			Path:       e.Path,
			Detail:     "remove the file or set adopt = \"backup\" to take it over",
		})
		return false
	case "backup":
		if _, err := os.Stat(abs + ".backup"); err != nil {
			diag.Changes = append(
				diag.Changes,
				Change{
					Reconciler: id,
					Kind:       ChangeBackup,
					Path:       e.Path + ".backup",
					Summary:    "existing file backed up on first contact",
				},
			)
		}
	}
	return true
}

func diffWholeFile(
	diag *Diagnosis,
	id string,
	e PlanEntry,
	abs string,
	managed map[string]string,
) {
	disk, err := os.ReadFile(abs)
	exists := err == nil
	if e.Kind == "preflight" && !firstContact(diag, id, e, abs, exists, managed) {
		return
	}

	expected, known := expectedBytes(e)
	switch {
	case !exists && !known && e.Structured == nil:
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeCreate,
				Path:       e.Path,
				Summary:    describeSource(e),
			},
		)
	case !exists:
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeCreate,
				Path:       e.Path,
				Summary:    describeSource(e),
			},
		)
	case known && bytes.Equal(disk, expected):
		// unchanged
	case known:
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeUpdate,
				Path:       e.Path,
				Summary:    describeSource(e),
			},
		)
	case e.Structured != nil:
		if same, ok := structuredEqual(e.Format, disk, e.Structured); ok && same {
			return
		}
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeUpdate,
				Path:       e.Path,
				Summary:    describeSource(e),
			},
		)
	default:
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeUnknown,
				Path:       e.Path,
				Summary:    "content comes from a derivation that is not realized yet",
			},
		)
	}
}

func diffBlock(
	diag *Diagnosis,
	id string,
	e PlanEntry,
	abs string,
	managed map[string]string,
) {
	disk, err := os.ReadFile(abs)
	exists := err == nil
	begin, _, block, known := blockFor(e)
	if !known {
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeUnknown,
				Path:       e.Path,
				Summary:    "block content comes from a derivation that is not realized yet",
			},
		)
		return
	}
	if exists && !strings.Contains(string(disk), begin) {
		if !firstContact(diag, id, e, abs, true, managed) {
			return
		}
	}
	switch {
	case !exists:
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeCreate,
				Path:       e.Path,
				Summary:    "managed block",
			},
		)
	case !strings.Contains(strings.ReplaceAll(string(disk), "\r\n", "\n"), block):
		diag.Changes = append(
			diag.Changes,
			Change{
				Reconciler: id,
				Kind:       ChangeUpdate,
				Path:       e.Path,
				Summary:    "managed block",
			},
		)
	}
}

func diffOps(
	diag *Diagnosis,
	id string,
	e PlanEntry,
	abs string,
	managed map[string]string,
) {
	disk, err := os.ReadFile(abs)
	exists := err == nil
	if !firstContact(diag, id, e, abs, exists, managed) {
		return
	}
	format := strings.TrimSuffix(e.ManifestType, "-ops")
	doc := map[string]any{}
	if exists {
		decoded, derr := fileops.DecodeDocument(format, disk)
		if derr != nil {
			diag.Findings = append(
				diag.Findings,
				Finding{
					Reconciler: id,
					ID:         "parse",
					Severity:   SeverityError,
					Title:      "cannot parse " + format + " document",
					Path:       e.Path,
					Detail:     derr.Error(),
				},
			)
			return
		}
		doc = decoded
	}
	next, perr := fileops.PreviewOps(doc, e.Ops)
	if perr != nil {
		diag.Findings = append(
			diag.Findings,
			Finding{
				Reconciler: id,
				ID:         "ops",
				Severity:   SeverityError,
				Title:      "cannot apply path operations",
				Path:       e.Path,
				Detail:     perr.Error(),
			},
		)
		return
	}
	summary := fmt.Sprintf("%d managed path(s)", len(e.Ops))
	switch {
	case !exists:
		diag.Changes = append(
			diag.Changes,
			Change{Reconciler: id, Kind: ChangeCreate, Path: e.Path, Summary: summary},
		)
	case !fileops.DocumentsEqual(doc, next):
		diag.Changes = append(
			diag.Changes,
			Change{Reconciler: id, Kind: ChangeUpdate, Path: e.Path, Summary: summary},
		)
	}
}

// expectedBytes returns the exact bytes the entry would write when they are
// knowable without a build: a realized store path, or inline text/lines.
func expectedBytes(e PlanEntry) ([]byte, bool) {
	if e.StorePath != nil {
		if data, err := os.ReadFile(*e.StorePath); err == nil {
			return data, true
		}
	}
	if e.Content != nil {
		return []byte(*e.Content), true
	}
	return nil, false
}

func blockFor(e PlanEntry) (begin, end, block string, ok bool) {
	prefix := e.CommentPrefix
	if prefix == "" {
		prefix = "#"
	}
	label := e.BlockLabel
	if label == "" {
		label = "stackpanel"
	}
	content, known := expectedBytes(e)
	if !known {
		return "", "", "", false
	}
	begin = fmt.Sprintf("%s ── BEGIN %s ──", prefix, label)
	end = fmt.Sprintf("%s ── END %s ──", prefix, label)
	notice := fmt.Sprintf(
		"%s DO NOT EDIT between these markers — managed by stackpanel",
		prefix,
	)
	block = begin + "\n" + notice + "\n" + string(content) + end + "\n"
	return begin, end, block, true
}

func structuredEqual(format string, disk []byte, structured any) (bool, bool) {
	decoded, err := fileops.DecodeDocument(format, disk)
	if err != nil {
		return false, false
	}
	want, ok := structured.(map[string]any)
	if !ok {
		return false, false
	}
	return fileops.DocumentsEqual(decoded, want), true
}

func describeSource(e PlanEntry) string {
	if e.Source != nil && *e.Source != "" {
		return "from " + *e.Source
	}
	return e.Format
}

// sha256File hashes a file; used by the files reconciler to compare disk
// against realized store paths without loading both into memory twice.
func sha256File(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:]), nil
}
