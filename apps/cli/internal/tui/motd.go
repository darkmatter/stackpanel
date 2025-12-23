package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// MOTDData contains the data needed to render the MOTD
type MOTDData struct {
	ProjectName string
	Commands    []MOTDCommand
	Features    []string
	Hints       []string
}

// MOTDCommand represents a command to display
type MOTDCommand struct {
	Name        string
	Description string
}

// MOTD styles
var (
	motdBoxStyle = lipgloss.NewStyle().
			Border(lipgloss.DoubleBorder()).
			BorderForeground(ColorPrimary).
			Padding(0, 2)

	motdTitleStyle = lipgloss.NewStyle().
			Foreground(ColorPrimary).
			Bold(true)

	motdSectionStyle = lipgloss.NewStyle().
				Foreground(ColorAccent).
				Bold(true)

	motdCommandNameStyle = lipgloss.NewStyle().
				Foreground(ColorWarning)

	motdCommandDescStyle = lipgloss.NewStyle().
				Foreground(ColorDim)

	motdFeatureStyle = lipgloss.NewStyle().
				Foreground(ColorSuccess)

	motdHintStyle = lipgloss.NewStyle().
			Foreground(ColorDim)
)

// RenderMOTD renders the message of the day
func RenderMOTD(data MOTDData) string {
	var b strings.Builder

	// Header box
	title := "stackpanel Development Environment"
	if data.ProjectName != "" {
		title = fmt.Sprintf("%s Development Environment", data.ProjectName)
	}

	headerContent := motdTitleStyle.Render(title)
	header := motdBoxStyle.Render(headerContent)
	b.WriteString(header)
	b.WriteString("\n\n")

	// Commands section
	if len(data.Commands) > 0 {
		// Calculate max command name width
		maxWidth := 0
		for _, cmd := range data.Commands {
			if len(cmd.Name) > maxWidth {
				maxWidth = len(cmd.Name)
			}
		}
		// Add padding
		maxWidth += 2

		b.WriteString(motdSectionStyle.Render("📦 Commands:"))
		b.WriteString("\n")
		for _, cmd := range data.Commands {
			// Pad the name to align descriptions
			paddedName := fmt.Sprintf("%-*s", maxWidth, cmd.Name)
			name := motdCommandNameStyle.Render(paddedName)
			desc := motdCommandDescStyle.Render("# " + cmd.Description)
			b.WriteString(fmt.Sprintf("  %s %s\n", name, desc))
		}
		b.WriteString("\n")
	}

	// Features section
	if len(data.Features) > 0 {
		b.WriteString(motdSectionStyle.Render("✨ Enabled Features:"))
		b.WriteString("\n")
		for _, feature := range data.Features {
			check := motdFeatureStyle.Render(SymbolSuccess)
			b.WriteString(fmt.Sprintf("  %s %s\n", check, feature))
		}
		b.WriteString("\n")
	}

	// Hints section
	if len(data.Hints) > 0 {
		b.WriteString(motdHintStyle.Render("💡 Hints:"))
		b.WriteString("\n")
		for _, hint := range data.Hints {
			b.WriteString(fmt.Sprintf("  %s %s\n", motdHintStyle.Render(SymbolDot), motdHintStyle.Render(hint)))
		}
		b.WriteString("\n")
	}

	return b.String()
}
