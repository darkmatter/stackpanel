// apply.go implements the manifest application engine. The core loop is:
// 1. Load previous state
// 2. Revert entries that were removed or changed type since last run
// 3. Apply each current entry (creating/patching files)
// 4. Persist state for next run

package fileops

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"
)

const stateFilename = "files-preflight-state.json"

// ApplyManifest reconciles the project directory with the manifest. Files that
// were previously managed but are absent from the new manifest are reverted.
// Writes are idempotent: unchanged files are skipped to avoid spurious mtime updates.
func ApplyManifest(projectRoot, stateDir string, manifest Manifest) (Summary, error) {
	if projectRoot == "" {
		return Summary{}, fmt.Errorf("fileops: project root is required")
	}

	absRoot, err := filepath.Abs(projectRoot)
	if err != nil {
		return Summary{}, fmt.Errorf("fileops: resolve project root: %w", err)
	}

	if stateDir == "" {
		stateDir = filepath.Join(absRoot, ".stack", "profile")
	}

	st, err := loadState(stateDir)
	if err != nil {
		return Summary{}, err
	}

	currentByPath := make(map[string]Entry, len(manifest.Files))
	for _, entry := range manifest.Files {
		currentByPath[entry.Path] = entry
	}

	var summary Summary

	// Phase 1: revert entries that were removed or changed type (e.g. json-ops -> block).
	// Type changes require revert-then-reapply because the cleanup logic differs per type.
	for path, prev := range st.Files {
		current, ok := currentByPath[path]
		if ok && current.Type == prev.Type {
			continue
		}
		if err := revertStateEntry(absRoot, path, prev, &summary); err != nil {
			return Summary{}, err
		}
		delete(st.Files, path)
	}

	// Phase 2: apply each entry in manifest order.
	for _, entry := range manifest.Files {
		prev, hasPrev := st.Files[entry.Path]
		next, err := applyEntry(absRoot, entry, prev, hasPrev, &summary)
		if err != nil {
			return Summary{}, err
		}
		st.Files[entry.Path] = next
	}

	if err := saveState(stateDir, st); err != nil {
		return Summary{}, err
	}

	return summary, nil
}

func applyEntry(projectRoot string, entry Entry, prev stateEntry, hasPrev bool, summary *Summary) (stateEntry, error) {
	switch entry.Type {
	case "json-ops":
		return applyJSONOpsEntry(projectRoot, entry, prev, hasPrev, summary)
	case "block":
		return applyBlockEntry(projectRoot, entry, summary)
	case "full-copy":
		return applyFullCopyEntry(projectRoot, entry, prev, hasPrev, summary)
	default:
		return stateEntry{}, fmt.Errorf("fileops: unsupported entry type %q for %s", entry.Type, entry.Path)
	}
}

// applyJSONOpsEntry handles surgical JSON edits. It maintains a "baseline" snapshot
// of the file before our edits so we can restore user-owned keys when our managed
// paths change between runs. The adopt="backup" mode additionally creates a .backup
// file so users can recover their original content.
func applyJSONOpsEntry(projectRoot string, entry Entry, prev stateEntry, hasPrev bool, summary *Summary) (stateEntry, error) {
	targetPath := filepath.Join(projectRoot, entry.Path)
	currentDoc, existed, err := loadJSONObject(targetPath)
	if err != nil {
		return stateEntry{}, err
	}

	normalizedOps, managedPaths, err := normalizeJSONOps(entry.Ops)
	if err != nil {
		return stateEntry{}, fmt.Errorf("fileops: normalize ops for %s: %w", entry.Path, err)
	}

	var baseline map[string]any
	if hasPrev {
		if prev.Type != "json-ops" {
			return stateEntry{}, fmt.Errorf("fileops: previous state for %s has unexpected type %q", entry.Path, prev.Type)
		}
		var ok bool
		baseline, ok = cloneJSONObject(prev.OriginalJSON)
		if !ok {
			return stateEntry{}, fmt.Errorf("fileops: previous state for %s is missing original JSON", entry.Path)
		}
	} else {
		baseline, err = determineJSONBaseline(targetPath, currentDoc, existed, entry.Adopt)
		if err != nil {
			return stateEntry{}, err
		}
		if entry.Adopt == "backup" && existed {
			backupPath, wroteBackup, err := backupFile(targetPath)
			if err != nil {
				return stateEntry{}, err
			}
			if wroteBackup {
				summary.Backups = append(summary.Backups, backupPath)
			}
			prev.BackupPath = backupPath
		}
	}

	if repairedDoc, repairedBaseline, repaired, err := repairManagedOnlyJSON(targetPath, projectRoot, entry.Path, currentDoc, normalizedOps, entry.Adopt, prev); err != nil {
		return stateEntry{}, err
	} else if repaired {
		currentDoc = repairedDoc
		baseline = repairedBaseline
	}

	if !existed {
		currentDoc = cloneMap(baseline)
	}

	stalePaths := diffManagedPaths(prev.ManagedPaths, managedPaths)
	for _, path := range stalePaths {
		if err := restoreJSONPath(currentDoc, baseline, path); err != nil {
			return stateEntry{}, fmt.Errorf("fileops: restore stale path %s in %s: %w", formatPath(path), entry.Path, err)
		}
		summary.Restored = append(summary.Restored, fmt.Sprintf("%s:%s", entry.Path, formatPath(path)))
	}

	for _, op := range normalizedOps {
		if err := applyJSONOp(currentDoc, op); err != nil {
			return stateEntry{}, fmt.Errorf("fileops: apply %s in %s: %w", formatPath(op.Path), entry.Path, err)
		}
	}

	wrote, err := writeCanonicalJSON(targetPath, currentDoc, entry.Mode)
	if err != nil {
		return stateEntry{}, err
	}
	if wrote {
		summary.Writes = append(summary.Writes, targetPath)
	} else {
		summary.Skipped = append(summary.Skipped, targetPath)
	}

	return stateEntry{
		Type:         "json-ops",
		BackupPath:   prev.BackupPath,
		OriginalJSON: cloneMap(baseline),
		ManagedPaths: cloneManagedPaths(managedPaths),
	}, nil
}

// determineJSONBaseline picks the "original" document to diff against. On first
// run with adopt="backup", it prefers the .backup file if it exists (handles the
// case where we previously wrote managed-only content and the original was lost).
func determineJSONBaseline(targetPath string, currentDoc map[string]any, existed bool, adopt string) (map[string]any, error) {
	if existed {
		return cloneMap(currentDoc), nil
	}

	if adopt != "backup" {
		return cloneMap(currentDoc), nil
	}

	backupDoc, backupExists, err := loadJSONObject(targetPath + ".backup")
	if err != nil {
		return nil, err
	}
	if backupExists {
		return cloneMap(backupDoc), nil
	}

	return cloneMap(currentDoc), nil
}

// repairManagedOnlyJSON detects a corrupted state where the on-disk file contains
// only our managed keys (the user's content was lost). This can happen if the state
// file was deleted. It tries to recover from the .backup file or git HEAD.
func repairManagedOnlyJSON(targetPath, projectRoot, entryPath string, currentDoc map[string]any, normalizedOps []JSONOp, adopt string, prev stateEntry) (map[string]any, map[string]any, bool, error) {
	if adopt != "backup" || len(currentDoc) == 0 {
		return nil, nil, false, nil
	}

	managedOnly := map[string]any{}
	for _, op := range normalizedOps {
		if err := applyJSONOp(managedOnly, op); err != nil {
			return nil, nil, false, fmt.Errorf("fileops: compute managed-only JSON for %s: %w", targetPath, err)
		}
	}
	if !reflect.DeepEqual(currentDoc, managedOnly) {
		return nil, nil, false, nil
	}

	backupPath := prev.BackupPath
	if backupPath == "" {
		backupPath = targetPath + ".backup"
	}
	backupDoc, backupExists, err := loadJSONObject(backupPath)
	if err != nil {
		return nil, nil, false, err
	}
	if backupExists && !reflect.DeepEqual(backupDoc, managedOnly) {
		return cloneMap(backupDoc), cloneMap(backupDoc), true, nil
	}

	gitDoc, gitExists, err := loadJSONObjectFromGit(projectRoot, entryPath)
	if err != nil {
		return nil, nil, false, err
	}
	if gitExists && !reflect.DeepEqual(gitDoc, managedOnly) {
		return cloneMap(gitDoc), cloneMap(gitDoc), true, nil
	}

	return nil, nil, false, nil
}

// loadJSONObjectFromGit reads a JSON file from the HEAD commit as a recovery source.
// Returns false if the file doesn't exist in git (not an error).
func loadJSONObjectFromGit(projectRoot, relPath string) (map[string]any, bool, error) {
	cmd := exec.Command("git", "-C", projectRoot, "show", "HEAD:"+filepath.ToSlash(relPath))
	data, err := cmd.Output()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return map[string]any{}, false, nil
		}
		return nil, false, fmt.Errorf("fileops: read %s from git: %w", relPath, err)
	}

	var doc map[string]any
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, false, fmt.Errorf("fileops: parse %s from git: %w", relPath, err)
	}
	if doc == nil {
		doc = map[string]any{}
	}
	return doc, true, nil
}

// applyBlockEntry manages a delimited text block within a file (e.g. .gitignore).
// Content between BEGIN/END markers is replaced; the rest of the file is preserved.
func applyBlockEntry(projectRoot string, entry Entry, summary *Summary) (stateEntry, error) {
	targetPath := filepath.Join(projectRoot, entry.Path)
	managedContent, err := os.ReadFile(entry.StorePath)
	if err != nil {
		return stateEntry{}, fmt.Errorf("fileops: read block content for %s: %w", entry.Path, err)
	}

	beginMarker := fmt.Sprintf("%s ── BEGIN %s ──", defaultString(entry.CommentPrefix, "#"), defaultString(entry.BlockLabel, "stackpanel"))
	endMarker := fmt.Sprintf("%s ── END %s ──", defaultString(entry.CommentPrefix, "#"), defaultString(entry.BlockLabel, "stackpanel"))
	notice := fmt.Sprintf("%s DO NOT EDIT between these markers — managed by stackpanel", defaultString(entry.CommentPrefix, "#"))
	block := beginMarker + "\n" + notice + "\n" + string(managedContent) + endMarker + "\n"

	existing, err := os.ReadFile(targetPath)
	if err != nil && !os.IsNotExist(err) {
		return stateEntry{}, fmt.Errorf("fileops: read %s: %w", entry.Path, err)
	}

	var next string
	if os.IsNotExist(err) {
		next = block
	} else {
		next, _ = upsertManagedBlock(string(existing), block, beginMarker, endMarker)
	}

	wrote, err := writeString(targetPath, next, entry.Mode)
	if err != nil {
		return stateEntry{}, err
	}
	if wrote {
		summary.Writes = append(summary.Writes, targetPath)
	} else {
		summary.Skipped = append(summary.Skipped, targetPath)
	}

	return stateEntry{
		Type:          "block",
		BlockLabel:    entry.BlockLabel,
		CommentPrefix: entry.CommentPrefix,
	}, nil
}

// applyFullCopyEntry overwrites the target with content from a Nix store path.
// If adopt="backup" and this is the first run, the existing file is backed up.
func applyFullCopyEntry(projectRoot string, entry Entry, prev stateEntry, hasPrev bool, summary *Summary) (stateEntry, error) {
	targetPath := filepath.Join(projectRoot, entry.Path)
	if !hasPrev && entry.Adopt == "backup" {
		if _, err := os.Stat(targetPath); err == nil {
			backupPath, wroteBackup, err := backupFile(targetPath)
			if err != nil {
				return stateEntry{}, err
			}
			if wroteBackup {
				summary.Backups = append(summary.Backups, backupPath)
			}
			prev.BackupPath = backupPath
		}
	}

	content, err := os.ReadFile(entry.StorePath)
	if err != nil {
		return stateEntry{}, fmt.Errorf("fileops: read managed content for %s: %w", entry.Path, err)
	}

	wrote, err := writeBytes(targetPath, content, entry.Mode)
	if err != nil {
		return stateEntry{}, err
	}
	if wrote {
		summary.Writes = append(summary.Writes, targetPath)
	} else {
		summary.Skipped = append(summary.Skipped, targetPath)
	}

	return stateEntry{
		Type:       "full-copy",
		BackupPath: prev.BackupPath,
	}, nil
}

// revertStateEntry undoes a previously applied entry. For json-ops, it restores
// each managed path to its baseline value. For blocks, it strips the managed
// section (and deletes the file if nothing remains). For full-copy, it deletes the file.
func revertStateEntry(projectRoot, path string, prev stateEntry, summary *Summary) error {
	switch prev.Type {
	case "json-ops":
		targetPath := filepath.Join(projectRoot, path)
		currentDoc, _, err := loadJSONObject(targetPath)
		if err != nil {
			if os.IsNotExist(err) {
				return nil
			}
			return err
		}
		baseline, ok := cloneJSONObject(prev.OriginalJSON)
		if !ok {
			return fmt.Errorf("fileops: previous JSON state for %s is invalid", path)
		}
		for _, managedPath := range prev.ManagedPaths {
			if err := restoreJSONPath(currentDoc, baseline, managedPath); err != nil {
				return fmt.Errorf("fileops: restore %s in %s: %w", formatPath(managedPath), path, err)
			}
		}
		wrote, err := writeCanonicalJSON(targetPath, currentDoc, "")
		if err != nil {
			return err
		}
		if wrote {
			summary.Restored = append(summary.Restored, targetPath)
		}
		return nil
	case "block":
		targetPath := filepath.Join(projectRoot, path)
		content, err := os.ReadFile(targetPath)
		if err != nil {
			if os.IsNotExist(err) {
				return nil
			}
			return fmt.Errorf("fileops: read %s: %w", path, err)
		}
		beginMarker := fmt.Sprintf("%s ── BEGIN %s ──", defaultString(prev.CommentPrefix, "#"), defaultString(prev.BlockLabel, "stackpanel"))
		endMarker := fmt.Sprintf("%s ── END %s ──", defaultString(prev.CommentPrefix, "#"), defaultString(prev.BlockLabel, "stackpanel"))
		next, changed := removeManagedBlock(string(content), beginMarker, endMarker)
		if !changed {
			return nil
		}
		if strings.TrimSpace(next) == "" {
			if err := os.Remove(targetPath); err != nil && !os.IsNotExist(err) {
				return fmt.Errorf("fileops: remove %s: %w", path, err)
			}
			summary.Removed = append(summary.Removed, targetPath)
			return nil
		}
		wrote, err := writeString(targetPath, next, "")
		if err != nil {
			return err
		}
		if wrote {
			summary.Removed = append(summary.Removed, targetPath)
		}
		return nil
	case "full-copy":
		targetPath := filepath.Join(projectRoot, path)
		if err := os.Remove(targetPath); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("fileops: remove stale %s: %w", path, err)
		}
		summary.Removed = append(summary.Removed, targetPath)
		return nil
	default:
		return fmt.Errorf("fileops: unsupported stale state type %q for %s", prev.Type, path)
	}
}

// normalizeJSONOps deduplicates ops by path (last write wins) and validates
// that no managed path is a prefix of another (which would cause ambiguous ownership).
func normalizeJSONOps(ops []JSONOp) ([]JSONOp, [][]string, error) {
	indexByPath := map[string]int{}
	normalized := make([]JSONOp, 0, len(ops))
	for _, op := range ops {
		if len(op.Path) == 0 {
			return nil, nil, fmt.Errorf("json op %q requires a path", op.Op)
		}
		key := pathKey(op.Path)
		if idx, ok := indexByPath[key]; ok {
			normalized[idx] = cloneJSONOp(op)
			continue
		}
		indexByPath[key] = len(normalized)
		normalized = append(normalized, cloneJSONOp(op))
	}

	paths := make([][]string, 0, len(normalized))
	for _, op := range normalized {
		paths = append(paths, clonePath(op.Path))
	}

	if err := validateNoOverlappingManagedPaths(paths); err != nil {
		return nil, nil, err
	}

	return normalized, paths, nil
}

func validateNoOverlappingManagedPaths(paths [][]string) error {
	for i := 0; i < len(paths); i++ {
		for j := i + 1; j < len(paths); j++ {
			if isPrefixPath(paths[i], paths[j]) || isPrefixPath(paths[j], paths[i]) {
				return fmt.Errorf("overlapping managed JSON paths are not supported: %s and %s", formatPath(paths[i]), formatPath(paths[j]))
			}
		}
	}
	return nil
}

func applyJSONOp(doc map[string]any, op JSONOp) error {
	switch op.Op {
	case "set":
		return setJSONValue(doc, op.Path, cloneValue(op.Value))
	case "merge":
		current, exists := getJSONValue(doc, op.Path)
		if !exists {
			return setJSONValue(doc, op.Path, cloneValue(op.Value))
		}
		merged, err := deepMergeJSON(current, op.Value)
		if err != nil {
			return err
		}
		return setJSONValue(doc, op.Path, merged)
	case "remove":
		return deleteJSONValue(doc, op.Path)
	case "append":
		return appendJSONValue(doc, op.Path, op.Value, false)
	case "appendUnique":
		return appendJSONValue(doc, op.Path, op.Value, true)
	default:
		return fmt.Errorf("unsupported JSON op %q", op.Op)
	}
}

func restoreJSONPath(current map[string]any, baseline map[string]any, path []string) error {
	if original, ok := getJSONValue(baseline, path); ok {
		return setJSONValue(current, path, cloneValue(original))
	}
	return deleteJSONValue(current, path)
}

func loadJSONObject(path string) (map[string]any, bool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return map[string]any{}, false, nil
		}
		return nil, false, fmt.Errorf("fileops: read %s: %w", path, err)
	}

	trimmed := bytes.TrimSpace(data)
	if len(trimmed) == 0 {
		return map[string]any{}, true, nil
	}

	var decoded map[string]any
	if err := json.Unmarshal(trimmed, &decoded); err != nil {
		return nil, true, fmt.Errorf("fileops: parse json %s: %w", path, err)
	}
	if decoded == nil {
		decoded = map[string]any{}
	}
	return decoded, true, nil
}

func writeCanonicalJSON(path string, doc map[string]any, mode string) (bool, error) {
	data, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return false, fmt.Errorf("fileops: marshal %s: %w", path, err)
	}
	data = append(data, '\n')
	return writeBytes(path, data, mode)
}

// writeBytes writes content to path, returning false if the file already has
// identical content (avoids unnecessary mtime changes that trigger file watchers).
func writeBytes(path string, content []byte, mode string) (bool, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return false, fmt.Errorf("fileops: create directory for %s: %w", path, err)
	}

	existing, err := os.ReadFile(path)
	if err == nil && bytes.Equal(existing, content) {
		if mode != "" {
			if err := applyMode(path, mode); err != nil {
				return false, err
			}
		}
		return false, nil
	}
	if err != nil && !os.IsNotExist(err) {
		return false, fmt.Errorf("fileops: read existing %s: %w", path, err)
	}

	fileMode := os.FileMode(0644)
	if mode != "" {
		parsed, err := parseMode(mode)
		if err != nil {
			return false, err
		}
		fileMode = parsed
	}

	if err := os.WriteFile(path, content, fileMode); err != nil {
		return false, fmt.Errorf("fileops: write %s: %w", path, err)
	}
	if mode != "" {
		if err := applyMode(path, mode); err != nil {
			return false, err
		}
	}
	return true, nil
}

func writeString(path string, content string, mode string) (bool, error) {
	return writeBytes(path, []byte(content), mode)
}

// backupFile copies path to path.backup. If the backup already exists, it is
// left untouched (returns false). This is a one-time operation per file.
func backupFile(path string) (string, bool, error) {
	backupPath := path + ".backup"
	if _, err := os.Stat(backupPath); err == nil {
		return backupPath, false, nil
	}
	content, err := os.ReadFile(path)
	if err != nil {
		return "", false, fmt.Errorf("fileops: read %s for backup: %w", path, err)
	}
	if err := os.WriteFile(backupPath, content, 0644); err != nil {
		return "", false, fmt.Errorf("fileops: write backup %s: %w", backupPath, err)
	}
	return backupPath, true, nil
}

func loadState(stateDir string) (stateFile, error) {
	path := filepath.Join(stateDir, stateFilename)
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return stateFile{Version: 1, Files: map[string]stateEntry{}}, nil
		}
		return stateFile{}, fmt.Errorf("fileops: read state: %w", err)
	}

	var st stateFile
	if err := json.Unmarshal(data, &st); err != nil {
		return stateFile{}, fmt.Errorf("fileops: parse state: %w", err)
	}
	if st.Files == nil {
		st.Files = map[string]stateEntry{}
	}
	return st, nil
}

func saveState(stateDir string, st stateFile) error {
	if st.Files == nil {
		st.Files = map[string]stateEntry{}
	}
	st.Version = 1
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		return fmt.Errorf("fileops: create state directory: %w", err)
	}
	data, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		return fmt.Errorf("fileops: marshal state: %w", err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(filepath.Join(stateDir, stateFilename), data, 0644); err != nil {
		return fmt.Errorf("fileops: write state: %w", err)
	}
	return nil
}

// diffManagedPaths returns paths that were managed in the previous run but are
// absent from the current manifest. These need to be restored to baseline values.
func diffManagedPaths(previous [][]string, current [][]string) [][]string {
	currentSet := make(map[string]struct{}, len(current))
	for _, path := range current {
		currentSet[pathKey(path)] = struct{}{}
	}
	var stale [][]string
	for _, path := range previous {
		if _, ok := currentSet[pathKey(path)]; ok {
			continue
		}
		stale = append(stale, clonePath(path))
	}
	sort.Slice(stale, func(i, j int) bool {
		if len(stale[i]) == len(stale[j]) {
			return pathKey(stale[i]) < pathKey(stale[j])
		}
		return len(stale[i]) < len(stale[j])
	})
	return stale
}

func getJSONValue(current any, path []string) (any, bool) {
	if len(path) == 0 {
		return current, true
	}

	switch node := current.(type) {
	case map[string]any:
		next, ok := node[path[0]]
		if !ok {
			return nil, false
		}
		return getJSONValue(next, path[1:])
	case []any:
		index, err := strconv.Atoi(path[0])
		if err != nil || index < 0 || index >= len(node) {
			return nil, false
		}
		return getJSONValue(node[index], path[1:])
	default:
		return nil, false
	}
}

// setJSONValue creates intermediate containers as needed. It infers whether to
// create a map or slice based on whether the next path segment parses as an integer.
func setJSONValue(root map[string]any, path []string, value any) error {
	if len(path) == 0 {
		return fmt.Errorf("empty JSON path")
	}

	var current any = root
	for idx := 0; idx < len(path)-1; idx++ {
		segment := path[idx]
		nextSegment := path[idx+1]

		switch node := current.(type) {
		case map[string]any:
			next, ok := node[segment]
			if !ok || next == nil {
				if _, err := strconv.Atoi(nextSegment); err == nil {
					next = []any{}
				} else {
					next = map[string]any{}
				}
				node[segment] = next
			}
			current = next
		case []any:
			index, err := strconv.Atoi(segment)
			if err != nil {
				return fmt.Errorf("path segment %q is not a valid array index", segment)
			}
			if index < 0 {
				return fmt.Errorf("negative array index %d", index)
			}
			for len(node) <= index {
				node = append(node, nil)
			}
			next := node[index]
			if next == nil {
				if _, err := strconv.Atoi(nextSegment); err == nil {
					next = []any{}
				} else {
					next = map[string]any{}
				}
				node[index] = next
			}
			current = next
		default:
			return fmt.Errorf("cannot descend into non-container at %s", formatPath(path[:idx+1]))
		}
	}

	last := path[len(path)-1]
	switch node := current.(type) {
	case map[string]any:
		node[last] = value
		return nil
	case []any:
		index, err := strconv.Atoi(last)
		if err != nil {
			return fmt.Errorf("path segment %q is not a valid array index", last)
		}
		if index < 0 {
			return fmt.Errorf("negative array index %d", index)
		}
		for len(node) <= index {
			node = append(node, nil)
		}
		node[index] = value
		return nil
	default:
		return fmt.Errorf("cannot set %s on non-container", formatPath(path))
	}
}

func deleteJSONValue(root map[string]any, path []string) error {
	if len(path) == 0 {
		return fmt.Errorf("empty JSON path")
	}
	if len(path) == 1 {
		delete(root, path[0])
		return nil
	}

	parent, ok := getJSONValue(root, path[:len(path)-1])
	if !ok {
		return nil
	}

	last := path[len(path)-1]
	switch node := parent.(type) {
	case map[string]any:
		delete(node, last)
		return nil
	case []any:
		index, err := strconv.Atoi(last)
		if err != nil {
			return fmt.Errorf("path segment %q is not a valid array index", last)
		}
		if index < 0 || index >= len(node) {
			return nil
		}
		copy(node[index:], node[index+1:])
		node[len(node)-1] = nil
		node = node[:len(node)-1]
		return setJSONValue(root, path[:len(path)-1], node)
	default:
		return fmt.Errorf("cannot delete %s from non-container", formatPath(path))
	}
}

func appendJSONValue(root map[string]any, path []string, value any, unique bool) error {
	current, exists := getJSONValue(root, path)
	if !exists {
		return setJSONValue(root, path, []any{cloneValue(value)})
	}

	array, ok := current.([]any)
	if !ok {
		return fmt.Errorf("append target %s is not an array", formatPath(path))
	}

	candidate := cloneValue(value)
	if unique {
		for _, item := range array {
			if jsonEqual(item, candidate) {
				return nil
			}
		}
	}

	array = append(array, candidate)
	return setJSONValue(root, path, array)
}

// deepMergeJSON recursively merges incoming into existing. Non-map values are
// overwritten; maps are merged key-by-key. Arrays are NOT merged - incoming wins.
func deepMergeJSON(existing any, incoming any) (any, error) {
	existingMap, existingOK := existing.(map[string]any)
	incomingMap, incomingOK := incoming.(map[string]any)
	if !existingOK || !incomingOK {
		return cloneValue(incoming), nil
	}

	merged := cloneMap(existingMap)
	for key, value := range incomingMap {
		if current, ok := merged[key]; ok {
			next, err := deepMergeJSON(current, value)
			if err != nil {
				return nil, err
			}
			merged[key] = next
			continue
		}
		merged[key] = cloneValue(value)
	}
	return merged, nil
}

func upsertManagedBlock(content string, block string, beginMarker string, endMarker string) (string, bool) {
	if !strings.Contains(content, beginMarker) {
		trimmed := strings.TrimRight(content, "\n")
		if trimmed == "" {
			return block, true
		}
		return trimmed + "\n\n" + block, true
	}

	lines := strings.Split(normalizeNewlines(content), "\n")
	beginIdx, endIdx := findManagedBlock(lines, beginMarker, endMarker)
	if beginIdx == -1 || endIdx == -1 {
		return content, false
	}

	replacement := strings.Split(strings.TrimSuffix(block, "\n"), "\n")
	next := append([]string{}, lines[:beginIdx]...)
	next = append(next, replacement...)
	next = append(next, lines[endIdx+1:]...)
	result := strings.Join(next, "\n")
	if !strings.HasSuffix(result, "\n") {
		result += "\n"
	}
	return result, result != normalizeNewlines(content)
}

func removeManagedBlock(content string, beginMarker string, endMarker string) (string, bool) {
	lines := strings.Split(normalizeNewlines(content), "\n")
	beginIdx, endIdx := findManagedBlock(lines, beginMarker, endMarker)
	if beginIdx == -1 || endIdx == -1 {
		return content, false
	}

	start := beginIdx
	if start > 0 && lines[start-1] == "" {
		start--
	}

	next := append([]string{}, lines[:start]...)
	next = append(next, lines[endIdx+1:]...)

	result := strings.Join(next, "\n")
	result = strings.TrimLeft(result, "\n")
	if strings.TrimSpace(result) == "" {
		return "", true
	}
	if !strings.HasSuffix(result, "\n") {
		result += "\n"
	}
	return result, true
}

func findManagedBlock(lines []string, beginMarker string, endMarker string) (int, int) {
	beginIdx := -1
	endIdx := -1
	for idx, line := range lines {
		if line == beginMarker {
			beginIdx = idx
			continue
		}
		if beginIdx >= 0 && line == endMarker {
			endIdx = idx
			break
		}
	}
	return beginIdx, endIdx
}

func applyMode(path string, mode string) error {
	parsed, err := parseMode(mode)
	if err != nil {
		return err
	}
	if err := os.Chmod(path, parsed); err != nil {
		return fmt.Errorf("fileops: chmod %s: %w", path, err)
	}
	return nil
}

func parseMode(mode string) (os.FileMode, error) {
	parsed, err := strconv.ParseUint(mode, 8, 32)
	if err != nil {
		return 0, fmt.Errorf("fileops: parse mode %q: %w", mode, err)
	}
	return os.FileMode(parsed), nil
}

func defaultString(value string, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func cloneJSONObject(value any) (map[string]any, bool) {
	if value == nil {
		return map[string]any{}, true
	}
	object, ok := value.(map[string]any)
	if !ok {
		return nil, false
	}
	return cloneMap(object), true
}

func cloneMap(input map[string]any) map[string]any {
	if input == nil {
		return map[string]any{}
	}
	output := make(map[string]any, len(input))
	for key, value := range input {
		output[key] = cloneValue(value)
	}
	return output
}

func cloneValue(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		return cloneMap(typed)
	case []any:
		cloned := make([]any, len(typed))
		for idx, item := range typed {
			cloned[idx] = cloneValue(item)
		}
		return cloned
	default:
		return typed
	}
}

func cloneManagedPaths(paths [][]string) [][]string {
	cloned := make([][]string, len(paths))
	for idx, path := range paths {
		cloned[idx] = clonePath(path)
	}
	return cloned
}

func clonePath(path []string) []string {
	cloned := make([]string, len(path))
	copy(cloned, path)
	return cloned
}

func cloneJSONOp(op JSONOp) JSONOp {
	return JSONOp{
		Op:    op.Op,
		Path:  clonePath(op.Path),
		Value: cloneValue(op.Value),
	}
}

// pathKey produces a map key from a JSON path. Uses null byte separator so
// path segments containing dots don't collide.
func pathKey(path []string) string {
	return strings.Join(path, "\x00")
}

func formatPath(path []string) string {
	return strings.Join(path, ".")
}

func isPrefixPath(prefix []string, path []string) bool {
	if len(prefix) >= len(path) {
		return false
	}
	for idx := range prefix {
		if prefix[idx] != path[idx] {
			return false
		}
	}
	return true
}

// jsonEqual compares values by marshaling to JSON. This handles type mismatches
// (e.g. float64 vs int) that reflect.DeepEqual would consider unequal.
func jsonEqual(left any, right any) bool {
	leftJSON, _ := json.Marshal(left)
	rightJSON, _ := json.Marshal(right)
	return bytes.Equal(leftJSON, rightJSON)
}

func normalizeNewlines(value string) string {
	return strings.ReplaceAll(value, "\r\n", "\n")
}
