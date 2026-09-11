package cmd

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"time"
)

// setupGitGuard protects preexisting edits without reverting anything. Clean
// tracked files remain editable. Only this guard may add temporary intent entries
// for newly created Nix inputs. Successful setup retains these entries so the
// next shell can evaluate the new files; Close cleans them up after a failed run.
type setupGitGuard struct {
	root, target string
	head         string
	index        map[string][]setupIndexEntry
	protected    map[string]setupFileState
	owned        map[string][]setupIndexEntry
}

type setupIndexEntry struct {
	Record string // mode, blob ID and merge stage
	Flags  uint64 // semantic flags, excluding cached filesystem metadata
}

const setupIntentToAdd = 0x20000000

type setupFileState struct {
	Exists bool
	Mode   os.FileMode
	Hash   [sha256.Size]byte
	Link   string
}

func captureSetupGit(ctx context.Context, target string) (*setupGitGuard, error) {
	target, err := filepath.EvalSymlinks(target)
	if err != nil {
		return nil, err
	}
	guard := &setupGitGuard{target: target, owned: map[string][]setupIndexEntry{}}
	root, err := setupGitCommand(ctx, target, "rev-parse", "--show-toplevel")
	if err != nil {
		if strings.Contains(err.Error(), "not a git repository") {
			return guard, nil
		}
		return nil, err
	}
	guard.root = strings.TrimSuffix(string(root), "\n")
	guard.head, err = setupGitHead(ctx, guard.root)
	if err != nil {
		return nil, err
	}
	guard.index, err = setupReadIndex(ctx, guard.root)
	if err != nil {
		return nil, err
	}
	guard.protected = map[string]setupFileState{}
	for _, args := range [][]string{
		{"diff", "--name-only", "--no-renames", "-z", "--"},
		{"diff", "--cached", "--name-only", "--no-renames", "-z", "--"},
		{"ls-files", "--others", "--exclude-standard", "-z"},
	} {
		data, err := setupGitCommand(ctx, guard.root, args...)
		if err != nil {
			return nil, err
		}
		for _, path := range setupGitPaths(data) {
			state, err := setupReadFileState(filepath.Join(guard.root, path))
			if err != nil {
				return nil, fmt.Errorf("preserve existing Git edit %q: %w", path, err)
			}
			guard.protected[path] = state
		}
	}
	return guard, nil
}

func (g *setupGitGuard) Check(ctx context.Context) error {
	if g.root == "" {
		return nil
	}
	head, err := setupGitHead(ctx, g.root)
	if err != nil {
		return err
	}
	if head != g.head {
		return errors.New("onboarding changed Git HEAD; existing history was not preserved (nothing was reverted)")
	}
	current, err := setupReadIndex(ctx, g.root)
	if err != nil {
		return err
	}
	paths := map[string]bool{}
	for path := range g.index {
		paths[path] = true
	}
	for path := range current {
		paths[path] = true
	}
	for path := range g.owned {
		paths[path] = true
	}
	for _, path := range sortedKeys(paths) {
		want := g.index[path]
		if own, ok := g.owned[path]; ok {
			want = own
		}
		if !reflect.DeepEqual(current[path], want) {
			return fmt.Errorf("onboarding changed Git staging for %q; existing index was not preserved (nothing was reverted)", path)
		}
	}
	for _, path := range sortedKeys(g.protected) {
		state, err := setupReadFileState(filepath.Join(g.root, path))
		if err != nil || state != g.protected[path] {
			return fmt.Errorf("onboarding changed preexisting user edits in %q; restore those edits before retrying (nothing was reverted)", path)
		}
	}
	return nil
}

// AddNixInputs exposes only new onboarding inputs to pure Git-backed evaluation.
// Existing untracked files are deliberately excluded: adding them would change
// the user's original index. Generated files, state, keys and profiles stay out.
func (g *setupGitGuard) AddNixInputs(ctx context.Context, requiredFiles ...string) error {
	if err := g.Check(ctx); err != nil || g.root == "" {
		return err
	}
	data, err := setupGitCommand(ctx, g.root, "ls-files", "--others", "--exclude-standard", "-z")
	if err != nil {
		return err
	}
	var paths []string
	accepted := make(map[string]bool, len(requiredFiles))
	for _, path := range requiredFiles {
		if filepath.IsLocal(path) {
			accepted[filepath.Clean(path)] = true
		}
	}
	for _, path := range setupGitPaths(data) {
		if _, existed := g.protected[path]; existed {
			continue
		}
		rel, err := filepath.Rel(g.target, filepath.Join(g.root, path))
		if err == nil && !setupGeneratedPath(rel) && (setupNixInput(rel) || accepted[rel]) {
			paths = append(paths, path)
		}
	}
	if len(paths) == 0 {
		return nil
	}
	sort.Strings(paths)
	_, addErr := setupGitCommand(ctx, g.root, append([]string{"add", "--intent-to-add", "--"}, paths...)...)
	// Record even partially added entries so deferred cleanup can remove them.
	// Cancellation can arrive after Git commits its index, so this bookkeeping
	// gets its own short deadline instead of inheriting the cancelled context.
	readCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	current, err := setupReadIndex(readCtx, g.root)
	if err != nil {
		return err
	}
	for _, path := range paths {
		entries := current[path]
		if len(entries) == 1 && entries[0].Flags&setupIntentToAdd != 0 {
			g.owned[path] = entries
		}
	}
	if addErr != nil {
		return addErr
	}
	return g.Check(ctx)
}

func (g *setupGitGuard) Close(ctx context.Context) error {
	if g.root == "" || len(g.owned) == 0 {
		return nil
	}
	current, err := setupReadIndex(ctx, g.root)
	if err != nil {
		return err
	}
	var remove []string
	for _, path := range sortedKeys(g.owned) {
		// If someone staged actual content meanwhile, preserve it. Check reports
		// the violation separately; cleanup must never undo new user staging.
		if reflect.DeepEqual(current[path], g.owned[path]) {
			remove = append(remove, path)
		}
	}
	if len(remove) == 0 {
		return nil
	}
	_, err = setupGitCommand(ctx, g.root, append([]string{"update-index", "--force-remove", "--"}, remove...)...)
	if err == nil {
		for _, path := range remove {
			delete(g.owned, path)
		}
	}
	return err
}

func setupNixInput(path string) bool {
	path = filepath.ToSlash(path)
	if path == ".." || strings.HasPrefix(path, "../") {
		return false
	}
	if setupGeneratedPath(path) {
		return false
	}
	return strings.HasSuffix(path, ".nix") || filepath.Base(path) == "flake.lock" || strings.HasPrefix(path, ".stack/")
}

func setupGeneratedPath(path string) bool {
	path = filepath.ToSlash(path)
	for _, generated := range []string{".stack/gen/", ".stack/profile/", ".stack/state/", ".stack/keys/", "packages/gen/env/"} {
		if strings.HasPrefix(path, generated) {
			return true
		}
	}
	return false
}

func setupReadFileState(path string) (setupFileState, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return setupFileState{}, nil
	}
	if err != nil {
		return setupFileState{}, err
	}
	state := setupFileState{Exists: true, Mode: info.Mode().Type() | info.Mode().Perm()}
	if info.Mode()&os.ModeSymlink != 0 {
		state.Link, err = os.Readlink(path)
		return state, err
	}
	if !info.Mode().IsRegular() {
		return state, errors.New("cannot safely snapshot a dirty directory or special file")
	}
	file, err := os.Open(path)
	if err != nil {
		return state, err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return state, err
	}
	copy(state.Hash[:], hash.Sum(nil))
	return state, nil
}

func setupReadIndex(ctx context.Context, root string) (map[string][]setupIndexEntry, error) {
	data, err := setupGitCommand(ctx, root, "ls-files", "--stage", "--debug", "-z")
	if err != nil {
		return nil, err
	}
	entries := map[string][]setupIndexEntry{}
	for len(data) > 0 {
		end := bytes.IndexByte(data, 0)
		if end < 0 {
			return nil, errors.New("invalid Git index record")
		}
		record, path, ok := strings.Cut(string(data[:end]), "\t")
		if !ok {
			return nil, errors.New("invalid Git index path")
		}
		data = data[end+1:]
		marker := []byte("\tflags: ")
		start := bytes.Index(data, marker)
		if start < 0 {
			return nil, errors.New("Git did not report index flags")
		}
		data = data[start+len(marker):]
		end = bytes.IndexByte(data, '\n')
		if end < 0 {
			return nil, errors.New("invalid Git index flags")
		}
		flags, err := strconv.ParseUint(string(data[:end]), 16, 64)
		if err != nil {
			return nil, fmt.Errorf("parse Git index flags: %w", err)
		}
		// Preserve assume-unchanged, skip-worktree and intent-to-add. Cached
		// stat fields and refresh flags may change during harmless Git reads.
		flags &= 0x8000 | 0x40000000 | setupIntentToAdd
		entries[path] = append(entries[path], setupIndexEntry{Record: record, Flags: flags})
		data = data[end+1:]
	}
	return entries, nil
}

func setupGitHead(ctx context.Context, root string) (string, error) {
	head, err := setupGitCommand(ctx, root, "rev-parse", "--verify", "--quiet", "HEAD")
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) || exit.ExitCode() != 1 {
			return "", err
		}
	}
	branch, err := setupGitCommand(ctx, root, "symbolic-ref", "--quiet", "HEAD")
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) || exit.ExitCode() != 1 {
			return "", err
		}
	}
	return string(head) + string(branch), nil
}

func setupGitPaths(data []byte) []string {
	var paths []string
	for _, path := range bytes.Split(data, []byte{0}) {
		if len(path) > 0 {
			paths = append(paths, string(path))
		}
	}
	return paths
}

func setupGitCommand(ctx context.Context, root string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "git", append([]string{"--literal-pathspecs", "-C", root}, args...)...)
	for _, value := range os.Environ() {
		key, _, _ := strings.Cut(value, "=")
		switch key {
		case "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR":
			continue
		}
		cmd.Env = append(cmd.Env, value)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	data, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("git %s: %w\n%s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return data, nil
}
