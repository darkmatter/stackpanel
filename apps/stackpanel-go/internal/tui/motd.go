// Package tui MOTD helpers: types shared with motd_data.go and a minimal
// one-line renderer. The full Lip Gloss banner was removed — Prelude's
// `motd` binary owns the shell-entry UI.
package tui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

var (
	colorKiwi = lipgloss.Color("#afd787")
)

// MOTDData is retained for compatibility with older call sites / tests.
type MOTDData struct {
	ProjectName string
	Commands    []MOTDCommand
	Features    []string
	Hints       []string
	Services    []ServiceStatus
}

// MOTDCommand represents a command to display in status / catalogue data.
type MOTDCommand struct {
	Name        string
	Description string
}

// ServiceStatus represents a service and its running state.
type ServiceStatus struct {
	Name    string
	Running bool
}

// stripAnsi removes ANSI escape codes from a string for width calculation.
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

// RenderMinimalMOTD renders a one-line status for non-interactive use.
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