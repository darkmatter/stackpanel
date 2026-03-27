// Package tui provides the terminal user interface for the stackpanel CLI.
// It contains Bubble Tea models, lipgloss styles, and shared rendering utilities
// used across the interactive TUI (status dashboard, service management, MOTD, etc.).
package tui

import (
	"github.com/charmbracelet/lipgloss"
)

// Theme colors — shared palette used by all TUI components.
// These intentionally use 8-character hex (with alpha) for some colors
// to work with lipgloss's extended color support.
var (
	// Primary colors
	ColorPrimary   = lipgloss.Color("#875fff") // Purple
	ColorSecondary = lipgloss.Color("#87ffd7") // Cyan
	ColorAccent    = lipgloss.Color("#ff87d7") // Amber

	// Status colors
	ColorSuccess = lipgloss.Color("#afff87")   // Green
	ColorWarning = lipgloss.Color("#ffc823ff") // Amber
	ColorError   = lipgloss.Color("#ff5f5f")   // Red
	ColorInfo    = lipgloss.Color("#6394e3ff") // Blue

	// Neutral colors
	ColorWhite   = lipgloss.Color("#DDDDDD") // White
	ColorDim     = lipgloss.Color("#6B7280") // Gray
	ColorSubtle  = lipgloss.Color("#9CA3AF") // Light gray
	ColorMuted   = lipgloss.Color("#4B5563") // Dark gray
	ColorBorder  = lipgloss.Color("#374151") // Border gray
	ColorSurface = lipgloss.Color("#1F2937") // Surface gray
)

// Base text styles
var (
	TextNormal = lipgloss.NewStyle()
	TextBold   = lipgloss.NewStyle().Bold(true)
	TextDim    = lipgloss.NewStyle().Foreground(ColorDim)
	TextSubtle = lipgloss.NewStyle().Foreground(ColorSubtle)
	TextMuted  = lipgloss.NewStyle().Foreground(ColorMuted)
)

// Status indicators
var (
	StatusRunning = lipgloss.NewStyle().
			Foreground(ColorSuccess).
			Bold(true)

	StatusStopped = lipgloss.NewStyle().
			Foreground(ColorDim)

	StatusStarting = lipgloss.NewStyle().
			Foreground(ColorWarning)

	StatusError = lipgloss.NewStyle().
			Foreground(ColorError).
			Bold(true)
)

// Headers and titles
var (
	TitleStyle = lipgloss.NewStyle().
			Foreground(ColorSecondary).
			Bold(true).
			MarginBottom(1)

	SubtitleStyle = lipgloss.NewStyle().
			Foreground(ColorSubtle).
			Italic(true)

	HeaderStyle = lipgloss.NewStyle().
			Foreground(ColorPrimary).
			Bold(true).
			Padding(0, 1).
			Background(lipgloss.Color("#1F2937"))
)

// Box styles for panels
var (
	BoxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorBorder).
			Padding(1, 2)

	BoxActiveStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorPrimary).
			Padding(1, 2)

	BoxSuccessStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorSuccess).
			Padding(1, 2)

	BoxErrorStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorError).
			Padding(1, 2)
)

// Status symbols
const (
	SymbolRunning  = "●"
	SymbolStopped  = "○"
	SymbolStarting = "◐"
	SymbolError    = "✗"
	SymbolSuccess  = "✓"
	SymbolWarning  = "⚠"
	SymbolInfo     = "→"
	SymbolArrow    = "▸"
	SymbolDot      = "•"
)

// Render helpers prepend a status symbol and apply the matching color.
// Use these instead of manually combining symbols + styles for consistency.
func RenderRunning(text string) string {
	return StatusRunning.Render(SymbolRunning + " " + text)
}

func RenderStopped(text string) string {
	return StatusStopped.Render(SymbolStopped + " " + text)
}

func RenderStarting(text string) string {
	return StatusStarting.Render(SymbolStarting + " " + text)
}

func RenderSuccess(text string) string {
	return lipgloss.NewStyle().Foreground(ColorSuccess).Render(SymbolSuccess + " " + text)
}

func RenderError(text string) string {
	return lipgloss.NewStyle().Foreground(ColorError).Render(SymbolError + " " + text)
}

func RenderWarning(text string) string {
	return lipgloss.NewStyle().Foreground(ColorWarning).Render(SymbolWarning + " " + text)
}

func RenderInfo(text string) string {
	return lipgloss.NewStyle().Foreground(ColorInfo).Render(SymbolInfo + " " + text)
}

func RenderDim(text string) string {
	return TextDim.Render(text)
}

// Table styles
var (
	TableHeaderStyle = lipgloss.NewStyle().
				Foreground(ColorSubtle).
				Bold(true).
				Padding(0, 1)

	TableCellStyle = lipgloss.NewStyle().
			Padding(0, 1)

	TableSelectedStyle = lipgloss.NewStyle().
				Background(ColorPrimary).
				Foreground(lipgloss.Color("#FFFFFF")).
				Padding(0, 1)
)

// Help text style
var HelpStyle = lipgloss.NewStyle().
	Foreground(ColorDim).
	MarginTop(1)

// Spinner style
var SpinnerStyle = lipgloss.NewStyle().
	Foreground(ColorPrimary)

// Progress bar colors
var (
	ProgressFilled = ColorSuccess
	ProgressEmpty  = ColorMuted
)

var FrameStyle = lipgloss.NewStyle().
	Border(lipgloss.RoundedBorder()).
	BorderForeground(ColorPrimary).
	Padding(1, 2).
	Margin(1, 2)

func RenderFrame(content string) string {
	return FrameStyle.Render(content)
}

// Banner is the ASCII art displayed at the top of the TUI and MOTD.
// Generated from "stackpanel" in a figlet-style font.
const Banner = `
       |                 |                                |
  __|  __|   _' |   __|  |  /  __ \    _' |  __ \    _ \  |
\__ \  |    (   |  (       <   |   |  (   |  |   |   __/  |
____/ \__| \__,_| \___| _|\_\  .__/  \__,_| _|  _| \___| _|
                              _|
`
