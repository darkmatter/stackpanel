package tui

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/reflow/wordwrap"
)

// ASCII banner for stackpanel
const motdBanner = `
        |                 |                                |
   __|  __|   _' |   __|  |  /  __ \    _' |  __ \    _ \  |
 \__ \  |    (   |  (       <   |   |  (   |  |   |   __/  |
 ____/ \__| \__,_| \___| _|\_\  .__/  \__,_| _|  _| \___| _|
                               _|`

// MOTD color palette
var (
	// Accent colors
	colorPink   = lipgloss.Color("#ff87d7")
	colorKiwi   = lipgloss.Color("#afd787")
	colorRed    = lipgloss.Color("#ff607f")
	colorBlue   = lipgloss.Color("#875fff")
	colorYellow = lipgloss.Color("#ffd75f")
	colorOrange = lipgloss.Color("#ffaf00")
	colorCyan   = lipgloss.Color("#5fffff")

	// Text colors
	colorPrimary = lipgloss.Color("#c0c0c0")
	colorBright  = lipgloss.Color("#ffffff")
	colorFaint   = lipgloss.Color("#999999")
	colorDark    = lipgloss.Color("#444444")
	colorBorder  = lipgloss.Color("#454545")
)

// MOTDData contains the data needed to render the MOTD (legacy struct for backward compatibility)
type MOTDData struct {
	ProjectName string
	Commands    []MOTDCommand
	Features    []string
	Hints       []string
	Services    []ServiceStatus
}

// MOTDCommand represents a command to display
type MOTDCommand struct {
	Name        string
	Description string
}

// ServiceStatus represents a service and its running state
type ServiceStatus struct {
	Name    string
	Running bool
}

const motdWidth = 72

// MOTD styles
var (
	// Banner style
	motdBannerStyle = lipgloss.NewStyle().
			Foreground(colorPink).
			Bold(true)

	// Container styles
	motdContainerStyle = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(colorBorder).
				Padding(1, 2).
				Width(motdWidth)

	// Section divider
	motdDividerStyle = lipgloss.NewStyle().
				Foreground(colorBorder)

	// Title styles
	motdTitleStyle = lipgloss.NewStyle().
			Foreground(colorPink).
			Bold(true)

	motdSubtitleStyle = lipgloss.NewStyle().
				Foreground(colorFaint)

	motdVersionStyle = lipgloss.NewStyle().
				Foreground(colorFaint).
				Italic(true)

	// Section header styles
	motdSectionStyle = lipgloss.NewStyle().
				Foreground(colorPink).
				Bold(true)

	// Command styles
	motdLabelStyle = lipgloss.NewStyle().
			Foreground(colorFaint)

	motdCommandStyle = lipgloss.NewStyle().
				Foreground(colorKiwi)

	motdTextStyle = lipgloss.NewStyle().
			Foreground(colorPrimary)

	// Status indicator styles
	motdStatusRunning = lipgloss.NewStyle().
				Foreground(colorKiwi)

	motdStatusStopped = lipgloss.NewStyle().
				Foreground(colorRed)

	motdStatusWarning = lipgloss.NewStyle().
				Foreground(colorYellow)

	motdServiceNameStyle = lipgloss.NewStyle().
				Foreground(colorFaint)

	// Issue styles
	motdIssueErrorStyle = lipgloss.NewStyle().
				Foreground(colorRed)

	motdIssueWarningStyle = lipgloss.NewStyle().
				Foreground(colorYellow)

	motdIssueInfoStyle = lipgloss.NewStyle().
				Foreground(colorBlue)

	// Link styles
	motdLinkStyle = lipgloss.NewStyle().
			Foreground(colorCyan).
			Underline(true)

	motdLinkLabelStyle = lipgloss.NewStyle().
				Foreground(colorFaint)

	// Hint styles
	motdHintStyle = lipgloss.NewStyle().
			Foreground(colorDark)

	motdFeatureStyle = lipgloss.NewStyle().
				Foreground(colorKiwi)

	// Environment styles
	motdEnvStyle = lipgloss.NewStyle().
			Foreground(colorFaint)

	motdEnvVersionStyle = lipgloss.NewStyle().
				Foreground(colorPrimary)

	// Update notification style
	motdUpdateStyle = lipgloss.NewStyle().
			Foreground(colorOrange).
			Bold(true)
)

// checkDockerService checks if a docker compose service is running
func checkDockerService(service string) bool {
	cmd := exec.Command("docker", "compose", "ps", "--format", "{{.State}}", "--filter", fmt.Sprintf("name=%s", service))
	output, err := cmd.Output()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(output)), "running")
}

// renderStatusDot renders a colored status dot
func renderStatusDot(running bool) string {
	if running {
		return motdStatusRunning.Render("●")
	}
	return motdStatusStopped.Render("○")
}

// renderWarningDot renders a warning status dot
func renderWarningDot() string {
	return motdStatusWarning.Render("⚠")
}

// renderStatusIndicator renders a status dot for a service
func renderStatusIndicator(name string, running bool) string {
	dot := renderStatusDot(running)
	svcName := motdServiceNameStyle.Render(name)
	return fmt.Sprintf("%s %s", dot, svcName)
}

// renderCommandRow renders a command row with aligned columns
func renderCommandRow(label string, cmd string, labelWidth int) string {
	paddedLabel := fmt.Sprintf("%-*s", labelWidth, label)
	styledLabel := motdCommandStyle.Render(paddedLabel)
	styledCmd := motdLabelStyle.Render(cmd)
	return fmt.Sprintf("  %s  %s", styledLabel, styledCmd)
}

// renderShortcutRow renders a shortcut explanation row
func renderShortcutRow(shortcut, explanation string) string {
	sc := motdCommandStyle.Render(shortcut)
	eq := motdLabelStyle.Render("=")
	exp := motdLabelStyle.Render(explanation)
	return fmt.Sprintf("  %s %s %s", sc, eq, exp)
}

// formatDuration formats a duration in a human-readable way
func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds", int(d.Seconds()))
	}
	if d < time.Hour {
		return fmt.Sprintf("%dm", int(d.Minutes()))
	}
	if d < 24*time.Hour {
		hours := int(d.Hours())
		mins := int(d.Minutes()) % 60
		if mins > 0 {
			return fmt.Sprintf("%dh%dm", hours, mins)
		}
		return fmt.Sprintf("%dh", hours)
	}
	days := int(d.Hours() / 24)
	return fmt.Sprintf("%dd", days)
}

// wrapText wraps text to fit within the MOTD width
func wrapText(text string, indent int) string {
	wrapped := wordwrap.String(text, motdWidth-indent-4)
	lines := strings.Split(wrapped, "\n")
	indentStr := strings.Repeat(" ", indent)
	for i := 1; i < len(lines); i++ {
		lines[i] = indentStr + lines[i]
	}
	return strings.Join(lines, "\n")
}

// renderDivider renders a horizontal divider line
func renderDivider() string {
	return motdDividerStyle.Render(strings.Repeat("─", motdWidth-4))
}

// renderBanner renders the styled ASCII banner
func renderBanner() string {
	lines := strings.Split(motdBanner, "\n")

	// Filter empty lines
	var nonEmptyLines []string
	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		nonEmptyLines = append(nonEmptyLines, line)
	}

	// Calculate centering padding based on container width
	// The banner is already formatted with internal spacing, so we just need to center it
	maxWidth := 0
	for _, line := range nonEmptyLines {
		if len(line) > maxWidth {
			maxWidth = len(line)
		}
	}

	containerWidth := motdWidth - 4 // Account for box padding
	blockPadding := (containerWidth - maxWidth) / 2
	if blockPadding < 0 {
		blockPadding = 0
	}

	// Apply consistent padding and styling to each line
	var styledLines []string
	paddingStr := strings.Repeat(" ", blockPadding)
	for _, line := range nonEmptyLines {
		// Use a visible style wrapper to preserve leading whitespace
		styledLine := motdBannerStyle.Render(paddingStr + line)
		styledLines = append(styledLines, styledLine)
	}

	return strings.Join(styledLines, "\n")
}

// renderHealthBar renders a visual health bar
func renderHealthBar(passing, total int) string {
	if total == 0 {
		return ""
	}

	barWidth := 10
	filled := (passing * barWidth) / total
	if passing > 0 && filled == 0 {
		filled = 1 // At least 1 block if any passing
	}

	bar := strings.Repeat("█", filled) + strings.Repeat("░", barWidth-filled)

	var barStyle lipgloss.Style
	ratio := float64(passing) / float64(total)
	switch {
	case ratio >= 0.8:
		barStyle = motdStatusRunning
	case ratio >= 0.5:
		barStyle = motdStatusWarning
	default:
		barStyle = motdStatusStopped
	}

	return barStyle.Render(bar) + motdLabelStyle.Render(fmt.Sprintf(" %d/%d", passing, total))
}

// RenderImprovedMOTD renders the improved MOTD with all status sections
func RenderImprovedMOTD(data *MOTDFullData) string {
	var result strings.Builder
	var content strings.Builder

	// Banner (outside the box, with leading newline for spacing)
	result.WriteString(renderBanner())
	result.WriteString("\n\n")

	// Title block with version
	projectTitle := "Dev Shell"
	if data.ProjectName != "" {
		projectTitle = data.ProjectName + " Shell"
	}
	titleLine := motdTitleStyle.Render(projectTitle)
	if data.Version != "" && data.Version != "dev" {
		titleLine += "  " + motdVersionStyle.Render("v"+data.Version)
	}
	content.WriteString(titleLine)
	content.WriteString("\n")
	content.WriteString(motdSubtitleStyle.Render("Your reproducible development environment is ready"))
	content.WriteString("\n\n")

	// Status Section
	content.WriteString(renderDivider())
	content.WriteString("\n")
	content.WriteString(motdSectionStyle.Render("Status"))
	content.WriteString("\n")

	// Agent status row
	if data.Agent.Running {
		content.WriteString("  ")
		content.WriteString(motdLabelStyle.Render("Agent     "))
		content.WriteString(motdStatusRunning.Render("●"))
		content.WriteString(" ")
		content.WriteString(motdEnvVersionStyle.Render(data.Agent.URL))
		content.WriteString("\n")
	} else {
		content.WriteString("  ")
		content.WriteString(motdLabelStyle.Render("Agent     "))
		content.WriteString(motdStatusStopped.Render("○"))
		content.WriteString(" ")
		content.WriteString(motdLabelStyle.Render("not running"))
		content.WriteString("\n")
	}

	// Services status row
	if len(data.Services) > 0 {
		content.WriteString("  ")
		content.WriteString(motdLabelStyle.Render("Services  "))
		var svcParts []string
		for _, svc := range data.Services {
			svcParts = append(svcParts, renderStatusIndicator(svc.Name, svc.Running))
		}
		content.WriteString(strings.Join(svcParts, "  "))
		content.WriteString("\n")
	}

	// AWS status row
	if data.AWS.Enabled {
		content.WriteString("  ")
		content.WriteString(motdLabelStyle.Render("AWS       "))
		if data.AWS.Valid {
			content.WriteString(motdStatusRunning.Render("●"))
			content.WriteString(" ")
			content.WriteString(motdEnvVersionStyle.Render(data.AWS.Message))
			if data.AWS.AccountID != "" {
				content.WriteString(motdLabelStyle.Render(" (" + data.AWS.AccountID + ")"))
			}
		} else {
			content.WriteString(renderWarningDot())
			content.WriteString(" ")
			content.WriteString(motdStatusWarning.Render(data.AWS.Message))
		}
		content.WriteString("\n")
	}

	// Health status row
	if data.Health.Enabled && data.Health.TotalChecks > 0 {
		content.WriteString("  ")
		content.WriteString(motdLabelStyle.Render("Health    "))
		content.WriteString(renderHealthBar(data.Health.PassingCount, data.Health.TotalChecks))
		content.WriteString("\n")
	}

	// Files status row
	if data.Files.Enabled && data.Files.TotalCount > 0 {
		content.WriteString("  ")
		content.WriteString(motdLabelStyle.Render("Files     "))
		if data.Files.StaleCount > 0 {
			content.WriteString(renderWarningDot())
			content.WriteString(" ")
			content.WriteString(motdStatusWarning.Render(fmt.Sprintf("%d stale", data.Files.StaleCount)))
			content.WriteString(motdLabelStyle.Render(fmt.Sprintf(" / %d total", data.Files.TotalCount)))
		} else {
			content.WriteString(motdStatusRunning.Render("●"))
			content.WriteString(" ")
			content.WriteString(motdEnvVersionStyle.Render(fmt.Sprintf("%d synced", data.Files.TotalCount)))
		}
		content.WriteString("\n")
	}

	// Shell freshness status row
	if data.ShellFreshness.Checked {
		content.WriteString("  ")
		content.WriteString(motdLabelStyle.Render("Shell     "))
		if data.ShellFreshness.Fresh {
			content.WriteString(motdStatusRunning.Render("●"))
			content.WriteString(" ")
			content.WriteString(motdEnvVersionStyle.Render("fresh"))
			if data.ShellFreshness.ShellAge > 0 {
				ageStr := formatDuration(data.ShellFreshness.ShellAge)
				content.WriteString(motdLabelStyle.Render(" (" + ageStr + " ago)"))
			}
		} else {
			content.WriteString(renderWarningDot())
			content.WriteString(" ")
			content.WriteString(motdStatusWarning.Render("stale"))
			content.WriteString(motdLabelStyle.Render(" (config changed, reload shell)"))
		}
		content.WriteString("\n")
	}

	// Studio link (under status section)
	if data.Agent.Running && data.StudioURL != "" {
		content.WriteString("  ")
		content.WriteString(motdLabelStyle.Render("Studio    "))
		content.WriteString(motdLinkStyle.Render(data.StudioURL))
		content.WriteString("\n")
	}

	// Environment Section
	if len(data.Environment.Languages) > 0 || len(data.Environment.Tools) > 0 {
		content.WriteString("\n")
		content.WriteString(motdSectionStyle.Render("Environment"))
		content.WriteString("\n")

		// Build environment parts
		var envParts []string
		for _, lang := range data.Environment.Languages {
			part := motdEnvStyle.Render(lang.Name) + " " + motdEnvVersionStyle.Render(lang.Version)
			envParts = append(envParts, part)
		}
		for _, tool := range data.Environment.Tools {
			part := motdEnvStyle.Render(tool.Name) + " " + motdEnvVersionStyle.Render(tool.Version)
			envParts = append(envParts, part)
		}

		// Render on multiple lines if needed, max ~4 items per line
		bullet := motdLabelStyle.Render("  •  ")
		itemsPerLine := 4
		for i := 0; i < len(envParts); i += itemsPerLine {
			end := i + itemsPerLine
			if end > len(envParts) {
				end = len(envParts)
			}
			lineItems := envParts[i:end]
			content.WriteString("  " + strings.Join(lineItems, bullet))
			content.WriteString("\n")
		}
	}

	// Quick Start + Shortcuts Section
	content.WriteString("\n")
	content.WriteString(renderDivider())
	content.WriteString("\n")

	// Quick Start section
	content.WriteString(motdSectionStyle.Render("Quick Start"))
	content.WriteString("\n")
	for _, cmd := range data.DefaultCommands {
		content.WriteString(renderCommandRow(cmd.Name, cmd.Description, 14))
		content.WriteString("\n")
	}

	// Shortcuts section
	content.WriteString("\n")
	content.WriteString(motdSectionStyle.Render("Shortcuts"))
	content.WriteString("\n")
	content.WriteString(renderShortcutRow("sp ", "stackpanel"))
	content.WriteString("\n")
	content.WriteString(renderShortcutRow("spx", "run devshell commands"))
	content.WriteString("\n")
	if data.ShortcutAlias != "" && data.ShortcutAlias != "spx" {
		content.WriteString(renderShortcutRow(data.ShortcutAlias+"  ", "same as spx"))
		content.WriteString("\n")
	}

	// User Commands Section
	if len(data.UserCommands) > 0 {
		content.WriteString("\n")
		cmdHeader := motdSectionStyle.Render("Your Commands")
		if data.TotalCommands > len(data.UserCommands) {
			cmdHeader += motdLabelStyle.Render(fmt.Sprintf(" (%d available)", data.TotalCommands))
		}
		content.WriteString(cmdHeader)
		content.WriteString("\n")

		for _, cmd := range data.UserCommands {
			if cmd.Description != "" {
				content.WriteString(renderCommandRow(cmd.Name, cmd.Description, 16))
			} else {
				content.WriteString("  " + motdCommandStyle.Render(cmd.Name))
			}
			content.WriteString("\n")
		}

		if data.TotalCommands > len(data.UserCommands) {
			content.WriteString(motdLabelStyle.Render("  ...run ") +
				motdCommandStyle.Render("sp commands") +
				motdLabelStyle.Render(" for full list"))
			content.WriteString("\n")
		}
	}

	// Issues Section (conditional)
	if len(data.Issues) > 0 {
		content.WriteString("\n")
		content.WriteString(renderDivider())
		content.WriteString("\n")
		content.WriteString(motdIssueWarningStyle.Render("⚠ Action Required"))
		content.WriteString("\n")

		for _, issue := range data.Issues {
			var icon string
			var msgStyle lipgloss.Style
			switch issue.Severity {
			case "error":
				icon = motdIssueErrorStyle.Render("✗")
				msgStyle = motdIssueErrorStyle
			case "warning":
				icon = motdIssueWarningStyle.Render("!")
				msgStyle = motdIssueWarningStyle
			default:
				icon = motdIssueInfoStyle.Render("•")
				msgStyle = motdIssueInfoStyle
			}

			line := fmt.Sprintf("  %s %s", icon, msgStyle.Render(issue.Message))
			if issue.FixCommand != "" {
				line += motdLabelStyle.Render(" → ") + motdCommandStyle.Render(issue.FixCommand)
			}
			content.WriteString(line)
			content.WriteString("\n")
		}
	}

	// Update notification (conditional)
	if data.UpdateAvailable != nil {
		content.WriteString("\n")
		content.WriteString(motdUpdateStyle.Render("💡 Update available: "))
		content.WriteString(motdEnvVersionStyle.Render("v" + data.UpdateAvailable.LatestVersion))
		content.WriteString(motdLabelStyle.Render(" (you have v" + data.UpdateAvailable.CurrentVersion + ")"))
		content.WriteString(motdLabelStyle.Render(" → "))
		content.WriteString(motdCommandStyle.Render(data.UpdateAvailable.UpdateCommand))
		content.WriteString("\n")
	}

	// Resources Section
	content.WriteString("\n")
	content.WriteString(renderDivider())
	content.WriteString("\n")
	content.WriteString(motdSectionStyle.Render("Resources"))
	content.WriteString("\n")

	content.WriteString("  ")
	content.WriteString(motdLinkLabelStyle.Render("Docs      "))
	content.WriteString(motdLinkStyle.Render(data.DocsURL))
	content.WriteString("\n")

	// Wrap content in the container
	innerContent := strings.TrimRight(content.String(), "\n")
	result.WriteString(motdContainerStyle.Render(innerContent))
	result.WriteString("\n")

	return result.String()
}

// stripAnsi removes ANSI escape codes from a string (for width calculation)
func stripAnsi(s string) string {
	var result strings.Builder
	inEscape := false
	for _, r := range s {
		if r == '\x1b' {
			inEscape = true
			continue
		}
		if inEscape {
			if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') {
				inEscape = false
			}
			continue
		}
		result.WriteRune(r)
	}
	return result.String()
}

// RenderMOTD renders the message of the day with beautiful styling (legacy function)
func RenderMOTD(data MOTDData) string {
	var result strings.Builder
	var content strings.Builder

	// Render banner first
	result.WriteString("\n")
	result.WriteString(renderBanner())
	result.WriteString("\n")

	// Service status indicators (top right aligned)
	if len(data.Services) > 0 {
		var statusParts []string
		for _, svc := range data.Services {
			statusParts = append(statusParts, renderStatusIndicator(svc.Name, svc.Running))
		}
		statusLine := strings.Join(statusParts, "  ")
		rightAligned := lipgloss.NewStyle().
			Width(motdWidth - 4).
			Align(lipgloss.Right).
			Render(statusLine)
		content.WriteString(rightAligned)
		content.WriteString("\n\n")
	}

	// Title block
	projectTitle := "Dev Shell Activated"
	if data.ProjectName != "" {
		projectTitle = fmt.Sprintf("%s Shell", data.ProjectName)
	}
	content.WriteString(motdTitleStyle.Render(projectTitle))
	content.WriteString("\n")
	content.WriteString(motdSubtitleStyle.Render("Your environment is ready"))
	content.WriteString("\n\n")

	// Intro text with proper wrapping
	introText := "This project uses " +
		lipgloss.NewStyle().Foreground(colorBlue).Bold(true).Render("nix") +
		" to provide a reproducible dev environment."
	content.WriteString(motdTextStyle.Render(introText))
	content.WriteString("\n\n")

	// Getting Started section
	content.WriteString(motdSectionStyle.Render("Getting Started"))
	content.WriteString("\n\n")

	// Calculate max label width for alignment
	labelWidth := 20

	// Default commands
	content.WriteString(renderCommandRow("dev", "Start Services", labelWidth))
	content.WriteString("\n")
	content.WriteString(renderCommandRow("dev stop", "Stop Services", labelWidth))
	content.WriteString("\n")
	content.WriteString(renderCommandRow("turbo check", "Run Checks", labelWidth))
	content.WriteString("\n")

	// User-defined commands (if any with descriptions)
	hasUserCmds := false
	for _, cmd := range data.Commands {
		if cmd.Description != "" {
			if !hasUserCmds {
				content.WriteString("\n")
				hasUserCmds = true
			}
			content.WriteString(renderCommandRow(cmd.Name, cmd.Description, labelWidth))
			content.WriteString("\n")
		}
	}

	// Features section
	if len(data.Features) > 0 {
		content.WriteString("\n")
		content.WriteString(motdSectionStyle.Render("Features"))
		content.WriteString("\n\n")
		for _, feature := range data.Features {
			check := motdFeatureStyle.Render("✓")
			text := motdTextStyle.Render(feature)
			content.WriteString(fmt.Sprintf("  %s %s\n", check, text))
		}
	}

	// Hints section
	if len(data.Hints) > 0 {
		content.WriteString("\n")
		content.WriteString(motdHintStyle.Render("Hints"))
		content.WriteString("\n\n")
		for _, hint := range data.Hints {
			bullet := motdHintStyle.Render("•")
			wrappedHint := wrapText(hint, 4)
			content.WriteString(fmt.Sprintf("  %s %s\n", bullet, motdHintStyle.Render(wrappedHint)))
		}
	}

	// Wrap content in the container
	innerContent := strings.TrimRight(content.String(), "\n")
	result.WriteString(motdContainerStyle.Render(innerContent))
	result.WriteString("\n")

	return result.String()
}

// RenderMOTDWithServices renders MOTD and auto-detects docker service status
func RenderMOTDWithServices(data MOTDData, serviceNames []string) string {
	// Auto-detect service status if services are provided
	if len(serviceNames) > 0 && len(data.Services) == 0 {
		for _, name := range serviceNames {
			data.Services = append(data.Services, ServiceStatus{
				Name:    name,
				Running: checkDockerService(name),
			})
		}
	}
	return RenderMOTD(data)
}

// RenderMinimalMOTD renders a minimal one-line MOTD
func RenderMinimalMOTD(projectName string) string {
	title := "Dev Shell"
	if projectName != "" {
		title = projectName
	}
	styled := lipgloss.NewStyle().
		Foreground(colorKiwi).
		Bold(true).
		Render("✓ " + title + " ready")
	return styled + "\n"
}
