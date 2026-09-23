package tui

import (
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mattn/go-isatty"
)

// IsInteractive returns true if both stdin and stdout are connected to a terminal.
// Both must be TTYs because Bubble Tea needs to read key events and render ANSI.
func IsInteractive() bool {
	return isatty.IsTerminal(os.Stdin.Fd()) && isatty.IsTerminal(os.Stdout.Fd())
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
