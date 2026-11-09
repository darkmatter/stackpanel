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

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/gofrs/flock"
	"github.com/spf13/cobra"
)

// setupStage is the manifest's resume point. Stages advance
// inspection → review → apply → verify → runtime → complete; problems found
// by verify move to repair, which returns to verify.
type setupStage string

const (
	stageInspection setupStage = "inspection"
	stageReview     setupStage = "review"
	stageApply      setupStage = "apply"
	stageRepair     setupStage = "repair"
	stageVerify     setupStage = "verify"
	stageRuntime    setupStage = "runtime"
	stageComplete   setupStage = "complete"
)

// The host keeps this manifest outside the repository. It records progress,
// never proof of success: doctor runs again on resume.
type setupManifest struct {
	Version       int                     `json:"version"`
	Root          string                  `json:"root"`
	Agent         string                  `json:"agent,omitempty"`
	Stage         setupStage              `json:"stage"`
	Options       setupSavedOptions       `json:"options"`
	Request       setupagent.SetupRequest `json:"request"`
	Plan          *setupagent.Plan        `json:"plan,omitempty"`
	Pending       []setupagent.Question   `json:"pendingQuestions,omitempty"`
	Conversation  []setupagent.Exchange   `json:"conversation,omitempty"`
	Pi            *setupagent.PiState     `json:"pi,omitempty"`
	Failure       string                  `json:"verificationFailure,omitempty"`
	LastError     string                  `json:"lastError,omitempty"`
	StudioSession string                  `json:"studioSession,omitempty"`
	// UntrackedAtStart lists the untracked files that predate the setup. It is
	// not omitempty: an empty list was recorded, while null was not yet.
	UntrackedAtStart []string  `json:"untrackedAtStart"`
	UpdatedAt        time.Time `json:"updatedAt"`
	path             string
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
	AgentModel  string   `json:"agentModel,omitempty"`
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
	// Fields from older or newer releases are ignored, so a release change does
	// not strand a saved setup.
	if err := json.NewDecoder(io.LimitReader(f, 16<<20)).Decode(value); err != nil {
		return fmt.Errorf("read setup state %s: %w", path, err)
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
	case stageInspection, stageReview, stageApply, stageRepair, stageVerify, stageRuntime, stageComplete:
	default:
		s.Stage = stageInspection
	}
	if s.Plan == nil {
		s.Stage = stageInspection
	} else {
		setupagent.NormalizePlan(s.Plan)
	}
	return s, nil
}

func (s *setupManifest) save() error {
	s.UpdatedAt = time.Now().UTC()
	return writeSetupJSON(s.path, s)
}

// persist saves a file-backed manifest. Helpers also run against in-memory
// manifests, which have no path and nothing to save.
func (s *setupManifest) persist() error {
	if s.path == "" {
		return nil
	}
	return s.save()
}

// recordOutcome saves the run's error, which the next run passes to the agent,
// and tells the user how to resume.
func (s *setupManifest) recordOutcome(retErr *error) {
	s.LastError = ""
	if *retErr != nil {
		s.LastError = (*retErr).Error()
	}
	*retErr = errors.Join(*retErr, s.save())
	if *retErr != nil {
		*retErr = fmt.Errorf("%w\nSetup saved for %s\nRerun the same command to resume. Manifest: %s", *retErr, s.Root, s.path)
	}
}

// restart discards the saved plan and answers, as --restart does. Files that
// predate the setup are still known, so earlier runs' output counts as new.
func (s *setupManifest) restart(opts setupFlags) {
	*s = setupManifest{Version: 1, Root: s.Root, Stage: stageInspection, Options: savedSetupOptions(opts),
		UntrackedAtStart: s.UntrackedAtStart, path: s.path}
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
			// Reuse the unfinished temporary repository if it is still there;
			// otherwise create a new one.
			if readSetupJSON(pointer, &saved) == nil {
				if s, err := loadSetupManifest(saved.Root); err == nil && s.Stage != stageComplete {
					if _, err := os.Stat(s.Root); err == nil {
						root = s.Root
					}
				}
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
	s, err := loadSetupManifest(root)
	resuming := err == nil && !opts.restart
	switch {
	case resuming:
	case err == nil:
		s.restart(opts)
	default:
		// No manifest, or one this release cannot use: start a new setup.
		s = &setupManifest{Version: 1, Root: root, Stage: stageInspection, path: setupStatePath(root), Options: savedSetupOptions(opts)}
	}
	if !resuming {
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
		opts.noRuntime, opts.noBrowser, opts.studioURL, opts.agentPort, opts.agentModel}
}

// restoreOptions applies the saved selections to flags the user omitted.
// Runtime endpoints and scope may change on retry; a changed selection needs a
// new plan, so restoreOptions returns its flag name and leaves opts unchanged.
func (s *setupManifest) restoreOptions(cmd *cobra.Command, opts *setupFlags) (changed string) {
	for _, flag := range []struct {
		name           string
		current, saved any
	}{
		{"flake", opts.flake, s.Options.Flake}, {"template", opts.template, s.Options.Template},
		{"with", opts.with, s.Options.With}, {"without", opts.without, s.Options.Without},
		{"addon", opts.addonValues, s.Options.AddonValues}, {"force", opts.force, s.Options.Force},
		{"agent-model", opts.agentModel, s.Options.AgentModel},
	} {
		if cmd.Flags().Changed(flag.name) && !reflect.DeepEqual(flag.current, flag.saved) {
			return flag.name
		}
	}
	opts.flake, opts.template = s.Options.Flake, s.Options.Template
	opts.agentModel = s.Options.AgentModel
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
	return ""
}
