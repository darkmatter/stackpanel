package tui

import (
	"testing"
)

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
