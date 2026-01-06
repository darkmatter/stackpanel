package output

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"
	"github.com/darkmatter/stackpanel/apps/stackpanel-go/internal/tui"
)

// ViewerModel is a Bubble Tea model for displaying command output
// with optional markdown rendering and scrolling support.
type ViewerModel struct {
	viewport    viewport.Model
	content     string
	title       string
	ready       bool
	quitting    bool
	width       int
	height      int
	isMarkdown  bool
	showHelp    bool
	returnToMsg tea.Msg // Message to send when returning
}

// ViewerOption configures the ViewerModel
type ViewerOption func(*ViewerModel)

// WithTitle sets the title displayed above the content
func WithTitle(title string) ViewerOption {
	return func(v *ViewerModel) {
		v.title = title
	}
}

// WithMarkdown enables markdown rendering for the content
func WithMarkdown() ViewerOption {
	return func(v *ViewerModel) {
		v.isMarkdown = true
	}
}

// WithReturnMsg sets a custom message to send when the user dismisses the viewer
func WithReturnMsg(msg tea.Msg) ViewerOption {
	return func(v *ViewerModel) {
		v.returnToMsg = msg
	}
}

// WithShowHelp enables/disables the help text at the bottom
func WithShowHelp(show bool) ViewerOption {
	return func(v *ViewerModel) {
		v.showHelp = show
	}
}

// ReturnFromViewerMsg is sent when user wants to return from the viewer
type ReturnFromViewerMsg struct{}

// NewViewerModel creates a new output viewer model
func NewViewerModel(content string, opts ...ViewerOption) ViewerModel {
	m := ViewerModel{
		content:    content,
		showHelp:   true,
		isMarkdown: false,
	}

	for _, opt := range opts {
		opt(&m)
	}

	return m
}

// Init implements tea.Model
func (m ViewerModel) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model
func (m ViewerModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "esc", "enter", " ":
			m.quitting = true
			if m.returnToMsg != nil {
				return m, func() tea.Msg { return m.returnToMsg }
			}
			return m, func() tea.Msg { return ReturnFromViewerMsg{} }
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

		headerHeight := m.headerHeight()
		footerHeight := m.footerHeight()
		verticalMarginHeight := headerHeight + footerHeight

		if !m.ready {
			m.viewport = viewport.New(msg.Width, msg.Height-verticalMarginHeight)
			m.viewport.YPosition = headerHeight
			m.viewport.SetContent(m.renderContent())
			m.ready = true
		} else {
			m.viewport.Width = msg.Width
			m.viewport.Height = msg.Height - verticalMarginHeight
			m.viewport.SetContent(m.renderContent())
		}
	}

	// Handle viewport scrolling
	m.viewport, cmd = m.viewport.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

// View implements tea.Model
func (m ViewerModel) View() string {
	if m.quitting {
		return ""
	}

	if !m.ready {
		return "\n  Initializing..."
	}

	var b strings.Builder

	// Header
	b.WriteString(m.headerView())
	b.WriteString("\n")

	// Content viewport
	b.WriteString(m.viewport.View())

	// Footer
	b.WriteString("\n")
	b.WriteString(m.footerView())

	return b.String()
}

func (m ViewerModel) headerHeight() int {
	if m.title != "" {
		return 3 // title + blank line + separator
	}
	return 1
}

func (m ViewerModel) footerHeight() int {
	if m.showHelp {
		return 2 // separator + help text
	}
	return 1
}

func (m ViewerModel) headerView() string {
	if m.title == "" {
		return ""
	}

	titleStyle := lipgloss.NewStyle().
		Foreground(tui.ColorSecondary).
		Bold(true).
		Padding(0, 1)

	title := titleStyle.Render(m.title)

	line := lipgloss.NewStyle().
		Foreground(tui.ColorBorder).
		Render(strings.Repeat("─", max(0, m.width-lipgloss.Width(title))))

	return lipgloss.JoinHorizontal(lipgloss.Center, title, line)
}

func (m ViewerModel) footerView() string {
	var parts []string

	// Scroll indicator
	info := lipgloss.NewStyle().
		Foreground(tui.ColorDim).
		Render(m.scrollInfo())
	parts = append(parts, info)

	if m.showHelp {
		help := lipgloss.NewStyle().
			Foreground(tui.ColorDim).
			Render(" • ↑/↓: scroll • q/esc/enter: return")
		parts = append(parts, help)
	}

	return strings.Join(parts, "")
}

func (m ViewerModel) scrollInfo() string {
	percent := m.viewport.ScrollPercent() * 100
	return lipgloss.NewStyle().
		Foreground(tui.ColorSubtle).
		Render(strings.Repeat("─", max(0, m.width/3))) +
		lipgloss.NewStyle().
			Foreground(tui.ColorDim).
			Render(fmt.Sprintf(" %.0f%% ", percent))
}

func (m ViewerModel) renderContent() string {
	content := m.content

	if m.isMarkdown && content != "" {
		rendered, err := m.renderMarkdown(content)
		if err == nil {
			content = rendered
		}
	}

	// Apply padding
	contentStyle := lipgloss.NewStyle().
		PaddingLeft(2).
		PaddingRight(2)

	return contentStyle.Render(content)
}

func (m ViewerModel) renderMarkdown(content string) (string, error) {
	// Calculate width for glamour (accounting for padding and viewport borders)
	const glamourGutter = 2
	width := m.width - 4 - glamourGutter // 4 for padding (2 left + 2 right)
	if width < 40 {
		width = 40
	}

	renderer, err := glamour.NewTermRenderer(
		glamour.WithAutoStyle(),
		glamour.WithWordWrap(width),
	)
	if err != nil {
		return "", err
	}

	return renderer.Render(content)
}

// SetContent updates the viewer's content
func (m *ViewerModel) SetContent(content string) {
	m.content = content
	if m.ready {
		m.viewport.SetContent(m.renderContent())
		m.viewport.GotoTop()
	}
}

// SetTitle updates the viewer's title
func (m *ViewerModel) SetTitle(title string) {
	m.title = title
}

// SetMarkdown enables or disables markdown rendering
func (m *ViewerModel) SetMarkdown(enabled bool) {
	m.isMarkdown = enabled
	if m.ready {
		m.viewport.SetContent(m.renderContent())
	}
}

// Content returns the current content
func (m ViewerModel) Content() string {
	return m.content
}

// RunViewer launches the output viewer as a standalone program
func RunViewer(content string, opts ...ViewerOption) error {
	model := NewViewerModel(content, opts...)
	p := tea.NewProgram(model, tea.WithAltScreen())
	_, err := p.Run()
	return err
}

// RunViewerWithTitle is a convenience function to run a viewer with a title
func RunViewerWithTitle(title, content string) error {
	return RunViewer(content, WithTitle(title))
}

// RunMarkdownViewer runs a viewer with markdown rendering enabled
func RunMarkdownViewer(content string, opts ...ViewerOption) error {
	opts = append([]ViewerOption{WithMarkdown()}, opts...)
	return RunViewer(content, opts...)
}

// SimpleViewer provides a simpler non-scrolling view for short output
type SimpleViewer struct {
	content  string
	title    string
	quitting bool
}

// NewSimpleViewer creates a simple viewer for short content
func NewSimpleViewer(title, content string) SimpleViewer {
	return SimpleViewer{
		title:   title,
		content: content,
	}
}

// Init implements tea.Model
func (m SimpleViewer) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model
func (m SimpleViewer) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if _, ok := msg.(tea.KeyMsg); ok {
		// Any key returns from viewer
		m.quitting = true
		return m, func() tea.Msg { return ReturnFromViewerMsg{} }
	}
	return m, nil
}

// View implements tea.Model
func (m SimpleViewer) View() string {
	if m.quitting {
		return ""
	}

	var b strings.Builder

	// Title
	if m.title != "" {
		titleStyle := lipgloss.NewStyle().
			Foreground(tui.ColorSecondary).
			Bold(true)
		b.WriteString(titleStyle.Render(m.title))
		b.WriteString("\n\n")
	}

	// Content
	contentStyle := lipgloss.NewStyle().
		PaddingLeft(2)
	b.WriteString(contentStyle.Render(m.content))
	b.WriteString("\n")

	// Help
	help := lipgloss.NewStyle().
		Foreground(tui.ColorDim).
		MarginTop(1).
		Render("\nPress any key to return...")
	b.WriteString(help)

	return b.String()
}

// RunSimpleViewer runs a simple viewer for short content
func RunSimpleViewer(title, content string) error {
	p := tea.NewProgram(NewSimpleViewer(title, content))
	_, err := p.Run()
	return err
}
