package reconcile

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// FilesReconciler is the Go port of check-files-drift: it compares every pure
// (whole-file, unadopted) entry of the current generation against disk and
// detects stale files left by the previous generation. Apply delegates to the
// `write-files` script so there is exactly one writer.
type FilesReconciler struct{}

const filesID = "files"

// ID implements Reconciler.
func (r *FilesReconciler) ID() string { return filesID }

// manifestFile is the pure-files manifest Nix writes (files.json, version 2).
type manifestFile struct {
	Version int             `json:"version"`
	Files   []manifestEntry `json:"files"`
}

type manifestEntry struct {
	Path          string  `json:"path"`
	Type          string  `json:"type"`
	Format        string  `json:"format"`
	Writer        string  `json:"writer"`
	Managed       string  `json:"managed"`
	BlockLabel    string  `json:"blockLabel"`
	CommentPrefix string  `json:"commentPrefix"`
	Target        *string `json:"target"`
	StorePath     *string `json:"storePath"`
	Source        *string `json:"source"`
}

func (m manifestEntry) writer() string {
	if m.Writer != "" {
		return m.Writer
	}
	if m.Managed != "" {
		return m.Managed
	}
	return "full"
}

func (m manifestEntry) isSymlink() bool {
	return m.Format == "symlink" || m.Type == "symlink"
}

func readManifest(path string) (*manifestFile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m manifestFile
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("parse files manifest %s: %w", path, err)
	}
	return &m, nil
}

// Diagnose implements Reconciler.
func (r *FilesReconciler) Diagnose(ctx *Context) (*Diagnosis, error) {
	manifestPath := ctx.Getenv("STACKPANEL_FILES_MANIFEST")
	if manifestPath == "" {
		return &Diagnosis{
			Notes: []string{
				"skipped: STACKPANEL_FILES_MANIFEST unset (not inside the devshell, or an older stackpanel)",
			},
		}, nil
	}
	current, err := readManifest(manifestPath)
	if err != nil {
		return nil, err
	}

	diag := &Diagnosis{}
	currentPaths := map[string]bool{}
	entries := append([]manifestEntry{}, current.Files...)
	sort.Slice(entries, func(i, j int) bool { return entries[i].Path < entries[j].Path })

	for _, e := range entries {
		currentPaths[e.Path] = true
		abs := filepath.Join(ctx.ProjectRoot, e.Path)
		summary := ""
		if e.Source != nil && *e.Source != "" {
			summary = "from " + *e.Source
		}
		switch {
		case e.isSymlink():
			target := ""
			if e.Target != nil {
				target = *e.Target
			}
			link, err := os.Readlink(abs)
			if err != nil {
				diag.Changes = append(
					diag.Changes,
					Change{
						Reconciler: filesID,
						Kind:       ChangeCreate,
						Path:       e.Path,
						Summary:    "symlink -> " + target,
					},
				)
			} else if link != target {
				diag.Changes = append(
					diag.Changes,
					Change{
						Reconciler: filesID,
						Kind:       ChangeUpdate,
						Path:       e.Path,
						Summary:    fmt.Sprintf("symlink %s -> %s", link, target),
					},
				)
			}
		case e.writer() == "full" && e.StorePath != nil:
			want, err := os.ReadFile(*e.StorePath)
			if err != nil {
				diag.Changes = append(
					diag.Changes,
					Change{
						Reconciler: filesID,
						Kind:       ChangeUnknown,
						Path:       e.Path,
						Summary:    "store path not realized: " + *e.StorePath,
					},
				)
				continue
			}
			got, err := os.ReadFile(abs)
			switch {
			case err != nil:
				diag.Changes = append(
					diag.Changes,
					Change{
						Reconciler: filesID,
						Kind:       ChangeCreate,
						Path:       e.Path,
						Summary:    summary,
					},
				)
			case !bytes.Equal(got, want):
				diag.Changes = append(
					diag.Changes,
					Change{
						Reconciler: filesID,
						Kind:       ChangeUpdate,
						Path:       e.Path,
						Summary:    summary,
					},
				)
			}
		}
	}

	// Stale files: written by the previous generation, absent from this one.
	previousPath := filepath.Join(ctx.StateDir, "files.json")
	if previous, err := readManifest(previousPath); err == nil {
		stale := append([]manifestEntry{}, previous.Files...)
		sort.Slice(stale, func(i, j int) bool { return stale[i].Path < stale[j].Path })
		for _, old := range stale {
			if currentPaths[old.Path] {
				continue
			}
			abs := filepath.Join(ctx.ProjectRoot, old.Path)
			if _, err := os.Lstat(abs); err != nil {
				continue
			}
			if old.writer() == "block" {
				diag.Changes = append(
					diag.Changes,
					Change{
						Reconciler: filesID,
						Kind:       ChangeDelete,
						Path:       old.Path,
						Summary:    "stale managed block",
					},
				)
			} else {
				diag.Changes = append(
					diag.Changes,
					Change{
						Reconciler: filesID,
						Kind:       ChangeDelete,
						Path:       old.Path,
						Summary:    "no longer generated",
					},
				)
			}
		}
	} else if !os.IsNotExist(err) {
		diag.Notes = append(diag.Notes, "previous manifest unreadable: "+err.Error())
	}

	return diag, nil
}

// Apply implements Reconciler by running the generation's write-files script.
func (r *FilesReconciler) Apply(ctx *Context) (*ApplyResult, error) {
	if ctx.Getenv("STACKPANEL_FILES_MANIFEST") == "" {
		return &ApplyResult{Notes: []string{"skipped: not inside the devshell"}}, nil
	}
	writer, err := exec.LookPath("write-files")
	if err != nil {
		return nil, fmt.Errorf("write-files not on PATH; enter the devshell first")
	}
	return runWriteFiles(ctx, writer)
}

// runWriteFiles executes a write-files binary with the project root and state
// dir exported, parsing its "  write <path>" lines into applied changes.
func runWriteFiles(ctx *Context, writer string) (*ApplyResult, error) {
	cmd := exec.CommandContext(ctx.Ctx, writer)
	cmd.Dir = ctx.ProjectRoot
	cmd.Env = append(
		os.Environ(),
		"STACKPANEL_ROOT="+ctx.ProjectRoot,
		"STACKPANEL_STATE_DIR="+ctx.StateDir,
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("write-files: %w\n%s", err, strings.TrimSpace(string(out)))
	}
	res := &ApplyResult{}
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "write "):
			res.Applied = append(
				res.Applied,
				Change{Reconciler: filesID, Kind: ChangeUpdate, Path: strings.Fields(line)[1]},
			)
		case strings.HasPrefix(line, "remove "):
			res.Applied = append(
				res.Applied,
				Change{Reconciler: filesID, Kind: ChangeDelete, Path: strings.Fields(line)[1]},
			)
		case strings.HasPrefix(line, "files:"):
			res.Notes = append(res.Notes, line)
		}
	}
	return res, nil
}
