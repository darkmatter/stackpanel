package views

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/darkmatter/stackpanel/cli/internal/tui"
	svc "github.com/darkmatter/stackpanel/packages/stackpanel-go/services"
)

// ServiceStartState represents the state of a service being started
type ServiceStartState int

const (
	StateWaiting ServiceStartState = iota
	StateStarting
	StateRunning
	StateFailed
	StateSkipped
)

// ServiceStartInfo holds information about a service being started
type ServiceStartInfo struct {
	Name        string
	DisplayName string
	State       ServiceStartState
	Progress    float64
	Message     string
	Error       error
}

// ServicesView is the Bubble Tea model for starting/managing services
type ServicesView struct {
	services   []ServiceStartInfo
	currentIdx int
	spinner    spinner.Model
	progress   progress.Model
	width      int
	height     int
	done       bool
	quitting   bool
	mode       ServicesViewMode
	// For navigation integration
	returnMsg tea.Msg
}

// ServicesViewMode determines what the view is doing
type ServicesViewMode int

const (
	ModeStart ServicesViewMode = iota
	ModeStop
	ModeRestart
)

// Service start messages
type (
	serviceStartedMsg struct {
		idx     int
		success bool
		message string
		err     error
	}
	serviceStoppedMsg struct {
		idx     int
		success bool
		message string
		err     error
	}
	startNextServiceMsg struct{}
	stopNextServiceMsg  struct{}
)

// ReturnFromServicesMsg signals return to navigation
type ReturnFromServicesMsg struct{}

// ServicesViewOption configures the ServicesView
type ServicesViewOption func(*ServicesView)

// WithServicesReturnMsg sets a custom message to send when returning
func WithServicesReturnMsg(msg tea.Msg) ServicesViewOption {
	return func(v *ServicesView) {
		v.returnMsg = msg
	}
}

// WithMode sets the operation mode (start, stop, restart)
func WithMode(mode ServicesViewMode) ServicesViewOption {
	return func(v *ServicesView) {
		v.mode = mode
	}
}

// NewServicesView creates a model for starting/stopping services
func NewServicesView(serviceNames []string, opts ...ServicesViewOption) ServicesView {
	// If no services specified, use all
	if len(serviceNames) == 0 {
		serviceNames = svc.Names()
	}

	svcInfos := make([]ServiceStartInfo, len(serviceNames))
	for i, name := range serviceNames {
		displayName := name
		if s := svc.Get(name); s != nil {
			displayName = s.DisplayName()
		}
		svcInfos[i] = ServiceStartInfo{
			Name:        name,
			DisplayName: displayName,
			State:       StateWaiting,
		}
	}

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = tui.SpinnerStyle

	p := progress.New(
		progress.WithDefaultGradient(),
		progress.WithWidth(40),
		progress.WithoutPercentage(),
	)

	view := ServicesView{
		services:   svcInfos,
		currentIdx: 0,
		spinner:    s,
		progress:   p,
		mode:       ModeStart,
	}

	for _, opt := range opts {
		opt(&view)
	}

	// Mark first service as starting
	if len(view.services) > 0 {
		view.services[0].State = StateStarting
	}

	return view
}

// Init implements tea.Model
func (m ServicesView) Init() tea.Cmd {
	if len(m.services) == 0 {
		return nil
	}

	switch m.mode {
	case ModeStop:
		return tea.Batch(
			m.spinner.Tick,
			m.stopServiceCmd(m.services[0].Name, 0),
		)
	default:
		return tea.Batch(
			m.spinner.Tick,
			m.startServiceCmd(m.services[0].Name, 0),
		)
	}
}

func (m ServicesView) startServiceCmd(name string, idx int) tea.Cmd {
	return func() tea.Msg {
		s := svc.Get(name)
		if s == nil {
			return serviceStartedMsg{
				idx:     idx,
				success: false,
				message: "Unknown service",
				err:     fmt.Errorf("unknown service: %s", name),
			}
		}

		// Check if already running
		status := s.Status()
		if status.Running {
			return serviceStartedMsg{
				idx:     idx,
				success: true,
				message: fmt.Sprintf("Already running (PID: %d)", status.PID),
			}
		}

		// Start the service
		if err := s.Start(); err != nil {
			return serviceStartedMsg{
				idx:     idx,
				success: false,
				message: "Start failed",
				err:     err,
			}
		}

		// Get new status for the message
		newStatus := s.Status()
		message := fmt.Sprintf("Started on port %d", s.Port())
		if newStatus.PID > 0 {
			message = fmt.Sprintf("Started (PID: %d)", newStatus.PID)
		}

		return serviceStartedMsg{
			idx:     idx,
			success: true,
			message: message,
		}
	}
}

func (m ServicesView) stopServiceCmd(name string, idx int) tea.Cmd {
	return func() tea.Msg {
		s := svc.Get(name)
		if s == nil {
			return serviceStoppedMsg{
				idx:     idx,
				success: false,
				message: "Unknown service",
				err:     fmt.Errorf("unknown service: %s", name),
			}
		}

		// Check if already stopped
		status := s.Status()
		if !status.Running {
			return serviceStoppedMsg{
				idx:     idx,
				success: true,
				message: "Already stopped",
			}
		}

		// Stop the service
		if err := s.Stop(); err != nil {
			return serviceStoppedMsg{
				idx:     idx,
				success: false,
				message: "Stop failed",
				err:     err,
			}
		}

		return serviceStoppedMsg{
			idx:     idx,
			success: true,
			message: "Stopped",
		}
	}
}

// Update implements tea.Model
func (m ServicesView) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		case "esc":
			if m.done {
				if m.returnMsg != nil {
					return m, func() tea.Msg { return m.returnMsg }
				}
				return m, func() tea.Msg { return ReturnFromServicesMsg{} }
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.progress.Width = msg.Width - 20

	case serviceStartedMsg:
		return m.handleServiceStarted(msg)

	case serviceStoppedMsg:
		return m.handleServiceStopped(msg)

	case startNextServiceMsg:
		if m.currentIdx < len(m.services) {
			return m, m.startServiceCmd(m.services[m.currentIdx].Name, m.currentIdx)
		}

	case stopNextServiceMsg:
		if m.currentIdx < len(m.services) {
			return m, m.stopServiceCmd(m.services[m.currentIdx].Name, m.currentIdx)
		}

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case progress.FrameMsg:
		newModel, cmd := m.progress.Update(msg)
		if pm, ok := newModel.(progress.Model); ok {
			m.progress = pm
		}
		return m, cmd
	}

	return m, nil
}

func (m ServicesView) handleServiceStarted(msg serviceStartedMsg) (tea.Model, tea.Cmd) {
	if msg.idx < len(m.services) {
		if msg.success {
			m.services[msg.idx].State = StateRunning
		} else {
			m.services[msg.idx].State = StateFailed
			m.services[msg.idx].Error = msg.err
		}
		m.services[msg.idx].Message = msg.message
		m.services[msg.idx].Progress = 1.0

		// Start next service
		m.currentIdx++
		if m.currentIdx < len(m.services) {
			m.services[m.currentIdx].State = StateStarting
			return m, tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg {
				return startNextServiceMsg{}
			})
		}
		m.done = true
		return m, tea.Tick(500*time.Millisecond, func(t time.Time) tea.Msg {
			return nil // Stay on screen, don't auto-quit
		})
	}
	return m, nil
}

func (m ServicesView) handleServiceStopped(msg serviceStoppedMsg) (tea.Model, tea.Cmd) {
	if msg.idx < len(m.services) {
		if msg.success {
			m.services[msg.idx].State = StateRunning // Use running to indicate "done" for stop
			m.services[msg.idx].Message = msg.message
		} else {
			m.services[msg.idx].State = StateFailed
			m.services[msg.idx].Error = msg.err
			m.services[msg.idx].Message = msg.message
		}
		m.services[msg.idx].Progress = 1.0

		// Stop next service
		m.currentIdx++
		if m.currentIdx < len(m.services) {
			m.services[m.currentIdx].State = StateStarting
			return m, tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg {
				return stopNextServiceMsg{}
			})
		}
		m.done = true
		return m, nil
	}
	return m, nil
}

// View implements tea.Model
func (m ServicesView) View() string {
	if m.quitting {
		return ""
	}

	var b strings.Builder

	// Header
	var title string
	switch m.mode {
	case ModeStop:
		title = "Stopping Services"
	case ModeRestart:
		title = "Restarting Services"
	default:
		title = "Starting Services"
	}

	header := lipgloss.NewStyle().
		Foreground(tui.ColorSecondary).
		Bold(true).
		MarginBottom(1).
		Render(title)
	b.WriteString(header)
	b.WriteString("\n\n")

	// Services list
	for i, s := range m.services {
		line := "  "

		switch s.State {
		case StateWaiting:
			line += tui.TextDim.Render(tui.SymbolStopped + " " + s.DisplayName)
			line += tui.TextDim.Render(" (waiting)")
		case StateStarting:
			line += tui.SpinnerStyle.Render(m.spinner.View())
			line += " " + s.DisplayName
			if m.mode == ModeStop {
				line += tui.TextDim.Render(" (stopping...)")
			} else {
				line += tui.TextDim.Render(" (starting...)")
			}
		case StateRunning:
			line += tui.RenderSuccess(s.DisplayName)
			if s.Message != "" {
				line += tui.TextDim.Render(" - " + s.Message)
			}
		case StateFailed:
			line += tui.RenderError(s.DisplayName)
			if s.Message != "" {
				line += " " + tui.TextDim.Render(s.Message)
			}
		case StateSkipped:
			line += tui.TextDim.Render(tui.SymbolStopped + " " + s.DisplayName + " (skipped)")
		}

		b.WriteString(line)
		b.WriteString("\n")

		// Show progress bar for current service
		if s.State == StateStarting && i == m.currentIdx {
			b.WriteString("    ")
			b.WriteString(m.progress.ViewAs(0.5))
			b.WriteString("\n")
		}
	}

	// Done message
	if m.done {
		b.WriteString("\n")
		successCount := 0
		failCount := 0
		for _, s := range m.services {
			if s.State == StateRunning {
				successCount++
			} else if s.State == StateFailed {
				failCount++
			}
		}

		var doneMsg string
		switch m.mode {
		case ModeStop:
			if failCount == 0 {
				doneMsg = fmt.Sprintf("All %d services stopped successfully!", successCount)
			} else {
				doneMsg = fmt.Sprintf("%d stopped, %d failed", successCount, failCount)
			}
		default:
			if failCount == 0 {
				doneMsg = fmt.Sprintf("All %d services started successfully!", successCount)
			} else {
				doneMsg = fmt.Sprintf("%d started, %d failed", successCount, failCount)
			}
		}

		if failCount == 0 {
			b.WriteString(tui.RenderSuccess(doneMsg))
		} else {
			b.WriteString(tui.RenderWarning(doneMsg))
		}
		b.WriteString("\n")

		// Help text for returning
		help := tui.HelpStyle.Render("\nPress esc to return")
		b.WriteString(help)
	}

	return b.String()
}

// RunServicesStart launches the service start view
func RunServicesStart(serviceNames []string) error {
	model := NewServicesView(serviceNames)
	p := tea.NewProgram(model)
	_, err := p.Run()
	return err
}

// RunServicesStop launches the service stop view
func RunServicesStop(serviceNames []string) error {
	model := NewServicesView(serviceNames, WithMode(ModeStop))
	p := tea.NewProgram(model)
	_, err := p.Run()
	return err
}
