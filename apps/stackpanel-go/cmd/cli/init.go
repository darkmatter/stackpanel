package cmd

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/spf13/cobra"
)

// Default flake reference for stackpanel.
// Users can override with --flake flag or STACKPANEL_FLAKE env var.
const defaultStackpanelFlake = "github:darkmatter/stackpanel"

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize a new stackpanel project",
	Long: `Initialize scaffolds a new stackpanel project and registers it so the
agent can find it. The scaffolding (flake.nix, .envrc, .stack/, ...) is fetched
from the stackpanel flake's lib.initFiles, which is derived from the same
template directory used by 'nix flake init -t' — both produce identical files.

The command is idempotent: running it again will skip any step whose work has
already been done. New steps added in future releases will be run on re-run.

An interactive TUI (via gum) guides you through each step. Pass
--non-interactive (or run under a non-TTY) to execute all steps without prompts.

Example:
  stackpanel init                              # Interactive setup
  stackpanel init --non-interactive            # No prompts, apply everything
  stackpanel init --force                      # Overwrite existing files
  stackpanel init --dry-run                    # Show what would be done
  stackpanel init --flake path:/path/to/sp     # Use a local stackpanel checkout`,
	RunE: runInit,
}

var (
	initForce          bool
	initDryRun         bool
	initFlake          string
	initNonInteractive bool
)

func init() {
	initCmd.Flags().BoolVar(&initForce, "force", false, "Overwrite existing files")
	initCmd.Flags().BoolVar(&initDryRun, "dry-run", false, "Show what would be created without writing files")
	initCmd.Flags().StringVar(&initFlake, "flake", "", "Stackpanel flake reference (default: git+ssh://git@github.com/darkmatter/stackpanel)")
	initCmd.Flags().BoolVar(&initNonInteractive, "non-interactive", false, "Skip all prompts and apply every pending step")

	rootCmd.AddCommand(initCmd)
}

// -----------------------------------------------------------------------------
// Step machinery
// -----------------------------------------------------------------------------

// stepContext carries shared state between steps so each step can consult the
// resolved target directory, flake ref, flag values, and any cached data from
// prior steps (e.g. fetched init files).
type stepContext struct {
	ctx         context.Context
	targetDir   string
	flakeRef    string
	force       bool
	dryRun      bool
	verbose     bool
	interactive bool

	// cache: populated by the fetch step, consumed by the write-files step.
	initFiles map[string]string
}

// step is the core abstraction for idempotent init work. Adding a new stage
// to `stackpanel init` is a matter of appending a `step` to `buildSteps`.
type step struct {
	// ID is used for logging only; keep it short and kebab-cased.
	ID string
	// Title is a human-readable label shown in prompts.
	Title string
	// Description is an optional longer sentence shown before the prompt.
	Description string
	// IsDone returns true if there is nothing to do for this step.
	// When true the step is skipped entirely (no prompt, no apply call).
	IsDone func(*stepContext) (bool, string, error)
	// Apply runs the step. It should be safe to invoke even if partially done.
	// Returned summary (if non-empty) is printed on success.
	Apply func(*stepContext) (string, error)
	// Confirm, when true, asks the user before running Apply in interactive mode.
	// Set to false for steps the user is expected to accept (fetching templates
	// from a flake reference, writing missing scaffolding, etc.).
	Confirm bool
}

func runInit(cmd *cobra.Command, args []string) error {
	verbose, _ := cmd.Flags().GetBool("verbose")
	ctx := context.Background()

	targetDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("failed to get current directory: %w", err)
	}

	flakeRef := resolveFlakeRef(initFlake)

	sctx := &stepContext{
		ctx:         ctx,
		targetDir:   targetDir,
		flakeRef:    flakeRef,
		force:       initForce,
		dryRun:      initDryRun,
		verbose:     verbose,
		interactive: !initNonInteractive && tui.IsInteractiveStdio(),
	}

	if verbose {
		output.Info(fmt.Sprintf("Target directory: %s", targetDir))
		output.Info(fmt.Sprintf("Using stackpanel flake: %s", flakeRef))
		if !sctx.interactive {
			output.Info("Non-interactive mode: prompts will be skipped")
		}
	}

	steps := buildSteps()

	if sctx.dryRun {
		output.Info("Dry run: no files will be written, no state will change")
	}

	for _, s := range steps {
		if err := runStep(sctx, s); err != nil {
			return err
		}
	}

	fmt.Fprintln(os.Stderr)
	output.Success("stackpanel init complete")
	output.Dimmed("  Next steps:")
	output.Dimmed("    1. Review the generated files in .stackpanel/ and flake.nix")
	output.Dimmed("    2. Edit .stackpanel/config.nix to configure your project")
	output.Dimmed("    3. Run 'direnv allow' (or 'nix develop --impure') to enter the shell")

	return nil
}

// runStep handles the common flow: check isDone, optionally prompt, run apply.
// It keeps runInit short and testable.
func runStep(sctx *stepContext, s step) error {
	done, doneMsg, err := s.IsDone(sctx)
	if err != nil {
		return fmt.Errorf("step %q check failed: %w", s.ID, err)
	}
	if done {
		if doneMsg == "" {
			doneMsg = s.Title
		}
		output.Green.Fprintf(os.Stderr, "✓ %s", doneMsg)
		fmt.Fprintln(os.Stderr, " (already done)")
		return nil
	}

	// Announce the step (before the prompt) so the user knows why we're asking.
	output.Info(s.Title)
	if s.Description != "" {
		output.Dimmed("  " + s.Description)
	}

	if sctx.interactive && s.Confirm && !sctx.dryRun {
		ok, err := tui.Confirm(fmt.Sprintf("Run step: %s?", s.Title), true)
		if err != nil {
			return fmt.Errorf("step %q confirm failed: %w", s.ID, err)
		}
		if !ok {
			output.Warning(fmt.Sprintf("Skipped %s (user declined)", s.ID))
			return nil
		}
	}

	if sctx.dryRun {
		output.Dimmed(fmt.Sprintf("  [dry-run] would apply: %s", s.ID))
		return nil
	}

	summary, err := s.Apply(sctx)
	if err != nil {
		return fmt.Errorf("step %q failed: %w", s.ID, err)
	}
	if summary != "" {
		output.Success(summary)
	}
	return nil
}

// buildSteps returns the ordered list of init steps. Adding a new stage is a
// one-liner append here; the machinery above handles idempotency and prompts.
func buildSteps() []step {
	return []step{
		stepFetchInitFiles(),
		stepWriteInitFiles(),
		stepRegisterProject(),
	}
}

// -----------------------------------------------------------------------------
// Steps
// -----------------------------------------------------------------------------

// stepFetchInitFiles evaluates the stackpanel flake's `lib.initFiles` attribute
// and caches the map on the context for downstream steps.
func stepFetchInitFiles() step {
	return step{
		ID:          "fetch-init-files",
		Title:       "Fetch boilerplate from stackpanel flake",
		Description: "Evaluates <flake>#lib.initFiles for project scaffolding (same file set as `nix flake init -t`).",
		IsDone: func(s *stepContext) (bool, string, error) {
			// This step is always "not done" until we've fetched files once per
			// invocation — the cache is per-process, so re-running the command
			// will refetch (which is desired: users might upgrade the flake).
			return s.initFiles != nil, "Boilerplate fetched", nil
		},
		Apply: func(s *stepContext) (string, error) {
			files, err := getInitFilesFromFlake(s.ctx, s.flakeRef)
			if err != nil {
				return "", fmt.Errorf("failed to get init files from flake: %w\nHint: check that the flake reference %q is valid", err, s.flakeRef)
			}
			s.initFiles = files
			return fmt.Sprintf("Fetched %d file(s) from stackpanel flake", len(files)), nil
		},
	}
}

// stepWriteInitFiles writes every file from the fetched initFiles map that
// doesn't already exist on disk (or, with --force, overwrites them).
func stepWriteInitFiles() step {
	return step{
		ID:          "write-init-files",
		Title:       "Write project scaffolding files",
		Description: "Writes any missing scaffolding files. Existing files are left alone unless --force.",
		IsDone: func(s *stepContext) (bool, string, error) {
			if s.force {
				// With --force we always (re)write. Never consider this done.
				return false, "", nil
			}
			if s.initFiles == nil {
				return false, "", nil
			}
			for rel := range s.initFiles {
				if _, err := os.Stat(filepath.Join(s.targetDir, rel)); errors.Is(err, os.ErrNotExist) {
					return false, "", nil
				} else if err != nil {
					return false, "", err
				}
			}
			return true, "All scaffolding files present", nil
		},
		Apply: func(s *stepContext) (string, error) {
			if s.initFiles == nil {
				return "", fmt.Errorf("initFiles not fetched; fetch step must run first")
			}
			created, skipped, err := writeInitFiles(s.targetDir, s.initFiles, s.force, s.verbose)
			if err != nil {
				return "", err
			}
			return fmt.Sprintf("Wrote %d file(s), skipped %d", created, skipped), nil
		},
	}
}

// stepRegisterProject records this directory in ~/.config/stackpanel/stackpanel.yaml
// so the agent and studio can find it.
func stepRegisterProject() step {
	return step{
		ID:          "register-project",
		Title:       "Register project with stackpanel user config",
		Description: "Adds this directory to ~/.config/stackpanel/stackpanel.yaml so the agent sees it.",
		IsDone: func(s *stepContext) (bool, string, error) {
			ucm, err := userconfig.NewManager()
			if err != nil {
				// If we can't even read the user config, treat as not done so
				// Apply gets to surface the real error.
				return false, "", nil
			}
			if ucm.HasProject(s.targetDir) {
				return true, "Project already registered", nil
			}
			return false, "", nil
		},
		Apply: func(s *stepContext) (string, error) {
			ucm, err := userconfig.NewManager()
			if err != nil {
				return "", fmt.Errorf("failed to create user config manager: %w", err)
			}
			name := filepath.Base(s.targetDir)
			if _, err := ucm.AddProject(s.targetDir, name); err != nil {
				return "", fmt.Errorf("failed to add project: %w", err)
			}
			return "Registered project in ~/.config/stackpanel/stackpanel.yaml", nil
		},
	}
}

// -----------------------------------------------------------------------------
// File writing helper
// -----------------------------------------------------------------------------

// writeInitFiles writes every (path, content) pair under root, respecting
// `force`. Returns (created, skipped, error). Kept separate from the step so
// tests can call it directly.
func writeInitFiles(root string, files map[string]string, force, verbose bool) (int, int, error) {
	// Sort keys for deterministic output in tests and logs.
	keys := make([]string, 0, len(files))
	for k := range files {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var created, skipped int
	for _, rel := range keys {
		abs := filepath.Join(root, rel)
		exists := false
		if _, err := os.Stat(abs); err == nil {
			exists = true
		} else if !errors.Is(err, os.ErrNotExist) {
			return created, skipped, err
		}

		if exists && !force {
			if verbose {
				output.Dimmed(fmt.Sprintf("  skip: %s (exists)", rel))
			}
			skipped++
			continue
		}

		if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
			return created, skipped, fmt.Errorf("failed to create directory for %s: %w", rel, err)
		}
		if err := os.WriteFile(abs, []byte(files[rel]), 0o644); err != nil {
			return created, skipped, fmt.Errorf("failed to write %s: %w", rel, err)
		}
		if exists {
			output.Yellow.Fprintf(os.Stderr, "  overwrote: %s\n", rel)
		} else {
			output.Green.Fprintf(os.Stderr, "  created:   %s\n", rel)
		}
		created++
	}
	return created, skipped, nil
}


// resolveFlakeRef picks the flake ref from (in order): --flake, STACKPANEL_FLAKE,
// STACKPANEL_ROOT, default.
func resolveFlakeRef(flag string) string {
	if flag != "" {
		return flag
	}
	if v := os.Getenv("STACKPANEL_FLAKE"); v != "" {
		return v
	}
	if root := os.Getenv("STACKPANEL_ROOT"); root != "" {
		return "path:" + root
	}
	return defaultStackpanelFlake
}

// getInitFilesFromFlake evaluates initFiles from a stackpanel flake reference.
// The flakeRef can be:
//   - "github:darkmatter/stackpanel" (default, from GitHub)
//   - "path:/local/path/to/stackpanel" (for local development)
//   - "git+file:///local/path/to/stackpanel" (faster local, uses git filtering)
//   - Any valid Nix flake reference
//
// "path:" references are automatically converted to "git+file://" for better
// performance (uses git to filter files instead of copying everything).
func getInitFilesFromFlake(ctx context.Context, flakeRef string) (map[string]string, error) {
	if strings.HasPrefix(flakeRef, "path:") {
		localPath := strings.TrimPrefix(flakeRef, "path:")
		flakeRef = "git+file://" + localPath
	}
	return nixeval.GetInitFilesFromFlake(ctx, flakeRef)
}

// findProjectRoot walks up the directory tree to find a project root
// (directory containing flake.nix or .stackpanel).
func findProjectRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "flake.nix")); err == nil {
			return dir, nil
		}
		if _, err := os.Stat(filepath.Join(dir, ".stackpanel")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("no project root found (looking for flake.nix or .stackpanel)")
		}
		dir = parent
	}
}
