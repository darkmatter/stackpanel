package tui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	svc "github.com/darkmatter/stackpanel/apps/stackpanel-go/pkg/services"
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

// StartServicesModel is the Bubble Tea model for starting services
type StartServicesModel struct {
	services   []ServiceStartInfo
	currentIdx int
	spinner    spinner.Model
	progress   progress.Model
	width      int
	done       bool
	quitting   bool
}

// Messages for service start
type (
	serviceStartedMsg struct {
		idx     int
		success bool
		message string
		err     error
	}
	serviceProgressMsg struct {
		idx      int
		progress float64
		message  string
	}
	startNextServiceMsg struct{}
)

// NewStartServicesModel creates a model for starting services
func NewStartServicesModel(serviceNames []string) StartServicesModel {
	svcInfos := make([]ServiceStartInfo, len(serviceNames))
	for i, name := range serviceNames {
		displayName := name
		if svc := svc.Get(name); svc != nil {
			displayName = svc.DisplayName()
		}
		svcInfos[i] = ServiceStartInfo{
			Name:        name,
			DisplayName: displayName,
			State:       StateWaiting,
		}
	}

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = SpinnerStyle

	p := progress.New(
		progress.WithDefaultGradient(),
		progress.WithWidth(40),
		progress.WithoutPercentage(),
	)

	return StartServicesModel{
		services:   svcInfos,
		currentIdx: 0,
		spinner:    s,
		progress:   p,
	}
}

func (m StartServicesModel) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		startServiceCmd(m.services[0].Name, 0),
	)
}

func startServiceCmd(name string, idx int) tea.Cmd {
	return func() tea.Msg {
		svc := svc.Get(name)
		if svc == nil {
			return serviceStartedMsg{
				idx:     idx,
				success: false,
				message: "Unknown service",
				err:     fmt.Errorf("unknown service: %s", name),
			}
		}

		// Check if already running
		status := svc.Status()
		if status.Running {
			return serviceStartedMsg{
				idx:     idx,
				success: true,
				message: fmt.Sprintf("Already running (PID: %d)", status.PID),
			}
		}

		// Start the service
		if err := svc.Start(); err != nil {
			return serviceStartedMsg{
				idx:     idx,
				success: false,
				message: "Start failed",
				err:     err,
			}
		}

		// Get new status for the message
		newStatus := svc.Status()
		message := fmt.Sprintf("Started on port %d", svc.Port())
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

func (m StartServicesModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			m.quitting = true
			return m, tea.Quit
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.progress.Width = msg.Width - 20

	case serviceStartedMsg:
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
				return m, tea.Batch(
					tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg {
						return startNextServiceMsg{}
					}),
				)
			} else {
				m.done = true
				return m, tea.Tick(500*time.Millisecond, func(t time.Time) tea.Msg {
					return tea.Quit()
				})
			}
		}

	case startNextServiceMsg:
		if m.currentIdx < len(m.services) {
			return m, startServiceCmd(m.services[m.currentIdx].Name, m.currentIdx)
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

func (m StartServicesModel) View() string {
	if m.quitting {
		return ""
	}

	var b strings.Builder

	// Header
	header := TitleStyle.Render("Starting Services")
	b.WriteString(header)
	b.WriteString("\n\n")

	// Services
	for i, svc := range m.services {
		line := "  "

		switch svc.State {
		case StateWaiting:
			line += TextDim.Render(SymbolStopped + " " + svc.DisplayName)
			line += TextDim.Render(" (waiting)")
		case StateStarting:
			line += SpinnerStyle.Render(m.spinner.View())
			line += " " + svc.DisplayName
			line += TextDim.Render(" (starting...)")
		case StateRunning:
			line += RenderSuccess(svc.DisplayName)
			if svc.Message != "" {
				line += TextDim.Render(" - " + svc.Message)
			}
		case StateFailed:
			line += RenderError(svc.DisplayName)
			if svc.Message != "" {
				line += " " + TextDim.Render(svc.Message)
			}
		case StateSkipped:
			line += TextDim.Render(SymbolStopped + " " + svc.DisplayName + " (skipped)")
		}

		b.WriteString(line)
		b.WriteString("\n")

		// Show progress bar for starting service
		if svc.State == StateStarting && i == m.currentIdx {
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
		for _, svc := range m.services {
			if svc.State == StateRunning {
				successCount++
			} else if svc.State == StateFailed {
				failCount++
			}
		}
		if failCount == 0 {
			b.WriteString(RenderSuccess(fmt.Sprintf("All %d services started successfully!", successCount)))
		} else {
			b.WriteString(RenderWarning(fmt.Sprintf("%d started, %d failed", successCount, failCount)))
		}
		b.WriteString("\n")
	}

	return b.String()
}

// RunStartServices launches the interactive service start TUI
func RunStartServices(serviceNames []string) error {
	if len(serviceNames) == 0 {
		serviceNames = svc.Names()
	}

	// Mark first service as starting
	model := NewStartServicesModel(serviceNames)
	model.services[0].State = StateStarting

	p := tea.NewProgram(model)
	_, err := p.Run()
	return err
}
