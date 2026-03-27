package server

import (
	"bufio"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/rs/zerolog/log"
)

// ShellManager tracks whether the Nix devshell is stale (nix files changed since
// the last build) and orchestrates rebuilds. The web UI uses this to show a
// "shell needs rebuild" banner and stream rebuild output in real-time.
//
// Staleness is tracked by comparing lastNixChange vs lastBuilt timestamps.
// The FlakeWatcher calls MarkNixFileChanged when .nix files are modified.
type ShellManager struct {
	projectRoot string
	server      *Server

	mu            sync.RWMutex
	lastBuilt     time.Time          // When the shell was last rebuilt
	lastNixChange time.Time          // When nix files last changed
	changedFiles  []string           // Files changed since last build (capped at 20)
	isRebuilding  bool               // Prevents concurrent rebuilds
	rebuildCancel context.CancelFunc // Allows cancelling an in-progress rebuild
}

// NewShellManager creates a new ShellManager for the given project.
func NewShellManager(projectRoot string, server *Server) *ShellManager {
	sm := &ShellManager{
		projectRoot:  projectRoot,
		server:       server,
		changedFiles: make([]string, 0),
	}

	// Check for shell entry timestamp
	sm.detectInitialState()

	return sm
}

// detectInitialState checks env vars to determine if we're inside a devshell.
// If so, we assume the shell is fresh. This covers the case where the agent
// is started from within `nix develop` or a direnv-managed shell.
func (sm *ShellManager) detectInitialState() {
	if os.Getenv("IN_NIX_SHELL") != "" || os.Getenv("DEVENV_ROOT") != "" {
		sm.lastBuilt = time.Now()
		log.Debug().Msg("ShellManager: detected active devshell")
	}
}

// MarkNixFileChanged records that a nix file has changed.
// This is called by the FlakeWatcher when nix files are modified.
func (sm *ShellManager) MarkNixFileChanged(filename string) {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	sm.lastNixChange = time.Now()

	// Keep track of changed files (limit to 20)
	relPath := filename
	if rel, err := filepath.Rel(sm.projectRoot, filename); err == nil {
		relPath = rel
	}

	// Avoid duplicates
	for _, f := range sm.changedFiles {
		if f == relPath {
			return
		}
	}

	if len(sm.changedFiles) >= 20 {
		// Remove oldest
		sm.changedFiles = sm.changedFiles[1:]
	}
	sm.changedFiles = append(sm.changedFiles, relPath)

	log.Debug().
		Str("file", relPath).
		Int("total_changed", len(sm.changedFiles)).
		Msg("ShellManager: nix file changed")

	// Broadcast SSE event
	if sm.server != nil {
		sm.server.broadcastSSE(SSEEvent{
			Event: "shell.stale",
			Data: map[string]any{
				"file":      relPath,
				"timestamp": sm.lastNixChange.Format(time.RFC3339),
			},
		})
	}
}

// IsStale returns true if nix files have changed since the last shell build.
func (sm *ShellManager) IsStale() bool {
	sm.mu.RLock()
	defer sm.mu.RUnlock()

	// If we've never built, check if there have been any changes
	if sm.lastBuilt.IsZero() {
		// Not stale if no changes recorded
		return !sm.lastNixChange.IsZero()
	}

	// Stale if nix files changed after last build
	return sm.lastNixChange.After(sm.lastBuilt)
}

// Status returns the current shell status.
func (sm *ShellManager) Status() ShellStatus {
	sm.mu.RLock()
	defer sm.mu.RUnlock()

	return ShellStatus{
		Stale:         sm.lastNixChange.After(sm.lastBuilt) && !sm.lastNixChange.IsZero(),
		Rebuilding:    sm.isRebuilding,
		LastBuilt:     sm.lastBuilt,
		LastNixChange: sm.lastNixChange,
		ChangedFiles:  append([]string{}, sm.changedFiles...), // Copy slice
	}
}

// ShellStatus represents the current state of the devshell.
type ShellStatus struct {
	Stale         bool
	Rebuilding    bool
	LastBuilt     time.Time
	LastNixChange time.Time
	ChangedFiles  []string
}

// RebuildEvent represents a streaming event during shell rebuild, sent to SSE subscribers.
type RebuildEvent struct {
	Type      string // "started", "output", "completed", "error"
	Output    string // Line of stdout/stderr (for Type="output")
	ExitCode  int    // Set on Type="completed"
	Error     string // Set on Type="error"
	Timestamp time.Time
}

// Rebuild starts a shell rebuild and streams output events to the caller.
// Only one rebuild can run at a time (returns RebuildInProgressError otherwise).
// The method parameter selects the rebuild command:
//   - "devshell": runs the project's ./devshell script (falls back to nix develop)
//   - "nix": always runs `nix develop --impure`
func (sm *ShellManager) Rebuild(ctx context.Context, method string, events chan<- RebuildEvent) error {
	sm.mu.Lock()
	if sm.isRebuilding {
		sm.mu.Unlock()
		return &RebuildInProgressError{}
	}
	sm.isRebuilding = true

	// Create cancellable context
	ctx, cancel := context.WithCancel(ctx)
	sm.rebuildCancel = cancel
	sm.mu.Unlock()

	defer func() {
		sm.mu.Lock()
		sm.isRebuilding = false
		sm.rebuildCancel = nil
		sm.mu.Unlock()
	}()

	// Determine command to run
	var cmd *exec.Cmd
	if method == "nix" {
		cmd = exec.CommandContext(ctx, "nix", "develop", "--impure")
	} else {
		// Default to ./devshell
		devshellPath := filepath.Join(sm.projectRoot, "devshell")
		if _, err := os.Stat(devshellPath); os.IsNotExist(err) {
			// Fall back to nix develop if devshell script doesn't exist
			cmd = exec.CommandContext(ctx, "nix", "develop", "--impure")
		} else {
			cmd = exec.CommandContext(ctx, devshellPath)
		}
	}

	cmd.Dir = sm.projectRoot
	cmd.Env = os.Environ()

	// Get stdout and stderr pipes
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		events <- RebuildEvent{
			Type:      "error",
			Error:     err.Error(),
			Timestamp: time.Now(),
		}
		return err
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		events <- RebuildEvent{
			Type:      "error",
			Error:     err.Error(),
			Timestamp: time.Now(),
		}
		return err
	}

	// Broadcast start event
	events <- RebuildEvent{
		Type:      "started",
		Timestamp: time.Now(),
	}

	if sm.server != nil {
		sm.server.broadcastSSE(SSEEvent{
			Event: "shell.rebuilding",
			Data: map[string]any{
				"method":    method,
				"timestamp": time.Now().Format(time.RFC3339),
			},
		})
	}

	// Start the command
	if err := cmd.Start(); err != nil {
		events <- RebuildEvent{
			Type:      "error",
			Error:     err.Error(),
			Timestamp: time.Now(),
		}
		return err
	}

	// Stream output in goroutines
	var wg sync.WaitGroup

	streamOutput := func(scanner *bufio.Scanner) {
		defer wg.Done()
		for scanner.Scan() {
			line := scanner.Text()
			events <- RebuildEvent{
				Type:      "output",
				Output:    line,
				Timestamp: time.Now(),
			}
		}
	}

	wg.Add(2)
	go streamOutput(bufio.NewScanner(stdout))
	go streamOutput(bufio.NewScanner(stderr))

	// Wait for output streaming to complete
	wg.Wait()

	// Wait for command to finish
	err = cmd.Wait()

	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			events <- RebuildEvent{
				Type:      "error",
				Error:     err.Error(),
				Timestamp: time.Now(),
			}
			return err
		}
	}

	// Mark as built if successful
	if exitCode == 0 {
		sm.mu.Lock()
		sm.lastBuilt = time.Now()
		sm.changedFiles = nil // Clear changed files
		sm.mu.Unlock()

		if sm.server != nil {
			sm.server.broadcastSSE(SSEEvent{
				Event: "shell.rebuilt",
				Data: map[string]any{
					"timestamp": time.Now().Format(time.RFC3339),
				},
			})
		}
	}

	events <- RebuildEvent{
		Type:      "completed",
		ExitCode:  exitCode,
		Timestamp: time.Now(),
	}

	return nil
}

// CancelRebuild cancels any in-progress rebuild.
func (sm *ShellManager) CancelRebuild() {
	sm.mu.RLock()
	cancel := sm.rebuildCancel
	sm.mu.RUnlock()

	if cancel != nil {
		cancel()
	}
}

// RebuildInProgressError is returned when attempting to start a rebuild while one is in progress.
type RebuildInProgressError struct{}

func (e *RebuildInProgressError) Error() string {
	return "a shell rebuild is already in progress"
}
