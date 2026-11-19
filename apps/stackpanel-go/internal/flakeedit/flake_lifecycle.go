package flakeedit

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/gofrs/flock"
)

// InstallModule installs the input, its dependencies and the requested import.
// Reconciled declarations are a no-op unless flake.lock is missing. Optional
// validators follow the semantics of UninstallRegistryModule, even on a no-op.
func InstallModule(
	ctx context.Context,
	projectRoot string,
	input FlakeInput,
	importPath string,
	deps []FlakeInput,
	validate ...func() error,
) error {
	return mutateModule(
		ctx,
		projectRoot,
		input.Name,
		installAction,
		func(e *FlakeEditor) ([]byte, error) {
			return e.installModule(input, importPath, deps)
		},
		validate...)
}

// UninstallRegistryModule checks registry ownership before removing the input.
// Validators see the new flake and lock while the project lock is held. They
// must not re-enter lifecycle operations on this project. Failure rolls back
// our writes, but does not clobber intervening user edits.
func UninstallRegistryModule(
	ctx context.Context,
	projectRoot string,
	input FlakeInput,
	importPath string,
	validate ...func() error,
) error {
	return mutateModule(
		ctx,
		projectRoot,
		input.Name,
		uninstallAction,
		func(e *FlakeEditor) ([]byte, error) {
			return e.uninstallRegistryModule(input, importPath)
		},
		validate...)
}

// UpdateModuleWithImports refreshes the input and reconciles the requested
// release's imports and dependencies in the same transaction.
func UpdateModuleWithImports(
	ctx context.Context,
	projectRoot string,
	input FlakeInput,
	previousImportPath, importPath string,
	deps []FlakeInput,
	validate ...func() error,
) error {
	return mutateModule(
		ctx,
		projectRoot,
		input.Name,
		updateAction,
		func(e *FlakeEditor) ([]byte, error) {
			return e.updateModuleWithImports(input, previousImportPath, importPath, deps)
		},
		validate...)
}

type moduleAction int

const (
	installAction moduleAction = iota
	uninstallAction
	updateAction
)

// A single flake input ID, not an option, input path or arbitrary flake URL.
var lifecycleInputID = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_-]*$`)

type moduleEdit func(*FlakeEditor) ([]byte, error)

func mutateModule(
	ctx context.Context,
	root, name string,
	action moduleAction,
	edit moduleEdit,
	validate ...func() error,
) error {
	if !lifecycleInputID.MatchString(name) {
		return fmt.Errorf("invalid flake input name %q", name)
	}
	return withModuleLock(ctx, root, func(root string) error {
		return mutateLockedModule(ctx, root, name, action, edit, validate)
	})
}

type moduleScopeKey struct{}

type moduleProjectScope struct {
	root     string
	lifetime context.Context
	borrow   sync.Mutex
}

// WithModuleProject holds the lifecycle lock over preflight, mutations and
// caller cleanup. Pass the supplied child context to same-project operations.
// Use it sequentially inside fn only; do not share it with background work.
// Returning an error does not undo operations that have already succeeded.
func WithModuleProject(
	ctx context.Context,
	root string,
	fn func(context.Context) error,
) error {
	return withModuleLock(ctx, root, func(root string) error {
		child, cancel := context.WithCancel(ctx)
		scope := &moduleProjectScope{root: root, lifetime: child}
		defer func() {
			// Revoke even forks that stripped cancellation with WithoutCancel.
			// A borrow racing the end of fn must finish before the OS unlock.
			cancel()
			scope.borrow.Lock()
			scope.borrow.Unlock()
		}()
		return fn(context.WithValue(child, moduleScopeKey{}, scope))
	})
}

func withModuleLock(ctx context.Context, root string, fn func(string) error) error {
	if root == "" {
		return errors.New("missing project root")
	}
	root, err := filepath.Abs(root)
	if err != nil {
		return err
	}
	root, err = filepath.EvalSymlinks(root)
	if err != nil {
		return err
	}
	if scope, _ := ctx.Value(moduleScopeKey{}).(*moduleProjectScope); scope != nil &&
		scope.root == root {
		if !scope.borrow.TryLock() {
			return errors.New("module project context must be used sequentially")
		}
		defer scope.borrow.Unlock()
		if err := scope.lifetime.Err(); err != nil {
			return err
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		return fn(root)
	}

	// Lock the directory inode: aliases of the project share the lock, there's
	// no lockfile to unlink/recreate, and replacing flake.nix doesn't unlock it.
	guard := flock.New(
		root,
		flock.SetFlag(os.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW),
	)
	locked, err := guard.TryLockContext(ctx, 25*time.Millisecond)
	if err != nil {
		return fmt.Errorf("lock project %s: %w", root, err)
	}
	if !locked {
		return fmt.Errorf("could not lock project %s", root)
	}
	defer guard.Close()
	return fn(root)
}

func mutateLockedModule(
	ctx context.Context,
	root, name string,
	action moduleAction,
	edit moduleEdit,
	validate []func() error,
) (result error) {
	source, err := snapshotFlakeFile(filepath.Join(root, "flake.nix"), false)
	if err != nil {
		return err
	}
	if source.info == nil {
		return fmt.Errorf("%s: %w", source.path, os.ErrNotExist)
	}
	modified, err := editFlakeSource(source.data, edit)
	if err != nil {
		return err
	}
	changed := !bytes.Equal(source.data, modified)
	if !changed && action == uninstallAction {
		return validateModule(ctx, validate)
	}

	lock := flakeFileSnapshot{path: filepath.Join(root, "flake.lock")}
	if !changed && action == installAction {
		info, err := os.Lstat(lock.path)
		if err == nil {
			if !info.Mode().IsRegular() {
				return fmt.Errorf("%s is not a regular file", lock.path)
			}
			return validateModule(ctx, validate)
		}
		if !errors.Is(err, os.ErrNotExist) {
			return err
		}
		// No lock yet: publish with the original absent-file guard below.
	} else {
		lock, err = snapshotFlakeFile(lock.path, true)
		if err != nil {
			return err
		}
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	currentSource := source
	if changed {
		currentSource, err = source.replace(modified, source.info.Mode().Perm())
		if err != nil {
			return err
		}
		defer currentSource.restoreOnError(&result, source)
	}

	staged, err := runModuleNix(ctx, root, name, action)
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	// A text editor or standalone Nix process need not participate in our
	// advisory lock. Don't publish a lock computed against stale inputs.
	if err := currentSource.check(false); err != nil {
		return err
	}
	currentLock := lock
	if lock.info == nil || !bytes.Equal(lock.data, staged.data) {
		mode := staged.info.Mode().Perm()
		if lock.info != nil {
			mode = lock.info.Mode().Perm()
		}
		currentLock, err = lock.replace(staged.data, mode)
		if err != nil {
			return err
		}
		defer currentLock.restoreOnError(&result, lock)
	} else if err := lock.check(false); err != nil {
		return err
	}

	if err := validateModule(ctx, validate); err != nil {
		return err
	}
	if len(validate) != 0 {
		if err := currentSource.check(false); err != nil {
			return err
		}
		return currentLock.check(false)
	}
	return nil
}

func validateModule(ctx context.Context, validators []func() error) error {
	for _, validate := range validators {
		if err := ctx.Err(); err != nil {
			return err
		}
		if validate == nil {
			return errors.New("nil module validator")
		}
		if err := validate(); err != nil {
			return fmt.Errorf("validate module change: %w", err)
		}
	}
	return ctx.Err()
}

func editFlakeSource(
	source []byte,
	edit func(*FlakeEditor) ([]byte, error),
) ([]byte, error) {
	editor, err := NewFlakeEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()
	if editor.HasParseErrors() {
		return nil, errors.New("flake.nix contains syntax errors; refusing to edit")
	}
	modified, err := edit(editor)
	if err != nil || bytes.Equal(modified, source) {
		return modified, err
	}
	parsed, err := NewFlakeEditor(modified)
	if err != nil {
		return nil, err
	}
	defer parsed.Close()
	if parsed.HasParseErrors() {
		return nil, errors.New("edited flake.nix contains syntax errors; refusing to write")
	}
	return modified, nil
}

func runModuleNix(
	ctx context.Context,
	root, name string,
	action moduleAction,
) (flakeFileSnapshot, error) {
	// Nix reads the project's normal flake.lock. Only its output is redirected
	// to a fresh path. Keep the stage outside the flake source being evaluated.
	base, err := filepath.Abs(os.TempDir())
	if err != nil {
		return flakeFileSnapshot{}, err
	}
	dir, err := os.MkdirTemp(base, "stackpanel-lock-*")
	if err != nil {
		return flakeFileSnapshot{}, err
	}
	defer os.RemoveAll(dir)
	out := filepath.Join(dir, "flake.lock")
	var args []string
	switch action {
	case installAction:
		args = []string{"flake", "lock", "--update-input", name}
	case uninstallAction:
		args = []string{"flake", "lock"}
	case updateAction:
		args = []string{"flake", "update", name}
	}
	args = append(args, "--output-lock-file", out)
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Dir = root
	cmd.WaitDelay = 2 * time.Second
	if _, err := cmd.Output(); err != nil {
		if ctx.Err() != nil {
			return flakeFileSnapshot{}, ctx.Err()
		}
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			return flakeFileSnapshot{}, fmt.Errorf(
				"nix flake %s: %w: %s",
				args[1],
				err,
				strings.TrimSpace(string(exit.Stderr)),
			)
		}
		return flakeFileSnapshot{}, fmt.Errorf("nix flake %s: %w", args[1], err)
	}
	staged, err := snapshotFlakeFile(out, false)
	if err != nil {
		return flakeFileSnapshot{}, err
	}
	if staged.info == nil || !json.Valid(staged.data) {
		return flakeFileSnapshot{}, errors.New(
			"nix did not produce a valid staged lock file",
		)
	}
	return staged, nil
}

// info == nil denotes an absent file. Compare identity and metadata as well as
// contents: an editor can replace a file with identical bytes, or chmod it.
type flakeFileSnapshot struct {
	path string
	info os.FileInfo
	data []byte
}

func snapshotFlakeFile(path string, writable bool) (flakeFileSnapshot, error) {
	s := flakeFileSnapshot{path: path}
	flags := os.O_RDONLY
	if writable {
		flags = os.O_RDWR // check actual access without truncating the file
	}
	// Do not follow links (including dangling ones), or block on a FIFO.
	f, err := os.OpenFile(path, flags|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return s, err
	}
	defer f.Close()
	s.info, err = f.Stat()
	if err != nil {
		return s, err
	}
	if !s.info.Mode().IsRegular() {
		return s, fmt.Errorf("%s is not a regular file", path)
	}
	if writable && s.info.Mode().Perm()&0o222 == 0 {
		return s, fmt.Errorf("%s is read-only: %w", path, os.ErrPermission)
	}
	s.data, err = io.ReadAll(f)
	if err != nil {
		return s, err
	}
	latest, err := os.Lstat(path)
	if err != nil {
		return s, err
	}
	if !sameFlakeFile(s.info, latest) {
		return s, fmt.Errorf("%s changed during read", path)
	}
	return s, nil
}

func sameFlakeFile(a, b os.FileInfo) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return os.SameFile(a, b) && a.Mode() == b.Mode() && a.Size() == b.Size() &&
		a.ModTime().Equal(b.ModTime())
}

func (s flakeFileSnapshot) check(writable bool) error {
	current, err := snapshotFlakeFile(s.path, writable)
	if err != nil {
		return err
	}
	if !sameFlakeFile(s.info, current.info) || !bytes.Equal(s.data, current.data) {
		return fmt.Errorf("%s changed concurrently; leaving it untouched", s.path)
	}
	return nil
}

// Prepare the replacement before checking the guard, so that check/rename are
// adjacent. For a previously absent lock, link publishes atomically without
// replacing a concurrent creation. POSIX has no general compare-and-rename
// for existing files; our directory lock serializes participating writers.
func (s flakeFileSnapshot) replace(
	data []byte,
	mode os.FileMode,
) (flakeFileSnapshot, error) {
	f, err := os.CreateTemp(filepath.Dir(s.path), ".stackpanel-flake-*")
	if err != nil {
		return flakeFileSnapshot{}, err
	}
	defer os.Remove(f.Name())
	_, err = f.Write(data)
	if err == nil {
		err = f.Chmod(mode)
	}
	var info os.FileInfo
	if err == nil {
		info, err = f.Stat()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return flakeFileSnapshot{}, err
	}
	if err := s.check(true); err != nil {
		return flakeFileSnapshot{}, err
	}
	if s.info == nil {
		err = os.Link(f.Name(), s.path)
	} else {
		err = os.Rename(f.Name(), s.path)
	}
	if err != nil {
		return flakeFileSnapshot{}, err
	}
	return flakeFileSnapshot{path: s.path, data: data, info: info}, nil
}

func (s flakeFileSnapshot) restoreOnError(result *error, before flakeFileSnapshot) {
	if *result == nil {
		return
	}
	var err error
	if before.info != nil {
		_, err = s.replace(before.data, before.info.Mode().Perm())
	} else if err = s.check(true); err == nil {
		err = os.Remove(s.path)
	}
	if err != nil {
		*result = errors.Join(*result, fmt.Errorf("could not restore %s: %w", s.path, err))
	}
}
