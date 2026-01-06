package tui

import (
	"io"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mattn/go-isatty"
)

// DaemonMode configures the TUI for daemon (non-interactive) operation
type DaemonMode struct {
	// Enabled indicates daemon mode is active
	Enabled bool
	// LogOutput is where logs should be written in daemon mode
	LogOutput io.Writer
}

// DefaultDaemonMode returns a DaemonMode with default settings
func DefaultDaemonMode() DaemonMode {
	return DaemonMode{
		Enabled:   false,
		LogOutput: os.Stderr,
	}
}

// IsInteractive returns true if the program is running in an interactive terminal
func IsInteractive() bool {
	return isatty.IsTerminal(os.Stdin.Fd()) && isatty.IsTerminal(os.Stdout.Fd())
}

// IsTTY returns true if stdout is a terminal
func IsTTY() bool {
	return isatty.IsTerminal(os.Stdout.Fd())
}

// DaemonProgramOptions returns tea.ProgramOption slice for daemon mode
// In daemon mode, we disable the renderer to avoid terminal manipulation
func DaemonProgramOptions(daemon DaemonMode) []tea.ProgramOption {
	if daemon.Enabled {
		return []tea.ProgramOption{
			tea.WithoutRenderer(),
			tea.WithInput(nil), // No input in daemon mode
		}
	}
	return nil
}

// NewProgram creates a new tea.Program with the appropriate options based on mode
func NewProgram(model tea.Model, daemon DaemonMode, opts ...tea.ProgramOption) *tea.Program {
	// Combine daemon options with any provided options
	allOpts := DaemonProgramOptions(daemon)
	allOpts = append(allOpts, opts...)

	return tea.NewProgram(model, allOpts...)
}

// NewInteractiveProgram creates a tea.Program configured for interactive use
func NewInteractiveProgram(model tea.Model, opts ...tea.ProgramOption) *tea.Program {
	defaultOpts := []tea.ProgramOption{
		tea.WithAltScreen(),
	}
	allOpts := append(defaultOpts, opts...)
	return tea.NewProgram(model, allOpts...)
}

// RunMode determines how the TUI should run based on environment and flags
type RunMode int

const (
	// RunModeInteractive runs with full TUI (default when in TTY with no args)
	RunModeInteractive RunMode = iota
	// RunModeDaemon runs without TUI rendering (for background processes)
	RunModeDaemon
	// RunModeDirect runs the command directly without TUI wrapper
	RunModeDirect
)

// DetermineRunMode determines how the program should run based on flags and environment
func DetermineRunMode(daemonFlag, noTUIFlag bool) RunMode {
	// Explicit daemon mode
	if daemonFlag {
		return RunModeDaemon
	}

	// Explicit no-TUI mode
	if noTUIFlag {
		return RunModeDirect
	}

	// Auto-detect based on terminal
	if !IsInteractive() {
		return RunModeDirect
	}

	return RunModeInteractive
}

// LogWriter returns an appropriate writer for logs based on run mode
// In interactive mode, logs should be discarded (TUI manages display)
// In daemon/direct mode, logs should go to stderr
func LogWriter(mode RunMode) io.Writer {
	if mode == RunModeInteractive {
		return io.Discard
	}
	return os.Stderr
}
