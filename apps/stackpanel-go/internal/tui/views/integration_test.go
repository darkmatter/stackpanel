package views

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// TestStatusViewNavigationIntegration tests that StatusView works with navigation
func TestStatusViewNavigationIntegration(t *testing.T) {
	// Create status view with return message
	customReturn := ReturnFromStatusMsg{}
	view := NewStatusView(WithStatusReturnMsg(customReturn))

	// Verify return message is set
	if view.returnMsg == nil {
		t.Error("Return message should be set")
	}

	// Set window size
	newView, _ := view.Update(tea.WindowSizeMsg{Width: 100, Height: 40})
	view = newView.(StatusView)

	// Press escape should return the message
	newView, cmd := view.Update(tea.KeyMsg{Type: tea.KeyEscape})
	view = newView.(StatusView)

	if cmd == nil {
		t.Error("Escape should return a command")
	}

	// Execute the command and verify it returns the right message type
	msg := cmd()
	if _, ok := msg.(ReturnFromStatusMsg); !ok {
		t.Errorf("Expected ReturnFromStatusMsg, got %T", msg)
	}
}

func TestStatusViewDefaultReturn(t *testing.T) {
	// Create status view without custom return
	view := NewStatusView()

	// Set window size
	newView, _ := view.Update(tea.WindowSizeMsg{Width: 100, Height: 40})
	view = newView.(StatusView)

	// Press escape should return default message
	_, cmd := view.Update(tea.KeyMsg{Type: tea.KeyEscape})

	if cmd == nil {
		t.Error("Escape should return a command")
	}

	msg := cmd()
	if _, ok := msg.(ReturnFromStatusMsg); !ok {
		t.Errorf("Expected ReturnFromStatusMsg, got %T", msg)
	}
}

func TestServicesViewNavigationIntegration(t *testing.T) {
	// Create services view with return message
	customReturn := ReturnFromServicesMsg{}
	view := NewServicesView([]string{"test"}, WithServicesReturnMsg(customReturn))

	// Verify return message is set
	if view.returnMsg == nil {
		t.Error("Return message should be set")
	}

	// Mark as done so we can escape
	view.done = true

	// Press escape should return the message
	_, cmd := view.Update(tea.KeyMsg{Type: tea.KeyEscape})

	if cmd == nil {
		t.Error("Escape should return a command when done")
	}

	msg := cmd()
	if _, ok := msg.(ReturnFromServicesMsg); !ok {
		t.Errorf("Expected ReturnFromServicesMsg, got %T", msg)
	}
}

func TestServicesViewEscapeBeforeDone(t *testing.T) {
	view := NewServicesView([]string{"test"})

	// Not done yet
	view.done = false

	// Press escape should not return (can't escape during operation)
	_, cmd := view.Update(tea.KeyMsg{Type: tea.KeyEscape})

	// Should not return a navigation command (nil or spinner tick)
	if cmd != nil {
		msg := cmd()
		if _, ok := msg.(ReturnFromServicesMsg); ok {
			t.Error("Should not be able to escape before done")
		}
	}
}

func TestAgentViewNavigationIntegration(t *testing.T) {
	// Create agent view with return message
	customReturn := ReturnFromAgentMsg{}
	view := NewAgentView(WithAgentReturnMsg(customReturn))

	// Verify return message is set
	if view.returnMsg == nil {
		t.Error("Return message should be set")
	}

	// Press escape should return the message
	_, cmd := view.Update(tea.KeyMsg{Type: tea.KeyEscape})

	if cmd == nil {
		t.Error("Escape should return a command")
	}

	msg := cmd()
	if _, ok := msg.(ReturnFromAgentMsg); !ok {
		t.Errorf("Expected ReturnFromAgentMsg, got %T", msg)
	}
}

func TestAgentViewBackMenuItem(t *testing.T) {
	view := NewAgentView()

	// Set focus to menu
	view.focus = FocusMenu

	// Find the "Back" menu item
	backIdx := -1
	for i, item := range view.menuItems {
		if item.Name == "Back" {
			backIdx = i
			break
		}
	}

	if backIdx == -1 {
		t.Fatal("Back menu item not found")
	}

	// Select the back item
	view.selectedIdx = backIdx

	// Press enter to execute
	_, cmd := view.Update(tea.KeyMsg{Type: tea.KeyEnter})

	if cmd == nil {
		t.Error("Selecting Back should return a command")
	}

	msg := cmd()
	if _, ok := msg.(ReturnFromAgentMsg); !ok {
		t.Errorf("Back should return ReturnFromAgentMsg, got %T", msg)
	}
}

func TestAllViewsRenderWithoutPanic(t *testing.T) {
	tests := []struct {
		name string
		view tea.Model
	}{
		{"StatusView", NewStatusView()},
		{"ServicesView", NewServicesView([]string{"test"})},
		{"AgentView", NewAgentView()},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Render before window size (should not panic)
			output := tt.view.View()
			if output == "" {
				t.Error("View should return something even before window size")
			}

			// Update with window size
			newView, _ := tt.view.Update(tea.WindowSizeMsg{Width: 100, Height: 40})

			// Render after window size
			output = newView.View()
			if output == "" {
				t.Error("View should return content after window size")
			}
		})
	}
}

func TestAllViewsHandleQuit(t *testing.T) {
	tests := []struct {
		name string
		view tea.Model
	}{
		{"StatusView", NewStatusView()},
		{"ServicesView", NewServicesView([]string{"test"})},
		{"AgentView", NewAgentView()},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Press 'q' should quit
			_, cmd := tt.view.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'q'}})

			// Should return quit command
			if cmd == nil {
				t.Error("q key should return a command")
			}
		})
	}
}

func TestAllViewsHandleCtrlC(t *testing.T) {
	tests := []struct {
		name string
		view tea.Model
	}{
		{"StatusView", NewStatusView()},
		{"ServicesView", NewServicesView([]string{"test"})},
		{"AgentView", NewAgentView()},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Press Ctrl+C should quit
			_, cmd := tt.view.Update(tea.KeyMsg{Type: tea.KeyCtrlC})

			// Should return quit command
			if cmd == nil {
				t.Error("Ctrl+C should return a command")
			}
		})
	}
}

func TestViewsShowHelpHints(t *testing.T) {
	// StatusView should show help hints
	statusView := NewStatusView()
	updated, _ := statusView.Update(tea.WindowSizeMsg{Width: 100, Height: 40})
	statusView = updated.(StatusView)

	// Simulate loading complete
	statusView.loading = false
	output := statusView.View()
	if !strings.Contains(output, "esc") && !strings.Contains(output, "back") {
		t.Error("StatusView should show escape/back hint")
	}

	// AgentView should show help hints
	agentView := NewAgentView()
	agentView.width = 100
	agentView.height = 40
	output = agentView.View()
	if !strings.Contains(output, "esc") && !strings.Contains(output, "back") {
		t.Error("AgentView should show escape/back hint")
	}
}

func TestServicesViewModeIntegration(t *testing.T) {
	modes := []struct {
		mode     ServicesViewMode
		expected string
	}{
		{ModeStart, "Starting"},
		{ModeStop, "Stopping"},
		{ModeRestart, "Restarting"},
	}

	for _, m := range modes {
		t.Run(m.expected, func(t *testing.T) {
			view := NewServicesView([]string{"test"}, WithMode(m.mode))
			output := view.View()
			if !strings.Contains(output, m.expected) {
				t.Errorf("Expected %q in output for mode %d", m.expected, m.mode)
			}
		})
	}
}

func TestAgentViewFocusIndicators(t *testing.T) {
	view := NewAgentView()
	view.width = 100
	view.height = 40

	// Test logs focus
	view.focus = FocusLogs
	output := view.View()
	// Should have some indicator that logs are focused
	if !strings.Contains(output, "Logs") {
		t.Error("Should show Logs panel")
	}

	// Test menu focus
	view.focus = FocusMenu
	output = view.View()
	// Should have some indicator that menu is focused
	if !strings.Contains(output, "Commands") {
		t.Error("Should show Commands panel")
	}
}

func TestAgentViewLogOperations(t *testing.T) {
	view := NewAgentView()

	// Add some logs
	view.AddLog("Test log 1")
	view.AddLog("Test log 2")
	view.AddLog("Test log 3")

	if len(view.logs) != 3 {
		t.Errorf("Expected 3 logs, got %d", len(view.logs))
	}

	// Logs should contain timestamps
	for _, log := range view.logs {
		if !strings.Contains(log, ":") { // Timestamps have colons
			t.Error("Log should contain timestamp")
		}
	}

	// Clear logs (via menu item simulation)
	view.focus = FocusMenu
	for i, item := range view.menuItems {
		if item.Name == "Clear Logs" {
			view.selectedIdx = i
			break
		}
	}
	view.Update(tea.KeyMsg{Type: tea.KeyEnter})

	// Note: Clear logs is handled internally, so logs should be cleared
	// In the actual implementation, this happens in executeMenuItem
}
