package nixdata

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"unicode"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
	nixser "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
)

var ErrInvalidModuleData = errors.New("invalid module config data")

// PatchModuleDataChecked restores the original bytes when the new config
// fails its pure evaluation (e.g. an option type error or an untracked
// tree file ignored by a Git flake). Never undo concurrent user edits.
func (s *Store) PatchModuleDataChecked(
	path []string,
	value any,
	check func() error,
) error {
	return s.patchProjectFile(path, func(src []byte, tail []string) ([]byte, error) {
		return patchModuleValue(src, tail, value)
	}, check)
}

// PatchModuleDataReversible lets a caller include an option write in a
// larger project transaction. The returned rollback refuses to replace an
// intervening edit. Hold the project mutation lock until commit or rollback.
func (s *Store) PatchModuleDataReversible(
	path []string,
	value any,
) (func() error, error) {
	return s.ApplyModulePatches([]ModulePatch{{Path: path, Value: value}})
}

func patchModuleLeaf(src []byte, tail []string, value any) ([]byte, error) {
	// A declared empty attrset is a concrete adoption leaf, unlike an
	// empty object in a relative settings patch (which is a no-op).
	if m, ok := value.(map[string]any); ok && len(m) == 0 {
		if len(tail) == 0 {
			return []byte("{}\n"), nil
		}
		return flakeedit.PatchNixPath(src, tail, "{}")
	}
	return patchModuleValue(src, tail, value)
}

// patchProjectFile is the single file-level mutation path for both the v0
// dotted UI editor and v1 literal (multi-leaf) module edits. No formatting
// pass over unrelated expressions; nil from edit means delete this file.
func (s *Store) patchProjectFile(
	path []string,
	edit func([]byte, []string) ([]byte, error),
	check func() error,
) error {
	undo, err := s.changeProjectFile(path, edit)
	if err != nil || check == nil {
		return err
	}
	if err = check(); err != nil {
		if undoErr := undo(); undoErr != nil {
			return errors.New("module config changed during rollback; check project config")
		}
	}
	return err
}

func (s *Store) changeProjectFile(
	path []string,
	edit func([]byte, []string) ([]byte, error),
) (func() error, error) {
	root, err := os.OpenRoot(s.paths.ProjectRoot)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	name, tail, err := modulePatchTarget(root, path)
	if err != nil {
		return nil, err
	}
	mode := os.FileMode(0o600)
	source := []byte("{ }\n")
	var before []byte
	if stat, err := root.Lstat(name); err == nil {
		if !stat.Mode().IsRegular() {
			return nil, errors.New("config target is not a regular file")
		}
		mode = stat.Mode().Perm()
		source, err = root.ReadFile(name)
		if err != nil {
			return nil, err
		}
		before = source
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	modified, err := edit(source, tail)
	if err != nil {
		return nil, err
	}
	change := &moduleFileChange{name: name, mode: mode}
	if bytes.Equal(source, modified) || (before == nil && modified == nil) {
		return func() error { return nil }, nil
	}
	if err := change.replace(root, before, modified); err != nil {
		return nil, err
	}
	return func() error {
		dir, err := os.OpenRoot(s.paths.ProjectRoot)
		if err != nil {
			return err
		}
		defer dir.Close()
		return change.replace(dir, modified, before)
	}, nil
}

func validModuleAttr(key string) bool {
	return key != "" && !strings.ContainsFunc(key, unicode.IsControl) && key != "_type" &&
		key != "_module" &&
		key != "imports"
}

func patchModuleValue(src []byte, path []string, value any) ([]byte, error) {
	switch v := value.(type) {
	case DeleteValue:
		return flakeedit.DeleteNixPath(src, path)
	case map[string]any:
		for _, key := range slices.Sorted(maps.Keys(v)) {
			if !validModuleAttr(key) {
				return nil, ErrInvalidModuleData
			}
			var err error
			src, err = patchModuleValue(src, append(path, key), v[key])
			if err != nil {
				return nil, err
			}
		}
		return src, nil
	}
	var expr string
	var err error
	switch v := value.(type) {
	case string:
		if strings.ContainsRune(v, 0) {
			return nil, ErrInvalidModuleData
		}
		expr = nixser.QuoteString(v)
	case []any:
		// JSON inside a quoted Nix string keeps arbitrary nested keys and
		// multiline strings in arrays literal, including ${...}.
		b, err := json.Marshal(v)
		if err != nil {
			return nil, ErrInvalidModuleData
		}
		expr = "(builtins.fromJSON " + nixser.QuoteString(string(b)) + ")"
	case nil, bool, float64:
		expr, err = nixser.Serialize(v)
	default:
		return nil, ErrInvalidModuleData
	}
	if err != nil {
		return nil, err
	}
	if len(path) == 0 {
		return []byte(expr + "\n"), nil
	}
	return flakeedit.PatchNixPath(src, path, expr)
}

// modulePatchTarget mirrors the Nix loader's top-level tree precedence. An
// existing file config must not be shadowed by creating a fresh tree entity.
func modulePatchTarget(
	root *os.Root,
	path []string,
) (string, []string, error) {
	if len(path) == 0 || ValidateEntityName(path[0]) != nil {
		return "", nil, ErrInvalidModuleData
	}
	for _, k := range path {
		if !validModuleAttr(k) {
			return "", nil, ErrInvalidModuleData
		}
	}
	base := filepath.Join(ConfigDirName, "config.nix")
	tree := filepath.Join(ConfigDirName, TreeDirName)
	entity := filepath.Join(tree, path[0])
	if st, err := root.Stat(entity); err == nil && st.IsDir() {
		if len(path) < 2 {
			return "", nil, ErrInvalidModuleData
		}
		key := path[1]
		if IsMapEntity(path[0]) {
			key = EncodeTreeFileKey(key)
		}
		if !filepath.IsLocal(key) || strings.ContainsAny(key, `/\`) || key == "." {
			return "", nil, ErrInvalidModuleData
		}
		return filepath.Join(entity, key+".nix"), path[2:], nil
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return "", nil, err
	}
	if _, err := root.Stat(entity + ".nix"); err == nil {
		return entity + ".nix", path[1:], nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", nil, err
	}
	source, err := root.ReadFile(base)
	if errors.Is(err, os.ErrNotExist) {
		if info, err := root.Stat(tree); err == nil && info.IsDir() {
			return entity + ".nix", path[1:], nil
		}
		return base, path, nil
	}
	if err != nil {
		return "", nil, err
	}
	if info, err := root.Stat(tree); err == nil && info.IsDir() {
		present, err := flakeedit.HasTopLevelBinding(source, path[0])
		if err != nil {
			return "", nil, err
		}
		if !present {
			return entity + ".nix", path[1:], nil
		}
	}
	if len(path) > 1 {
		target, ok, err := flakeedit.ImportTargetForTopLevelBinding(source, path[0])
		if err != nil {
			return "", nil, err
		}
		if ok {
			if filepath.IsAbs(target) || filepath.Ext(target) != ".nix" {
				return "", nil, errors.New("unsupported module config import")
			}
			name := filepath.Join(ConfigDirName, target)
			if !filepath.IsLocal(name) {
				return "", nil, errors.New("config import outside project")
			}
			if _, err := root.Stat(name); err != nil {
				return "", nil, err
			}
			return name, path[1:], nil
		}
	}
	return base, path, nil
}

func writeModuleSource(
	root *os.Root,
	name string,
	data []byte,
	mode os.FileMode,
) error {
	dir := filepath.Dir(name)
	if err := root.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp := filepath.Join(dir, fmt.Sprintf(".module-%s.tmp", rand.Text()))
	f, err := root.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer root.Remove(tmp)
	_, err = f.Write(data)
	if err == nil {
		err = f.Chmod(mode.Perm())
	}
	if err = errors.Join(err, f.Close()); err != nil {
		return err
	}
	return root.Rename(tmp, name)
}
