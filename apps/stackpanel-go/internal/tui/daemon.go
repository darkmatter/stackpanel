package tui

import (
	"io"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mattn/go-isatty"
)

// DaemonMode configures the TUI for headless operation (CI, background processes).
// When enabled, Bubble Tea's renderer and input are disabled so the program
// can run without a terminal. Logs go to LogOutput instead of the TUI.
type DaemonMode struct {
	Enabled   bool
	LogOutput io.Writer
}

// DefaultDaemonMode returns a DaemonMode with default settings
func DefaultDaemonMode() DaemonMode {
	return DaemonMode{
		Enabled:   false,
		LogOutput: os.Stderr,
	}
}

// IsInteractive returns true if both stdin and stdout are connected to a terminal.
// Both must be TTYs because Bubble Tea needs to read key events and render ANSI.
func IsInteractive() bool {
	return isatty.IsTerminal(os.Stdin.Fd()) && isatty.IsTerminal(os.Stdout.Fd())
}

// IsTTY returns true if stdout is a terminal
func IsTTY() bool {
	return isatty.IsTerminal(os.Stdout.Fd())
}

// DaemonProgramOptions returns tea.ProgramOption slice for daemon mode.
// Disabling the renderer and input prevents ANSI escape sequences from
// polluting log files or non-TTY output.
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

// RunMode determines how the TUI should run. The three modes allow the same
// Cobra commands to work in interactive terminals, CI pipelines, and as
// background daemons without code changes at the call site.
type RunMode int

const (
	RunModeInteractive RunMode = iota // Full TUI with alt-screen
	RunModeDaemon                     // No rendering, no input (background)
	RunModeDirect                     // Plain stdout, no TUI wrapper (piped/CI)
)

// DetermineRunMode selects the run mode with explicit flags taking precedence
// over auto-detection. Fallback order: daemonFlag → noTUIFlag → TTY check.
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

// LogWriter returns an appropriate writer for logs based on run mode.
// Interactive mode discards logs because the TUI manages its own display;
// writing to stdout/stderr would corrupt the Bubble Tea rendering.
func LogWriter(mode RunMode) io.Writer {
	if mode == RunModeInteractive {
		return io.Discard
	}
	return os.Stderr
}
