package views

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestStatusView(t *testing.T) {
	view := NewStatusView()

	// Check initial state
	if !view.loading {
		t.Error("StatusView should start in loading state")
	}

	// Init should return commands
	cmd := view.Init()
	if cmd == nil {
		t.Error("StatusView.Init() should return commands")
	}

	// View should render without panic
	output := view.View()
	if output == "" {
		t.Error("StatusView.View() should return content")
	}
	if !strings.Contains(output, "Loading") {
		t.Error("StatusView should show loading state initially")
	}
}

func TestStatusViewWithOptions(t *testing.T) {
	customMsg := ReturnFromStatusMsg{}
	view := NewStatusView(WithStatusReturnMsg(customMsg))

	if view.returnMsg == nil {
		t.Error("WithStatusReturnMsg should set returnMsg")
	}
}

func TestStatusViewUpdate(t *testing.T) {
	view := NewStatusView()

	// Test window size message
	newView, _ := view.Update(tea.WindowSizeMsg{Width: 100, Height: 50})
	updatedView := newView.(StatusView)
	if updatedView.width != 100 || updatedView.height != 50 {
		t.Error("StatusView should update dimensions on WindowSizeMsg")
	}

	// Test services updated message
	services := []ServiceInfo{
		{Name: "test", DisplayName: "Test Service", Status: "running", PID: 1234, Port: 8080},
	}
	newView, _ = view.Update(statusServicesUpdatedMsg(services))
	updatedView = newView.(StatusView)
	if updatedView.loading {
		t.Error("StatusView should not be loading after services update")
	}
	if len(updatedView.services) != 1 {
		t.Errorf("StatusView should have 1 service, got %d", len(updatedView.services))
	}
}

func TestServicesView(t *testing.T) {
	// Test with empty service list (should use all services)
	view := NewServicesView(nil)

	// View should render without panic
	output := view.View()
	if output == "" {
		t.Error("ServicesView.View() should return content")
	}
	if !strings.Contains(output, "Starting Services") {
		t.Error("ServicesView should show title")
	}
}

func TestServicesViewWithOptions(t *testing.T) {
	customMsg := ReturnFromServicesMsg{}
	view := NewServicesView([]string{"postgres"},
		WithServicesReturnMsg(customMsg),
		WithMode(ModeStop),
	)

	if view.returnMsg == nil {
		t.Error("WithServicesReturnMsg should set returnMsg")
	}
	if view.mode != ModeStop {
		t.Error("WithMode should set mode")
	}
}

func TestServicesViewModes(t *testing.T) {
	tests := []struct {
		mode     ServicesViewMode
		expected string
	}{
		{ModeStart, "Starting Services"},
		{ModeStop, "Stopping Services"},
		{ModeRestart, "Restarting Services"},
	}

	for _, tt := range tests {
		view := NewServicesView(nil, WithMode(tt.mode))
		output := view.View()
		if !strings.Contains(output, tt.expected) {
			t.Errorf("Mode %d should show %q in title", tt.mode, tt.expected)
		}
	}
}

func TestServicesViewUpdate(t *testing.T) {
	view := NewServicesView([]string{"test"})

	// Test window size message
	newView, _ := view.Update(tea.WindowSizeMsg{Width: 100, Height: 50})
	updatedView := newView.(ServicesView)
	if updatedView.width != 100 {
		t.Error("ServicesView should update dimensions on WindowSizeMsg")
	}
}

func TestAgentView(t *testing.T) {
	view := NewAgentView()

	// Check initial state
	if view.connected {
		t.Error("AgentView should start disconnected")
	}
	if view.focus != FocusLogs {
		t.Error("AgentView should start with focus on logs")
	}

	// View should render without panic (before window size, shows initializing)
	output := view.View()
	if output == "" {
		t.Error("AgentView.View() should return content")
	}
	if !strings.Contains(output, "Initializing") {
		t.Error("AgentView should show initializing before window size")
	}

	// After window size, should show full view
	view.width = 100
	view.height = 30
	output = view.View()
	if !strings.Contains(output, "Agent Monitor") {
		t.Error("AgentView should show title after resize")
	}
}

func TestAgentViewWithOptions(t *testing.T) {
	customMenu := []AgentMenuItem{
		{Name: "Custom", Description: "Custom action"},
	}

	view := NewAgentView(
		WithSplitRatio(0.7),
		WithMenuItems(customMenu),
	)

	if view.splitRatio != 0.7 {
		t.Errorf("splitRatio = %f, want 0.7", view.splitRatio)
	}
	if len(view.menuItems) != 1 {
		t.Errorf("menuItems length = %d, want 1", len(view.menuItems))
	}
	if view.menuItems[0].Name != "Custom" {
		t.Error("Custom menu item not set")
	}
}

func TestAgentViewSplitRatioBounds(t *testing.T) {
	// Test lower bound
	view := NewAgentView(WithSplitRatio(0.1))
	if view.splitRatio < 0.2 {
		t.Error("splitRatio should be clamped to minimum 0.2")
	}

	// Test upper bound
	view = NewAgentView(WithSplitRatio(0.9))
	if view.splitRatio > 0.8 {
		t.Error("splitRatio should be clamped to maximum 0.8")
	}
}

func TestAgentViewAddLog(t *testing.T) {
	view := NewAgentView()

	view.AddLog("Test log message")

	if len(view.logs) != 1 {
		t.Errorf("logs length = %d, want 1", len(view.logs))
	}
	if !strings.Contains(view.logs[0], "Test log message") {
		t.Error("Log should contain the message")
	}
}

func TestAgentViewSetConnected(t *testing.T) {
	view := NewAgentView()

	view.SetConnected(true)
	if !view.connected {
		t.Error("SetConnected(true) should set connected to true")
	}

	view.SetConnected(false)
	if view.connected {
		t.Error("SetConnected(false) should set connected to false")
	}
}

func TestAgentViewUpdate(t *testing.T) {
	view := NewAgentView()

	// Test tab to switch focus
	newView, _ := view.Update(tea.KeyMsg{Type: tea.KeyTab})
	updatedView := newView.(AgentView)
	if updatedView.focus != FocusMenu {
		t.Error("Tab should switch focus to menu")
	}

	// Test tab again to switch back
	newView, _ = updatedView.Update(tea.KeyMsg{Type: tea.KeyTab})
	updatedView = newView.(AgentView)
	if updatedView.focus != FocusLogs {
		t.Error("Tab should switch focus back to logs")
	}
}

func TestAgentViewMenuNavigation(t *testing.T) {
	view := NewAgentView()
	view.focus = FocusMenu

	// Move down
	newView, _ := view.Update(tea.KeyMsg{Type: tea.KeyDown})
	updatedView := newView.(AgentView)
	if updatedView.selectedIdx != 1 {
		t.Errorf("Down should move selection to 1, got %d", updatedView.selectedIdx)
	}

	// Move up
	newView, _ = updatedView.Update(tea.KeyMsg{Type: tea.KeyUp})
	updatedView = newView.(AgentView)
	if updatedView.selectedIdx != 0 {
		t.Errorf("Up should move selection to 0, got %d", updatedView.selectedIdx)
	}

	// Can't go above 0
	newView, _ = updatedView.Update(tea.KeyMsg{Type: tea.KeyUp})
	updatedView = newView.(AgentView)
	if updatedView.selectedIdx != 0 {
		t.Error("Up at 0 should stay at 0")
	}
}

func TestServiceInfo(t *testing.T) {
	info := ServiceInfo{
		Name:        "postgres",
		DisplayName: "PostgreSQL",
		Status:      "running",
		PID:         1234,
		Port:        5432,
		Details:     "10 connections",
	}

	if info.Name != "postgres" {
		t.Error("ServiceInfo.Name not set")
	}
	if info.DisplayName != "PostgreSQL" {
		t.Error("ServiceInfo.DisplayName not set")
	}
	if info.Status != "running" {
		t.Error("ServiceInfo.Status not set")
	}
	if info.PID != 1234 {
		t.Error("ServiceInfo.PID not set")
	}
	if info.Port != 5432 {
		t.Error("ServiceInfo.Port not set")
	}
}

func TestServiceStartInfo(t *testing.T) {
	info := ServiceStartInfo{
		Name:        "postgres",
		DisplayName: "PostgreSQL",
		State:       StateRunning,
		Progress:    1.0,
		Message:     "Started",
	}

	if info.State != StateRunning {
		t.Error("ServiceStartInfo.State not set")
	}
	if info.Progress != 1.0 {
		t.Error("ServiceStartInfo.Progress not set")
	}
}
