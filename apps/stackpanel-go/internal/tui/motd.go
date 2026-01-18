package tui

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/reflow/wordwrap"
)

// ASCII banner for stackpanel
const motdBanner = `        |                 |                                |
   __|  __|   _' |   __|  |  /  __ \    _' |  __ \    _ \  |
 \__ \  |    (   |  (       <   |   |  (   |  |   |   __/  |
 ____/ \__| \__,_| \___| _|\_\  .__/  \__,_| _|  _| \___| _|
                               _|`

// MOTD color palette (adapted from gum-style bash script)
var (
	// Accent colors
	colorPink = lipgloss.Color("212")
	colorKiwi = lipgloss.Color("156")
	colorRed  = lipgloss.Color("197")
	colorBlue = lipgloss.Color("99")

	// Text colors
	colorPrimary = lipgloss.Color("7")
	colorBright  = lipgloss.Color("15")
	colorFaint   = lipgloss.Color("103")
	colorDark    = lipgloss.Color("238")
	colorBorder  = lipgloss.Color("240")
)

// MOTDData contains the data needed to render the MOTD
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

const motdWidth = 68

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
				Padding(1, 4).
				Width(motdWidth + 8)

	// Title styles
	motdTitleStyle = lipgloss.NewStyle().
			Foreground(colorPink).
			Bold(true)

	motdSubtitleStyle = lipgloss.NewStyle().
				Foreground(colorFaint)

	// Section header styles
	motdSectionStyle = lipgloss.NewStyle().
				Foreground(colorPink)

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

	motdServiceNameStyle = lipgloss.NewStyle().
				Foreground(colorDark)

	// Hint styles
	motdHintStyle = lipgloss.NewStyle().
			Foreground(colorDark)

	motdFeatureStyle = lipgloss.NewStyle().
				Foreground(colorKiwi)
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

// renderStatusIndicator renders a status dot for a service
func renderStatusIndicator(name string, running bool) string {
	var dot string
	if running {
		dot = motdStatusRunning.Render("●")
	} else {
		dot = motdStatusStopped.Render("●")
	}
	svcName := motdServiceNameStyle.Render(name)
	return fmt.Sprintf("%s %s", svcName, dot)
}

// renderCommandRow renders a command row with aligned columns
func renderCommandRow(label string, cmd string, labelWidth int) string {
	paddedLabel := fmt.Sprintf("%-*s", labelWidth, label)
	styledLabel := motdLabelStyle.Render(paddedLabel)
	styledCmd := motdCommandStyle.Render(cmd)
	return fmt.Sprintf("%s  %s", styledLabel, styledCmd)
}

// wrapText wraps text to fit within the MOTD width
func wrapText(text string, indent int) string {
	wrapped := wordwrap.String(text, motdWidth-indent)
	lines := strings.Split(wrapped, "\n")
	indentStr := strings.Repeat(" ", indent)
	for i := 1; i < len(lines); i++ {
		lines[i] = indentStr + lines[i]
	}
	return strings.Join(lines, "\n")
}

// renderBanner renders the styled ASCII banner
func renderBanner() string {
	lines := strings.Split(motdBanner, "\n")

	// Find the widest line to use for consistent centering
	maxWidth := 0
	var nonEmptyLines []string
	for _, line := range lines {
		if line == "" {
			continue
		}
		nonEmptyLines = append(nonEmptyLines, line)
		if len(line) > maxWidth {
			maxWidth = len(line)
		}
	}

	// Calculate left padding to center the entire block
	containerWidth := motdWidth + 8
	blockPadding := (containerWidth - maxWidth) / 2
	if blockPadding < 0 {
		blockPadding = 0
	}

	// Apply consistent padding to all lines
	var styledLines []string
	for _, line := range nonEmptyLines {
		paddedLine := strings.Repeat(" ", blockPadding) + line
		styledLines = append(styledLines, motdBannerStyle.Render(paddedLine))
	}

	return strings.Join(styledLines, "\n")
}

// RenderMOTD renders the message of the day with beautiful styling
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
			Width(motdWidth).
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
	content.WriteString(renderCommandRow("Start Services", "dev", labelWidth))
	content.WriteString("\n")
	content.WriteString(renderCommandRow("Stop Services", "dev stop", labelWidth))
	content.WriteString("\n")
	content.WriteString(renderCommandRow("Run Checks", "turbo check", labelWidth))
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
