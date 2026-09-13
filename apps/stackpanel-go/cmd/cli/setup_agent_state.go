package cmd

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/gofrs/flock"
	"github.com/spf13/cobra"
)

// The host owns this manifest outside the coding agent's writable repository.
// It records progress, never proof of success: doctor must run again on resume.
type setupManifest struct {
	Version       int                     `json:"version"`
	Root          string                  `json:"root"`
	Agent         string                  `json:"agent,omitempty"`
	Stage         string                  `json:"stage"`
	Options       setupSavedOptions       `json:"options"`
	Request       setupagent.SetupRequest `json:"request"`
	Plan          *setupagent.Plan        `json:"plan,omitempty"`
	Pending       []setupagent.Question   `json:"pendingQuestions,omitempty"`
	PendingReply  *setupReplyRecovery     `json:"pendingReply,omitempty"`
	Conversation  []setupagent.Exchange   `json:"conversation,omitempty"`
	Failure       string                  `json:"verificationFailure,omitempty"`
	LastError     string                  `json:"lastError,omitempty"`
	StudioSession string                  `json:"studioSession,omitempty"`
	Git           *setupGitCheckpoint     `json:"git,omitempty"`
	GitViolation  *setupGitCheckpoint     `json:"gitViolation,omitempty"`
	UpdatedAt     time.Time               `json:"updatedAt"`
	path          string
}

type setupSavedOptions struct {
	Flake       string   `json:"flake"`
	Template    string   `json:"template"`
	With        []string `json:"with,omitempty"`
	Without     []string `json:"without,omitempty"`
	AddonValues []string `json:"addonValues,omitempty"`
	Force       bool     `json:"force"`
	NoRuntime   bool     `json:"noRuntime"`
	NoBrowser   bool     `json:"noBrowser"`
	StudioURL   string   `json:"studioURL,omitempty"`
	AgentPort   int      `json:"agentPort,omitempty"`
}

type setupGitCheckpoint struct {
	Root      string                       `json:"root"`
	Head      string                       `json:"head"`
	Editable  map[string]setupFileState    `json:"editable"`
	Protected map[string]setupFileState    `json:"protected,omitempty"`
	Index     map[string][]setupIndexEntry `json:"index"`
}

func setupStateDirectory() string {
	return filepath.Join(filepath.Dir(userconfig.GetConfigPath()), "setup")
}

func setupStatePath(root string) string {
	return filepath.Join(setupStateDirectory(), fmt.Sprintf("%x.json", sha256.Sum256([]byte(root))))
}

func readSetupJSON(path string, value any) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	d := json.NewDecoder(io.LimitReader(f, 16<<20))
	d.DisallowUnknownFields()
	if err := d.Decode(value); err != nil {
		return fmt.Errorf("read setup state %s: %w", path, err)
	}
	if err := d.Decode(new(any)); err != io.EOF {
		return fmt.Errorf("invalid trailing setup state in %s", path)
	}
	return nil
}

func writeSetupJSON(path string, value any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".setup-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	encoder := json.NewEncoder(f)
	encoder.SetIndent("", "  ")
	err = encoder.Encode(value)
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err = errors.Join(err, closeErr); err != nil {
		return err
	}
	if err := os.Rename(f.Name(), path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func loadSetupManifest(root string) (*setupManifest, error) {
	s := &setupManifest{path: setupStatePath(root)}
	if err := readSetupJSON(s.path, s); err != nil {
		return nil, err
	}
	if s.Version != 1 || s.Root != root || (s.Request.Root != "" && s.Request.Root != root) {
		return nil, fmt.Errorf("unsupported or mismatched setup manifest: %s", s.path)
	}
	switch s.Stage {
	case "inspection", "review", "apply", "repair", "verify", "runtime", "complete":
	default:
		return nil, fmt.Errorf("invalid setup stage in %s", s.path)
	}
	if s.Stage != "inspection" && s.Plan == nil {
		return nil, fmt.Errorf("missing saved plan in %s", s.path)
	}
	if s.Plan != nil {
		if err := reconcile.ValidateExpectations(s.Plan.Expectations); err != nil {
			return nil, fmt.Errorf("invalid saved plan: %w", err)
		}
	}
	return s, nil
}

func (s *setupManifest) save() error {
	s.UpdatedAt = time.Now().UTC()
	return writeSetupJSON(s.path, s)
}

// Take a new Git baseline on every invocation. Only unchanged, checkpointed
// setup output is editable again; user edits/staging since a checkpoint remain
// protected. An abrupt kill can leave uncheckpointed output, which is preserved
// conservatively too. We never reset HEAD, restore files, or unstage user work.
func (s *setupManifest) restoreGit(g *setupGitGuard) {
	if s.Git == nil || s.Git.Root != g.root || s.Git.Head != g.head {
		return
	}
	for path, state := range s.Git.Editable {
		if current, ok := g.protected[path]; ok && current == state && reflect.DeepEqual(g.index[path], s.Git.Index[path]) {
			delete(g.protected, path)
		}
	}
}

func (s *setupManifest) checkGitViolation(ctx context.Context) error {
	if previous := s.GitViolation; previous != nil {
		guard := &setupGitGuard{root: previous.Root, head: previous.Head, index: previous.Index, protected: previous.Protected}
		if err := guard.Check(ctx); err != nil {
			return err
		}
		s.GitViolation = nil
	}
	return nil
}

func (s *setupManifest) checkpoint(ctx context.Context, g *setupGitGuard) error {
	if err := g.Check(ctx); err != nil {
		return err
	}
	current, err := captureSetupGit(ctx, s.Root)
	if err != nil {
		return err
	}
	snapshot := &setupGitCheckpoint{Root: g.root, Head: g.head, Editable: map[string]setupFileState{}, Index: current.index}
	for path, state := range current.protected {
		if _, protected := g.protected[path]; !protected {
			snapshot.Editable[path] = state
		}
	}
	s.Git = snapshot
	return s.save()
}

func setupStateLock(path string) (*flock.Flock, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	lock := flock.New(path)
	locked, err := lock.TryLock()
	if err != nil || !locked {
		lock.Close()
		if err != nil {
			return nil, err
		}
		return nil, errors.New("another setup is already running for this target")
	}
	return lock, nil
}

// A separate pointer makes repeating --tmp from the same working directory find
// its unfinished repository. The per-repository lock also covers direct retries.
func openSetupManifest(ctx context.Context, opts setupFlags) (*setupManifest, func(), bool, error) {
	var locks []*flock.Flock
	closeLocks := func() {
		for i := len(locks) - 1; i >= 0; i-- {
			locks[i].Close()
		}
	}
	ok := false
	defer func() {
		if !ok {
			closeLocks()
		}
	}()
	var root, pointer string
	if opts.tmp {
		cwd, err := os.Getwd()
		if err != nil {
			return nil, nil, false, err
		}
		cwd, err = filepath.EvalSymlinks(cwd)
		if err != nil {
			return nil, nil, false, err
		}
		pointer = filepath.Join(setupStateDirectory(), fmt.Sprintf("tmp-%x.json", sha256.Sum256([]byte(cwd))))
		lock, err := setupStateLock(pointer + ".lock")
		if err != nil {
			return nil, nil, false, err
		}
		locks = append(locks, lock)
		if !opts.restart {
			var saved struct {
				Root string `json:"root"`
			}
			if err := readSetupJSON(pointer, &saved); err == nil {
				s, err := loadSetupManifest(saved.Root)
				if err != nil {
					return nil, nil, false, fmt.Errorf("load temporary setup: %w; use --restart for a fresh repository", err)
				}
				if s.Stage != "complete" {
					root = s.Root
				}
			} else if !os.IsNotExist(err) {
				return nil, nil, false, err
			}
		}
	} else if opts.newDir != "" {
		candidate, err := filepath.Abs(opts.newDir)
		if err != nil {
			return nil, nil, false, err
		}
		if canonical, err := filepath.EvalSymlinks(candidate); err == nil {
			if _, err := os.Stat(setupStatePath(canonical)); err == nil {
				root = canonical // A matching manifest permits a nonempty --new target.
			}
		}
	}
	if root == "" {
		var err error
		root, err = prepareAgentSetupTarget(ctx, opts)
		if err != nil {
			return nil, nil, false, err
		}
	}
	root, err := filepath.EvalSymlinks(root)
	if err != nil {
		return nil, nil, false, fmt.Errorf("saved setup repository is unavailable: %w; use --restart for a fresh run", err)
	}
	lock, err := setupStateLock(setupStatePath(root) + ".lock")
	if err != nil {
		return nil, nil, false, err
	}
	locks = append(locks, lock)
	var s *setupManifest
	resuming := false
	if !opts.restart {
		s, err = loadSetupManifest(root)
		if err != nil && !os.IsNotExist(err) {
			return nil, nil, false, fmt.Errorf("%w; use --restart to review a new plan without deleting repository files", err)
		}
		resuming = err == nil
	}
	if s == nil {
		s = &setupManifest{Version: 1, Root: root, Stage: "inspection", path: setupStatePath(root), Options: savedSetupOptions(opts)}
		if err := s.save(); err != nil {
			return nil, nil, false, err
		}
	}
	if pointer != "" {
		if err := writeSetupJSON(pointer, struct {
			Root string `json:"root"`
		}{root}); err != nil {
			return nil, nil, false, err
		}
	}
	ok = true
	return s, closeLocks, resuming, nil
}

func savedSetupOptions(opts setupFlags) setupSavedOptions {
	return setupSavedOptions{opts.flake, opts.template, opts.with, opts.without, opts.addonValues, opts.force,
		opts.noRuntime, opts.noBrowser, opts.studioURL, opts.agentPort}
}

func (s *setupManifest) restoreOptions(cmd *cobra.Command, opts *setupFlags) error {
	// Explicit configuration changes require a newly reviewed plan. Omitted flags
	// inherit saved selections; runtime endpoints and scope may change on retry.
	for _, flag := range []struct {
		name           string
		current, saved any
	}{
		{"flake", opts.flake, s.Options.Flake}, {"template", opts.template, s.Options.Template},
		{"with", opts.with, s.Options.With}, {"without", opts.without, s.Options.Without},
		{"addon", opts.addonValues, s.Options.AddonValues}, {"force", opts.force, s.Options.Force},
	} {
		if cmd.Flags().Changed(flag.name) && !reflect.DeepEqual(flag.current, flag.saved) {
			return fmt.Errorf("--%s differs from the saved setup selections; use --restart to review a new plan", flag.name)
		}
	}
	opts.flake, opts.template = s.Options.Flake, s.Options.Template
	opts.with, opts.without, opts.addonValues, opts.force = s.Options.With, s.Options.Without, s.Options.AddonValues, s.Options.Force
	if !cmd.Flags().Changed("no-runtime") {
		opts.noRuntime = s.Options.NoRuntime
	}
	if !cmd.Flags().Changed("no-browser") {
		opts.noBrowser = s.Options.NoBrowser
	}
	if !cmd.Flags().Changed("studio-url") {
		opts.studioURL = s.Options.StudioURL
	}
	if !cmd.Flags().Changed("agent-port") {
		opts.agentPort = s.Options.AgentPort
	}
	if opts.experimentalAgent == "auto" && s.Agent != "" {
		opts.experimentalAgent = s.Agent
	}
	s.Options = savedSetupOptions(*opts)
	return nil
}
