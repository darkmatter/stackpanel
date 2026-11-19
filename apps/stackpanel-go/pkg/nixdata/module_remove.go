package nixdata

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"slices"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
)

// A nil after means remove the entire per-entry file. Missing files and paths
// are no-ops; uninstalling must not create an empty .stack/config.nix.
type moduleFileChange struct {
	name          string
	mode          os.FileMode
	before, after []byte
}

// ModulePatch is one literal Nix option assignment from an evaluated
// declaration. DeleteValue removes the binding instead.
type ModulePatch struct {
	Path  []string
	Value any
}

// RemoveModuleData edits just the declaring module's option bindings, using
// the same split/tree layout resolution as module enable/settings writes.
// The caller holds its project mutation lock through flake removal. If that
// removal fails, rollback restores the original source bytes, *unless* the
// user has subsequently edited the affected file.
func (s *Store) RemoveModuleData(paths [][]string) (func() error, error) {
	patches := make([]ModulePatch, len(paths))
	for i, p := range paths {
		patches[i] = ModulePatch{Path: p, Value: DeleteValue{}}
	}
	return s.ApplyModulePatches(patches)
}

// ApplyModulePatches prepares every change before writing. Each target file
// is installed once, even if enable + several adoption choices share it.
// Under the project lock, rollback is safe until the ledger commit succeeds.
func (s *Store) ApplyModulePatches(
	patches []ModulePatch,
) (rollback func() error, err error) {
	root, err := os.OpenRoot(s.paths.ProjectRoot)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	var files []*moduleFileChange
	byName := make(map[string]*moduleFileChange)
	for _, patch := range patches {
		path := patch.Path
		if len(path) == 0 {
			return nil, errors.New("empty module config option path")
		}
		name, tail, err := modulePatchTarget(root, path)
		if err != nil {
			return nil, err
		}
		f := byName[name]
		if f == nil {
			info, err := root.Lstat(name)
			f = &moduleFileChange{name: name, mode: 0o600}
			if err == nil {
				if !info.Mode().IsRegular() {
					return nil, fmt.Errorf("refusing to edit non-regular module config %s", name)
				}
				f.mode = info.Mode().Perm()
				f.before, err = root.ReadFile(name)
				if err != nil {
					return nil, err
				}
				f.after = f.before
			} else if !errors.Is(err, os.ErrNotExist) {
				return nil, err
			}
			byName[name] = f
			files = append(files, f)
		}
		if _, remove := patch.Value.(DeleteValue); remove {
			if len(tail) == 0 {
				f.after = nil
			} else if f.after != nil {
				f.after, err = flakeedit.DeleteNixPath(f.after, tail)
			}
		} else {
			src := f.after
			if src == nil {
				src = []byte("{ }\n")
			}
			f.after, err = patchModuleLeaf(src, tail, patch.Value)
		}
		if err != nil {
			return nil, err
		}
	}
	changed := make([]*moduleFileChange, 0, len(files))
	rollback = func() error {
		dir, err := os.OpenRoot(s.paths.ProjectRoot)
		if err != nil {
			return err
		}
		defer dir.Close()
		var failures error
		for _, f := range slices.Backward(changed) {
			if err := f.replace(dir, f.after, f.before); err != nil {
				failures = errors.Join(failures, fmt.Errorf("restore %s: %w", f.name, err))
			}
		}
		return failures
	}
	for _, f := range files {
		if bytes.Equal(f.after, f.before) && (f.after == nil) == (f.before == nil) {
			continue
		}
		if err := f.replace(root, f.before, f.after); err != nil {
			return nil, errors.Join(err, rollback())
		}
		changed = append(changed, f)
	}
	return rollback, nil
}

func (f *moduleFileChange) replace(root *os.Root, expected, value []byte) error {
	info, err := root.Lstat(f.name)
	switch {
	case errors.Is(err, os.ErrNotExist) && expected == nil:
		// A deleted entry can be restored only if its name remains free.
	case err != nil:
		return err
	case expected == nil || !info.Mode().IsRegular() || info.Mode().Perm() != f.mode:
		return fmt.Errorf("%s changed during module edit", f.name)
	default:
		current, err := root.ReadFile(f.name)
		if err != nil {
			return err
		}
		if !bytes.Equal(current, expected) {
			return fmt.Errorf("%s changed during module edit", f.name)
		}
	}
	if value == nil {
		return root.Remove(f.name)
	}
	return writeModuleSource(root, f.name, value, f.mode)
}
