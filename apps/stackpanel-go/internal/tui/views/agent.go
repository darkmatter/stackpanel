package views

import (
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

// AgentView provides a split-screen view with streaming logs and command menu
type AgentView struct {
	// Layout
	width      int
	height     int
	splitRatio float64 // 0.0-1.0, portion for logs panel

	// Logs panel (left)
	logsViewport viewport.Model
	logs         []string
	autoScroll   bool

	// Menu panel (right)
	menuItems   []AgentMenuItem
	selectedIdx int

	// State
	spinner   spinner.Model
	focus     AgentFocus
	quitting  bool
	connected bool

	// For navigation integration
	returnMsg tea.Msg
}

// AgentFocus indicates which panel has focus
type AgentFocus int

const (
	FocusLogs AgentFocus = iota
	FocusMenu
)

// AgentMenuItem represents a menu item in the agent view
type AgentMenuItem struct {
	Name        string
	Description string
	Action      func() tea.Cmd
}

// Agent messages
type (
	agentLogMsg       string
	agentConnectedMsg struct{}
	agentTickMsg      struct{}
)

// ReturnFromAgentMsg signals return to navigation
type ReturnFromAgentMsg struct{}

// AgentViewOption configures the AgentView
type AgentViewOption func(*AgentView)

// WithAgentReturnMsg sets a custom message to send when returning
func WithAgentReturnMsg(msg tea.Msg) AgentViewOption {
	return func(v *AgentView) {
		v.returnMsg = msg
	}
}

// WithSplitRatio sets the split ratio (0.0-1.0 for logs panel width)
func WithSplitRatio(ratio float64) AgentViewOption {
	return func(v *AgentView) {
		if ratio < 0.2 {
			ratio = 0.2
		}
		if ratio > 0.8 {
			ratio = 0.8
		}
		v.splitRatio = ratio
	}
}

// WithMenuItems sets the menu items
func WithMenuItems(items []AgentMenuItem) AgentViewOption {
	return func(v *AgentView) {
		v.menuItems = items
	}
}

// NewAgentView creates a new agent split view
func NewAgentView(opts ...AgentViewOption) AgentView {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = tui.SpinnerStyle

	// Default menu items
	defaultMenu := []AgentMenuItem{
		{Name: "Status", Description: "Show agent status"},
		{Name: "Restart", Description: "Restart the agent"},
		{Name: "Clear Logs", Description: "Clear the log view"},
		{Name: "Back", Description: "Return to menu"},
	}

	view := AgentView{
		splitRatio:   0.6, // 60% for logs
		logsViewport: viewport.New(40, 20),
		logs:         []string{},
		autoScroll:   true,
		menuItems:    defaultMenu,
		selectedIdx:  0,
		spinner:      s,
		focus:        FocusLogs,
		connected:    false,
	}

	for _, opt := range opts {
		opt(&view)
	}

	return view
}

// Init implements tea.Model
func (m AgentView) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		m.tickCmd(),
	)
}

func (m AgentView) tickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return agentTickMsg{}
	})
}

// Update implements tea.Model
func (m AgentView) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKeyMsg(msg)

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.updateLayout()

	case agentLogMsg:
		m.addLog(string(msg))

	case agentConnectedMsg:
		m.connected = true
		m.addLog("Agent connected")

	case agentTickMsg:
		cmds = append(cmds, m.tickCmd())

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)
	}

	// Update viewport if focused on logs
	if m.focus == FocusLogs {
		var cmd tea.Cmd
		m.logsViewport, cmd = m.logsViewport.Update(msg)
		cmds = append(cmds, cmd)
	}

	return m, tea.Batch(cmds...)
}

func (m AgentView) handleKeyMsg(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c":
		m.quitting = true
		return m, tea.Quit

	case "esc":
		if m.returnMsg != nil {
			return m, func() tea.Msg { return m.returnMsg }
		}
		return m, func() tea.Msg { return ReturnFromAgentMsg{} }

	case "tab":
		// Toggle focus between panels
		if m.focus == FocusLogs {
			m.focus = FocusMenu
		} else {
			m.focus = FocusLogs
		}
		return m, nil

	case "up", "k":
		if m.focus == FocusMenu {
			if m.selectedIdx > 0 {
				m.selectedIdx--
			}
		}
		return m, nil

	case "down", "j":
		if m.focus == FocusMenu {
			if m.selectedIdx < len(m.menuItems)-1 {
				m.selectedIdx++
			}
		}
		return m, nil

	case "enter", " ":
		if m.focus == FocusMenu {
			return m.executeMenuItem()
		}
		return m, nil

	case "a":
		// Toggle auto-scroll
		m.autoScroll = !m.autoScroll
		return m, nil

	case "c":
		// Clear logs
		m.logs = []string{}
		m.updateLogsContent()
		return m, nil
	}

	return m, nil
}

func (m AgentView) executeMenuItem() (tea.Model, tea.Cmd) {
	if m.selectedIdx >= len(m.menuItems) {
		return m, nil
	}

	item := m.menuItems[m.selectedIdx]

	// Handle built-in actions
	switch item.Name {
	case "Back":
		if m.returnMsg != nil {
			return m, func() tea.Msg { return m.returnMsg }
		}
		return m, func() tea.Msg { return ReturnFromAgentMsg{} }
	case "Clear Logs":
		m.logs = []string{}
		m.updateLogsContent()
		return m, nil
	case "Status":
		m.addLog("Agent status: " + m.statusText())
		return m, nil
	case "Restart":
		m.addLog("Restarting agent...")
		m.connected = false
		return m, nil
	}

	// Custom action
	if item.Action != nil {
		return m, item.Action()
	}

	return m, nil
}

func (m *AgentView) addLog(line string) {
	timestamp := time.Now().Format("15:04:05")
	m.logs = append(m.logs, timestamp+" "+line)

	// Limit log history
	if len(m.logs) > 1000 {
		m.logs = m.logs[len(m.logs)-1000:]
	}

	m.updateLogsContent()
}

func (m *AgentView) updateLogsContent() {
	content := strings.Join(m.logs, "\n")
	m.logsViewport.SetContent(content)

	if m.autoScroll {
		m.logsViewport.GotoBottom()
	}
}

func (m *AgentView) updateLayout() {
	// Calculate panel widths
	logsWidth := int(float64(m.width) * m.splitRatio)
	menuWidth := m.width - logsWidth - 3 // 3 for divider

	// Account for borders and padding
	contentHeight := m.height - 4 // header + footer

	// Update logs viewport
	m.logsViewport.Width = logsWidth - 4
	m.logsViewport.Height = contentHeight - 2

	_ = menuWidth // Used in View()
}

func (m AgentView) statusText() string {
	if m.connected {
		return "Connected"
	}
	return "Disconnected"
}

// View implements tea.Model
func (m AgentView) View() string {
	if m.quitting {
		return ""
	}

	// Handle zero dimensions (before window size message)
	if m.width < 20 || m.height < 10 {
		return tui.RenderFrame("Initializing...")
	}

	// Calculate panel widths
	logsWidth := int(float64(m.width) * m.splitRatio)
	menuWidth := m.width - logsWidth - 1 // 1 for divider

	// Header
	header := m.renderHeader()

	// Logs panel
	logsPanel := m.renderLogsPanel(logsWidth)

	// Menu panel
	menuPanel := m.renderMenuPanel(menuWidth)

	// Divider
	divider := lipgloss.NewStyle().
		Foreground(tui.ColorBorder).
		Render(strings.Repeat("│\n", m.height-4))

	// Join panels horizontally
	content := lipgloss.JoinHorizontal(
		lipgloss.Top,
		logsPanel,
		divider,
		menuPanel,
	)

	// Footer
	footer := m.renderFooter()

	return tui.RenderFrame(lipgloss.JoinVertical(lipgloss.Left, header, content, footer))
}

func (m AgentView) renderHeader() string {
	title := lipgloss.NewStyle().
		Foreground(tui.ColorSecondary).
		Bold(true).
		Render("Agent Monitor")

	status := m.spinner.View() + " "
	if m.connected {
		status = tui.RenderSuccess("Connected")
	} else {
		status += tui.TextDim.Render("Connecting...")
	}

	// Right-align status
	gap := m.width - lipgloss.Width(title) - lipgloss.Width(status) - 2
	if gap < 0 {
		gap = 0
	}

	return title + strings.Repeat(" ", gap) + status + "\n"
}

func (m AgentView) renderLogsPanel(width int) string {
	// Panel title
	titleStyle := lipgloss.NewStyle().
		Foreground(tui.ColorPrimary).
		Bold(true)

	title := titleStyle.Render("Logs")
	if m.focus == FocusLogs {
		title = titleStyle.Foreground(tui.ColorSecondary).Render("▶ Logs")
	}

	autoScrollIndicator := ""
	if m.autoScroll {
		autoScrollIndicator = tui.TextDim.Render(" [auto-scroll]")
	}

	// Logs content
	logsStyle := lipgloss.NewStyle().
		Width(width-2).
		Height(m.height-6).
		BorderStyle(lipgloss.RoundedBorder()).
		BorderForeground(tui.ColorBorder).
		Padding(0, 1)

	if m.focus == FocusLogs {
		logsStyle = logsStyle.BorderForeground(tui.ColorPrimary)
	}

	content := m.logsViewport.View()
	if len(m.logs) == 0 {
		content = tui.TextDim.Render("No logs yet...")
	}

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title+autoScrollIndicator,
		logsStyle.Render(content),
	)
}

func (m AgentView) renderMenuPanel(width int) string {
	// Panel title
	titleStyle := lipgloss.NewStyle().
		Foreground(tui.ColorPrimary).
		Bold(true)

	title := titleStyle.Render("Commands")
	if m.focus == FocusMenu {
		title = titleStyle.Foreground(tui.ColorSecondary).Render("▶ Commands")
	}

	// Menu items
	var menuContent strings.Builder
	for i, item := range m.menuItems {
		isSelected := i == m.selectedIdx && m.focus == FocusMenu

		itemStyle := lipgloss.NewStyle().
			Width(width-6).
			Padding(0, 1)

		cursor := "  "
		if isSelected {
			cursor = tui.SymbolArrow + " "
			itemStyle = itemStyle.
				Foreground(tui.ColorWhite).
				Background(tui.ColorPrimary).
				Bold(true)
		}

		name := itemStyle.Render(cursor + item.Name)
		menuContent.WriteString(name)
		menuContent.WriteString("\n")

		// Description
		if item.Description != "" && isSelected {
			descStyle := lipgloss.NewStyle().
				Foreground(tui.ColorDim).
				PaddingLeft(4)
			menuContent.WriteString(descStyle.Render(item.Description))
			menuContent.WriteString("\n")
		}
	}

	// Menu container
	menuStyle := lipgloss.NewStyle().
		Width(width-2).
		Height(m.height-6).
		BorderStyle(lipgloss.RoundedBorder()).
		BorderForeground(tui.ColorBorder).
		Padding(0, 1)

	if m.focus == FocusMenu {
		menuStyle = menuStyle.BorderForeground(tui.ColorPrimary)
	}

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		menuStyle.Render(menuContent.String()),
	)
}

func (m AgentView) renderFooter() string {
	var hints []string

	hints = append(hints, "tab: switch panel")
	if m.focus == FocusLogs {
		hints = append(hints, "a: toggle auto-scroll")
		hints = append(hints, "↑/↓: scroll")
	} else {
		hints = append(hints, "↑/↓: select")
		hints = append(hints, "enter: execute")
	}
	hints = append(hints, "esc: back")
	hints = append(hints, "q: quit")

	return tui.HelpStyle.Render(strings.Join(hints, " • "))
}

// AddLog adds a log line to the agent view (for external use)
func (m *AgentView) AddLog(line string) {
	m.addLog(line)
}

// SetConnected sets the connection status
func (m *AgentView) SetConnected(connected bool) {
	m.connected = connected
}

// RunAgentView launches the agent view as a standalone program
func RunAgentView(opts ...AgentViewOption) error {
	model := NewAgentView(opts...)
	p := tea.NewProgram(model, tea.WithAltScreen())
	_, err := p.Run()
	return err
}
