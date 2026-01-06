package views

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/table"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/darkmatter/stackpanel/apps/stackpanel-go/internal/tui"
	svc "github.com/darkmatter/stackpanel/apps/stackpanel-go/pkg/services"
)

// ServiceInfo holds status information for a service
type ServiceInfo struct {
	Name        string
	DisplayName string
	Status      string // running, stopped, starting, error
	PID         int
	Port        int
	Details     string
}

// StatusView is the Bubble Tea model for the status dashboard
// Refactored to integrate with the navigation system
type StatusView struct {
	services    []ServiceInfo
	caddyInfo   ServiceInfo
	certStatus  string
	table       table.Model
	spinner     spinner.Model
	width       int
	height      int
	loading     bool
	lastRefresh time.Time
	refreshing  bool
	quitting    bool
	// For navigation integration
	returnMsg tea.Msg
}

// Status messages
type (
	statusServicesUpdatedMsg []ServiceInfo
	statusCaddyUpdatedMsg    ServiceInfo
	statusCertUpdatedMsg     string
	statusTickMsg            struct{}
)

// ReturnFromStatusMsg signals return to navigation
type ReturnFromStatusMsg struct{}

// Configuration
var (
	caddyConfigDir = filepath.Join(os.Getenv("HOME"), ".config", "caddy")
)

// StatusViewOption configures the StatusView
type StatusViewOption func(*StatusView)

// WithReturnMsg sets a custom message to send when returning
func WithStatusReturnMsg(msg tea.Msg) StatusViewOption {
	return func(v *StatusView) {
		v.returnMsg = msg
	}
}

// NewStatusView creates a new status dashboard view
func NewStatusView(opts ...StatusViewOption) StatusView {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = tui.SpinnerStyle

	// Create table with proper column widths
	columns := []table.Column{
		{Title: "Service", Width: 14},
		{Title: "Status", Width: 12},
		{Title: "PID", Width: 8},
		{Title: "Port", Width: 8},
		{Title: "Details", Width: 30},
	}

	t := table.New(
		table.WithColumns(columns),
		table.WithFocused(true),
		table.WithHeight(7),
	)

	// Apply styles
	styles := table.DefaultStyles()
	styles.Header = styles.Header.
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(tui.ColorBorder).
		BorderBottom(true).
		Bold(true).
		Foreground(tui.ColorSubtle)
	styles.Selected = styles.Selected.
		Foreground(lipgloss.Color("#FFFFFF")).
		Background(tui.ColorPrimary).
		Bold(false)
	styles.Cell = styles.Cell.
		Padding(0, 1)
	t.SetStyles(styles)

	view := StatusView{
		spinner:     s,
		table:       t,
		loading:     true,
		lastRefresh: time.Now(),
	}

	for _, opt := range opts {
		opt(&view)
	}

	return view
}

// Init implements tea.Model
func (m StatusView) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		m.refreshServices,
		m.refreshCaddy,
		m.refreshCerts,
		m.tickCmd(),
	)
}

func (m StatusView) tickCmd() tea.Cmd {
	return tea.Tick(2*time.Second, func(t time.Time) tea.Msg {
		return statusTickMsg{}
	})
}

func (m StatusView) refreshServices() tea.Msg {
	var svcInfos []ServiceInfo

	for _, s := range svc.All() {
		status := s.Status()
		info := ServiceInfo{
			Name:        s.Name(),
			DisplayName: s.DisplayName(),
			Port:        s.Port(),
			Status:      "stopped",
		}

		if status.Running {
			info.Status = "running"
			info.PID = status.PID
			// Get extended status info
			var details []string
			for key, val := range s.StatusInfo() {
				if key != "Socket" { // Skip verbose socket paths
					details = append(details, val)
				}
			}
			if len(details) > 0 {
				info.Details = strings.Join(details, ", ")
			}
		}

		svcInfos = append(svcInfos, info)
	}

	return statusServicesUpdatedMsg(svcInfos)
}

func (m StatusView) refreshCaddy() tea.Msg {
	info := ServiceInfo{
		Name:        "caddy",
		DisplayName: "Caddy",
		Status:      "stopped",
	}

	pidFile := filepath.Join(caddyConfigDir, "caddy.pid")
	pid := readPidFile(pidFile)

	if pid > 0 && svc.IsProcessRunning(pid) {
		info.Status = "running"
		info.PID = pid
		info.Details = countSites()
	}

	return statusCaddyUpdatedMsg(info)
}

func (m StatusView) refreshCerts() tea.Msg {
	stateDir := findStateDir()
	hostname, _ := os.Hostname()
	certFile := filepath.Join(stateDir, hostname+".crt")

	if _, err := os.Stat(certFile); os.IsNotExist(err) {
		return statusCertUpdatedMsg("No certificate")
	}

	// Check validity
	cmd := exec.Command("step", "certificate", "inspect", certFile, "--format", "json")
	output, err := cmd.Output()
	if err != nil {
		return statusCertUpdatedMsg("Error checking cert")
	}

	if strings.Contains(string(output), "expired") {
		return statusCertUpdatedMsg("Expired")
	}

	return statusCertUpdatedMsg("Valid")
}

// Update implements tea.Model
func (m StatusView) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		case "esc":
			// Return to navigation
			if m.returnMsg != nil {
				return m, func() tea.Msg { return m.returnMsg }
			}
			return m, func() tea.Msg { return ReturnFromStatusMsg{} }
		case "r":
			m.refreshing = true
			return m, tea.Batch(
				m.refreshServices,
				m.refreshCaddy,
				m.refreshCerts,
			)
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		// Adjust table width with padding
		m.table.SetWidth(msg.Width - 4)
		m.table.SetHeight(min(10, msg.Height-20))

	case statusServicesUpdatedMsg:
		m.services = msg
		m.loading = false
		m.refreshing = false
		m.lastRefresh = time.Now()
		m.updateTable()

	case statusCaddyUpdatedMsg:
		m.caddyInfo = ServiceInfo(msg)

	case statusCertUpdatedMsg:
		m.certStatus = string(msg)

	case statusTickMsg:
		cmds = append(cmds, tea.Batch(
			m.refreshServices,
			m.refreshCaddy,
			m.refreshCerts,
			m.tickCmd(),
		))

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)
	}

	// Update table
	var cmd tea.Cmd
	m.table, cmd = m.table.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

func (m *StatusView) updateTable() {
	var rows []table.Row
	for _, s := range m.services {
		status := m.renderStatusBadge(s.Status)
		pidStr := "-"
		if s.PID > 0 {
			pidStr = strconv.Itoa(s.PID)
		}
		portStr := "-"
		if s.Port > 0 {
			portStr = strconv.Itoa(s.Port)
		}
		rows = append(rows, table.Row{
			s.DisplayName,
			status,
			pidStr,
			portStr,
			s.Details,
		})
	}
	m.table.SetRows(rows)
}

func (m StatusView) renderStatusBadge(status string) string {
	switch status {
	case "running":
		return tui.StatusRunning.Render(tui.SymbolRunning + " running")
	case "stopped":
		return tui.StatusStopped.Render(tui.SymbolStopped + " stopped")
	case "starting":
		return tui.StatusStarting.Render(tui.SymbolStarting + " starting")
	case "error":
		return tui.StatusError.Render(tui.SymbolError + " error")
	default:
		return tui.TextDim.Render(status)
	}
}

// View implements tea.Model
func (m StatusView) View() string {
	if m.quitting {
		return ""
	}

	var b strings.Builder

	// Header
	header := lipgloss.NewStyle().
		Foreground(tui.ColorSecondary).
		Bold(true).
		MarginBottom(1).
		Render("Status Dashboard")
	b.WriteString(header)
	b.WriteString("\n\n")

	// Loading state
	if m.loading {
		b.WriteString(m.spinner.View())
		b.WriteString(" Loading services...")
		return b.String()
	}

	// Services section
	sectionHeader := lipgloss.NewStyle().
		Foreground(tui.ColorPrimary).
		Bold(true)

	b.WriteString(sectionHeader.Render(tui.SymbolArrow + " Development Services"))
	if m.refreshing {
		b.WriteString(" ")
		b.WriteString(m.spinner.View())
	}
	b.WriteString("\n\n")

	// Table with border
	tableStyle := lipgloss.NewStyle().
		BorderStyle(lipgloss.RoundedBorder()).
		BorderForeground(tui.ColorBorder).
		Padding(0, 1)
	b.WriteString(tableStyle.Render(m.table.View()))
	b.WriteString("\n")

	// Caddy section
	b.WriteString("\n")
	b.WriteString(sectionHeader.Render(tui.SymbolArrow + " Reverse Proxy"))
	b.WriteString("\n")
	caddyLine := "  "
	if m.caddyInfo.Status == "running" {
		caddyLine += tui.StatusRunning.Render(tui.SymbolRunning + " Caddy")
		caddyLine += tui.TextDim.Render(fmt.Sprintf(" (PID: %d)", m.caddyInfo.PID))
		if m.caddyInfo.Details != "" {
			caddyLine += tui.TextDim.Render(" - " + m.caddyInfo.Details)
		}
	} else {
		caddyLine += tui.StatusStopped.Render(tui.SymbolStopped + " Caddy (stopped)")
	}
	b.WriteString(caddyLine)
	b.WriteString("\n")

	// Certs section
	b.WriteString("\n")
	b.WriteString(sectionHeader.Render(tui.SymbolArrow + " Certificates"))
	b.WriteString("\n")
	certLine := "  "
	switch m.certStatus {
	case "Valid":
		certLine += tui.RenderSuccess("Device certificate valid")
	case "Expired":
		certLine += tui.RenderWarning("Device certificate expired")
	case "No certificate":
		certLine += tui.TextDim.Render(tui.SymbolStopped + " No device certificate")
	default:
		certLine += tui.TextDim.Render(tui.SymbolStopped + " " + m.certStatus)
	}
	b.WriteString(certLine)
	b.WriteString("\n")

	// Last refresh time
	b.WriteString("\n")
	refreshInfo := tui.TextDim.Render(fmt.Sprintf("Last refresh: %s", m.lastRefresh.Format("15:04:05")))
	b.WriteString(refreshInfo)

	// Help
	help := tui.HelpStyle.Render("\n\nr: refresh • esc: back • q: quit")
	b.WriteString(help)

	return b.String()
}

// Helper functions

func readPidFile(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	pid, _ := strconv.Atoi(strings.TrimSpace(string(data)))
	return pid
}

func countSites() string {
	sitesDir := filepath.Join(caddyConfigDir, "sites.d")
	entries, _ := os.ReadDir(sitesDir)
	count := 0
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".caddy") {
			count++
		}
	}
	if count > 0 {
		return fmt.Sprintf("%d site(s)", count)
	}
	return ""
}

func findStateDir() string {
	cwd, _ := os.Getwd()
	dir := cwd
	for {
		if _, err := os.Stat(filepath.Join(dir, ".stackpanel")); err == nil {
			return filepath.Join(dir, ".stackpanel", "state", "step")
		}
		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
			return filepath.Join(dir, ".stackpanel", "state", "step")
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return filepath.Join(cwd, ".stackpanel", "state", "step")
}

// RunStatusView launches the status dashboard as a standalone program
func RunStatusView() error {
	p := tea.NewProgram(NewStatusView(), tea.WithAltScreen())
	_, err := p.Run()
	return err
}
