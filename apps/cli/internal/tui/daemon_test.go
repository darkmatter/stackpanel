package tui

import (
	"io"
	"os"
	"testing"
)

func TestDefaultDaemonMode(t *testing.T) {
	dm := DefaultDaemonMode()

	if dm.Enabled {
		t.Error("DefaultDaemonMode should have Enabled = false")
	}
	if dm.LogOutput != os.Stderr {
		t.Error("DefaultDaemonMode should use os.Stderr for LogOutput")
	}
}

func TestDetermineRunMode(t *testing.T) {
	tests := []struct {
		name       string
		daemonFlag bool
		noTUIFlag  bool
		expected   RunMode
	}{
		{
			name:       "daemon flag takes precedence",
			daemonFlag: true,
			noTUIFlag:  false,
			expected:   RunModeDaemon,
		},
		{
			name:       "daemon flag takes precedence over no-tui",
			daemonFlag: true,
			noTUIFlag:  true,
			expected:   RunModeDaemon,
		},
		{
			name:       "no-tui flag returns direct mode",
			daemonFlag: false,
			noTUIFlag:  true,
			expected:   RunModeDirect,
		},
		// Note: we can't reliably test the interactive detection
		// in unit tests since it depends on actual terminal state
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DetermineRunMode(tt.daemonFlag, tt.noTUIFlag)
			if result != tt.expected {
				t.Errorf("DetermineRunMode(%v, %v) = %v, want %v",
					tt.daemonFlag, tt.noTUIFlag, result, tt.expected)
			}
		})
	}
}

func TestLogWriter(t *testing.T) {
	tests := []struct {
		name     string
		mode     RunMode
		expected io.Writer
	}{
		{
			name:     "interactive mode discards logs",
			mode:     RunModeInteractive,
			expected: io.Discard,
		},
		{
			name:     "daemon mode writes to stderr",
			mode:     RunModeDaemon,
			expected: os.Stderr,
		},
		{
			name:     "direct mode writes to stderr",
			mode:     RunModeDirect,
			expected: os.Stderr,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := LogWriter(tt.mode)
			if result != tt.expected {
				t.Errorf("LogWriter(%v) = %v, want %v", tt.mode, result, tt.expected)
			}
		})
	}
}

func TestDaemonProgramOptions(t *testing.T) {
	// Test that daemon mode returns options
	dm := DaemonMode{Enabled: true}
	opts := DaemonProgramOptions(dm)
	if len(opts) == 0 {
		t.Error("DaemonProgramOptions should return options when daemon mode is enabled")
	}

	// Test that non-daemon mode returns nil
	dm = DaemonMode{Enabled: false}
	opts = DaemonProgramOptions(dm)
	if opts != nil {
		t.Error("DaemonProgramOptions should return nil when daemon mode is disabled")
	}
}

func TestRunModeConstants(t *testing.T) {
	// Verify constants have expected values
	if RunModeInteractive != 0 {
		t.Error("RunModeInteractive should be 0")
	}
	if RunModeDaemon != 1 {
		t.Error("RunModeDaemon should be 1")
	}
	if RunModeDirect != 2 {
		t.Error("RunModeDirect should be 2")
	}
}
