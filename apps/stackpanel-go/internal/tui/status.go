package tui

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
	svc "github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
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

// StatusModel is the Bubble Tea model for the status dashboard
type StatusModel struct {
	services     []ServiceInfo
	caddyInfo    ServiceInfo
	certStatus   string
	table        table.Model
	spinner      spinner.Model
	width        int
	height       int
	loading      bool
	lastRefresh  time.Time
	refreshing   bool
	selectedView int // 0=services, 1=caddy, 2=certs
	quitting     bool
}

// Messages
type (
	servicesUpdatedMsg []ServiceInfo
	caddyUpdatedMsg    ServiceInfo
	certUpdatedMsg     string
	tickMsg            struct{}
	refreshDoneMsg     struct{}
)

// Configuration
var (
	// ServicesBaseDir is now dynamic - use svc.BaseDir instead
	// This variable is kept for backward compatibility but should be avoided
	ServicesBaseDir = filepath.Join(os.Getenv("HOME"), ".local", "share", "devservices")
	CaddyConfigDir  = filepath.Join(os.Getenv("HOME"), ".config", "caddy")
)

// GetServicesBaseDir returns the current services base directory.
// Prefer this over the ServicesBaseDir variable.
func GetServicesBaseDir() string {
	return svc.BaseDir
}

// Service definitions are now loaded dynamically from the services package

// NewStatusModel creates a new status dashboard model
func NewStatusModel() StatusModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = SpinnerStyle

	// Create table
	columns := []table.Column{
		{Title: "Service", Width: 12},
		{Title: "Status", Width: 10},
		{Title: "PID", Width: 8},
		{Title: "Port", Width: 6},
		{Title: "Details", Width: 30},
	}

	t := table.New(
		table.WithColumns(columns),
		table.WithFocused(true),
		table.WithHeight(5),
	)

	// Apply styles
	s2 := table.DefaultStyles()
	s2.Header = s2.Header.
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(ColorBorder).
		BorderBottom(true).
		Bold(false).
		Foreground(ColorSubtle)
	s2.Selected = s2.Selected.
		Foreground(lipgloss.Color("#FFFFFF")).
		Background(ColorPrimary).
		Bold(false)
	t.SetStyles(s2)

	return StatusModel{
		spinner:     s,
		table:       t,
		loading:     true,
		lastRefresh: time.Now(),
	}
}

func (m StatusModel) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		refreshServices,
		refreshCaddy,
		refreshCerts,
		tickCmd(),
	)
}

func tickCmd() tea.Cmd {
	return tea.Tick(2*time.Second, func(t time.Time) tea.Msg {
		return tickMsg{}
	})
}

func refreshServices() tea.Msg {
	var svcInfos []ServiceInfo

	for _, svc := range svc.All() {
		status := svc.Status()
		info := ServiceInfo{
			Name:        svc.Name(),
			DisplayName: svc.DisplayName(),
			Port:        svc.Port(),
			Status:      "stopped",
		}

		if status.Running {
			info.Status = "running"
			info.PID = status.PID
			// Get extended status info
			details := []string{}
			for key, val := range svc.StatusInfo() {
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

	return servicesUpdatedMsg(svcInfos)
}

func refreshCaddy() tea.Msg {
	info := ServiceInfo{
		Name:        "caddy",
		DisplayName: "Caddy",
		Status:      "stopped",
	}

	pidFile := filepath.Join(CaddyConfigDir, "caddy.pid")
	pid := readCaddyPid(pidFile)

	if pid > 0 && svc.IsProcessRunning(pid) {
		info.Status = "running"
		info.PID = pid
		info.Details = countCaddySites()
	}

	return caddyUpdatedMsg(info)
}

func refreshCerts() tea.Msg {
	stateDir := findStepStateDir()
	hostname, _ := os.Hostname()
	certFile := filepath.Join(stateDir, hostname+".crt")

	if _, err := os.Stat(certFile); os.IsNotExist(err) {
		return certUpdatedMsg("No certificate")
	}

	// Check validity
	cmd := exec.Command("step", "certificate", "inspect", certFile, "--format", "json")
	output, err := cmd.Output()
	if err != nil {
		return certUpdatedMsg("Error checking cert")
	}

	if strings.Contains(string(output), "expired") {
		return certUpdatedMsg("Expired")
	}

	return certUpdatedMsg("Valid")
}

func (m StatusModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			m.quitting = true
			return m, tea.Quit
		case "r":
			m.refreshing = true
			return m, tea.Batch(
				refreshServices,
				refreshCaddy,
				refreshCerts,
			)
		case "tab":
			m.selectedView = (m.selectedView + 1) % 3
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.table.SetWidth(msg.Width - 4)

	case servicesUpdatedMsg:
		m.services = msg
		m.loading = false
		m.refreshing = false
		m.lastRefresh = time.Now()
		m.updateTable()

	case caddyUpdatedMsg:
		m.caddyInfo = ServiceInfo(msg)

	case certUpdatedMsg:
		m.certStatus = string(msg)

	case tickMsg:
		cmds = append(cmds, tea.Batch(
			refreshServices,
			refreshCaddy,
			refreshCerts,
			tickCmd(),
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

func (m *StatusModel) updateTable() {
	var rows []table.Row
	for _, svc := range m.services {
		status := renderStatusBadge(svc.Status)
		pidStr := "-"
		if svc.PID > 0 {
			pidStr = strconv.Itoa(svc.PID)
		}
		rows = append(rows, table.Row{
			svc.DisplayName,
			status,
			pidStr,
			strconv.Itoa(svc.Port),
			svc.Details,
		})
	}
	m.table.SetRows(rows)
}

func renderStatusBadge(status string) string {
	switch status {
	case "running":
		return StatusRunning.Render(SymbolRunning + " running")
	case "stopped":
		return StatusStopped.Render(SymbolStopped + " stopped")
	case "starting":
		return StatusStarting.Render(SymbolStarting + " starting")
	case "error":
		return StatusError.Render(SymbolError + " error")
	default:
		return TextDim.Render(status)
	}
}

func (m StatusModel) View() string {
	if m.quitting {
		return ""
	}

	var b strings.Builder

	// Header
	header := lipgloss.NewStyle().
		Foreground(ColorSecondary).
		Bold(true).
		Render("╔════════════════════════════════════════════════════════════════╗\n" +
			"║  Stackpanel Development Environment                           ║\n" +
			"╚════════════════════════════════════════════════════════════════╝")
	b.WriteString(header)
	b.WriteString("\n\n")

	// Loading state
	if m.loading {
		b.WriteString(m.spinner.View())
		b.WriteString(" Loading svc...")
		return RenderFrame(b.String())
	}

	// Services section
	servicesHeader := lipgloss.NewStyle().
		Foreground(ColorWarning).
		Bold(true).
		Render("■")
	b.WriteString(servicesHeader)
	b.WriteString(" Development Services")
	if m.refreshing {
		b.WriteString(" ")
		b.WriteString(m.spinner.View())
	}
	b.WriteString("\n\n")
	b.WriteString(m.table.View())
	b.WriteString("\n")

	// Caddy section
	b.WriteString("\n")
	b.WriteString(servicesHeader)
	b.WriteString(" Reverse Proxy\n")
	caddyLine := "  "
	if m.caddyInfo.Status == "running" {
		caddyLine += StatusRunning.Render(SymbolRunning + " Caddy")
		caddyLine += TextDim.Render(fmt.Sprintf(" (PID: %d)", m.caddyInfo.PID))
		if m.caddyInfo.Details != "" {
			caddyLine += TextDim.Render(" - " + m.caddyInfo.Details)
		}
	} else {
		caddyLine += StatusStopped.Render(SymbolStopped + " Caddy (stopped)")
	}
	b.WriteString(caddyLine)
	b.WriteString("\n")

	// Certs section
	b.WriteString("\n")
	b.WriteString(servicesHeader)
	b.WriteString(" Certificates\n")
	certLine := "  "
	switch m.certStatus {
	case "Valid":
		certLine += RenderSuccess("Device certificate valid")
	case "Expired":
		certLine += RenderWarning("Device certificate expired")
	case "No certificate":
		certLine += TextDim.Render(SymbolStopped + " No device certificate")
	default:
		certLine += TextDim.Render(SymbolStopped + " " + m.certStatus)
	}
	b.WriteString(certLine)
	b.WriteString("\n")

	// Help
	help := HelpStyle.Render("\n  r: refresh • q: quit")
	b.WriteString(help)
	b.WriteString("\n")

	return RenderFrame(b.String())
}

// Helper functions for Caddy and Certs (services use the services package now)

func readCaddyPid(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	pid, _ := strconv.Atoi(strings.TrimSpace(string(data)))
	return pid
}

func countCaddySites() string {
	sitesDir := filepath.Join(CaddyConfigDir, "sites.d")
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

func findStepStateDir() string {
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

// RunStatusDashboard launches the interactive status dashboard
func RunStatusDashboard() error {
	p := tea.NewProgram(NewStatusModel(), tea.WithAltScreen())
	_, err := p.Run()
	return err
}
