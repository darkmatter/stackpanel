package navigation

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

// MenuStyle defines the styling for menu rendering
type MenuStyle struct {
	// Style for selected item cursor
	CursorStyle lipgloss.Style
	// Style for selected item text
	SelectedStyle lipgloss.Style
	// Style for unselected item text
	ItemStyle lipgloss.Style
	// Style for item description
	DescriptionStyle lipgloss.Style
	// Style for the container
	ContainerStyle lipgloss.Style
	// Cursor character (default: ">")
	Cursor string
	// Spacing between cursor and item name
	CursorSpacing int
	// Spacing between item name and description
	DescriptionSpacing int
	// Show descriptions
	ShowDescriptions bool
}

// DefaultMenuStyle returns the default menu styling
func DefaultMenuStyle() MenuStyle {
	return MenuStyle{
		CursorStyle:        lipgloss.NewStyle().Foreground(tui.ColorPrimary).Bold(true),
		SelectedStyle:      lipgloss.NewStyle().Foreground(tui.ColorWhite).Bold(true),
		ItemStyle:          lipgloss.NewStyle().Foreground(tui.ColorSubtle),
		DescriptionStyle:   lipgloss.NewStyle().Foreground(tui.ColorDim),
		ContainerStyle:     lipgloss.NewStyle().PaddingLeft(2),
		Cursor:             tui.SymbolArrow,
		CursorSpacing:      1,
		DescriptionSpacing: 2,
		ShowDescriptions:   true,
	}
}

// MenuItem represents an item in the menu
type MenuItem struct {
	Name        string
	Description string
	Node        *CommandNode
}

// Menu represents a navigable, single-select list of command items.
// It's a stateless renderer — navigation state (SelectedIdx) is mutated
// externally by the NavigationModel's key handler.
type Menu struct {
	Items       []MenuItem
	SelectedIdx int
	Style       MenuStyle
	Width       int
	Height      int
}

// NewMenu creates a new menu from command node children
func NewMenu(node *CommandNode) *Menu {
	var items []MenuItem
	if node != nil {
		for _, child := range node.Children {
			items = append(items, MenuItem{
				Name:        child.Name,
				Description: child.Description,
				Node:        child,
			})
		}
	}

	return &Menu{
		Items:       items,
		SelectedIdx: 0,
		Style:       DefaultMenuStyle(),
	}
}

// NewMenuWithStyle creates a new menu with custom styling
func NewMenuWithStyle(node *CommandNode, style MenuStyle) *Menu {
	menu := NewMenu(node)
	menu.Style = style
	return menu
}

// MoveUp moves selection up one item
func (m *Menu) MoveUp() {
	if m.SelectedIdx > 0 {
		m.SelectedIdx--
	}
}

// MoveDown moves selection down one item
func (m *Menu) MoveDown() {
	if m.SelectedIdx < len(m.Items)-1 {
		m.SelectedIdx++
	}
}

// MoveToTop moves selection to the first item
func (m *Menu) MoveToTop() {
	m.SelectedIdx = 0
}

// MoveToBottom moves selection to the last item
func (m *Menu) MoveToBottom() {
	if len(m.Items) > 0 {
		m.SelectedIdx = len(m.Items) - 1
	}
}

// Selected returns the currently selected item, or nil if none
func (m *Menu) Selected() *MenuItem {
	if m.SelectedIdx >= 0 && m.SelectedIdx < len(m.Items) {
		return &m.Items[m.SelectedIdx]
	}
	return nil
}

// SelectedNode returns the command node for the selected item
func (m *Menu) SelectedNode() *CommandNode {
	if item := m.Selected(); item != nil {
		return item.Node
	}
	return nil
}

// IsEmpty returns true if the menu has no items
func (m *Menu) IsEmpty() bool {
	return len(m.Items) == 0
}

// SetItems updates the menu items
func (m *Menu) SetItems(items []MenuItem) {
	m.Items = items
	if m.SelectedIdx >= len(items) {
		m.SelectedIdx = max(0, len(items)-1)
	}
}

// SetFromNode updates the menu from a command node
func (m *Menu) SetFromNode(node *CommandNode) {
	var items []MenuItem
	if node != nil {
		for _, child := range node.Children {
			items = append(items, MenuItem{
				Name:        child.Name,
				Description: child.Description,
				Node:        child,
			})
		}
	}
	m.SetItems(items)
}

// Render renders the menu as a string
func (m *Menu) Render() string {
	if m.IsEmpty() {
		return m.Style.DescriptionStyle.Render("No commands available")
	}

	var lines []string
	cursorWidth := lipgloss.Width(m.Style.Cursor) + m.Style.CursorSpacing

	// Calculate max name width for alignment
	maxNameWidth := 0
	for _, item := range m.Items {
		if w := lipgloss.Width(item.Name); w > maxNameWidth {
			maxNameWidth = w
		}
	}

	for i, item := range m.Items {
		isSelected := i == m.SelectedIdx

		var line strings.Builder

		// Cursor
		if isSelected {
			line.WriteString(m.Style.CursorStyle.Render(m.Style.Cursor))
			line.WriteString(strings.Repeat(" ", m.Style.CursorSpacing))
		} else {
			line.WriteString(strings.Repeat(" ", cursorWidth))
		}

		// Item name
		name := item.Name
		if isSelected {
			name = m.Style.SelectedStyle.Render(name)
		} else {
			name = m.Style.ItemStyle.Render(name)
		}
		line.WriteString(name)

		// Description (if enabled)
		if m.Style.ShowDescriptions && item.Description != "" {
			// Pad to align descriptions
			padding := maxNameWidth - lipgloss.Width(item.Name) + m.Style.DescriptionSpacing
			line.WriteString(strings.Repeat(" ", padding))
			line.WriteString(m.Style.DescriptionStyle.Render(item.Description))
		}

		lines = append(lines, line.String())
	}

	return m.Style.ContainerStyle.Render(strings.Join(lines, "\n"))
}

// RenderWithMaxHeight renders the menu with a scrolling window. When there
// are more items than maxVisible, "..." indicators appear at the edges to
// signal more content. The selected item is always kept within the window.
func (m *Menu) RenderWithMaxHeight(maxVisible int) string {
	if m.IsEmpty() {
		return m.Style.DescriptionStyle.Render("No commands available")
	}

	if maxVisible <= 0 || maxVisible >= len(m.Items) {
		return m.Render()
	}

	// Calculate visible range (keep selected item in view)
	startIdx := 0
	if m.SelectedIdx >= maxVisible {
		startIdx = m.SelectedIdx - maxVisible + 1
	}
	endIdx := startIdx + maxVisible
	if endIdx > len(m.Items) {
		endIdx = len(m.Items)
		startIdx = endIdx - maxVisible
		if startIdx < 0 {
			startIdx = 0
		}
	}

	var lines []string
	cursorWidth := lipgloss.Width(m.Style.Cursor) + m.Style.CursorSpacing

	// Calculate max name width for alignment
	maxNameWidth := 0
	for _, item := range m.Items {
		if w := lipgloss.Width(item.Name); w > maxNameWidth {
			maxNameWidth = w
		}
	}

	// Show scroll indicator at top if needed
	if startIdx > 0 {
		lines = append(lines, m.Style.DescriptionStyle.Render("  ..."))
	}

	for i := startIdx; i < endIdx; i++ {
		item := m.Items[i]
		isSelected := i == m.SelectedIdx

		var line strings.Builder

		// Cursor
		if isSelected {
			line.WriteString(m.Style.CursorStyle.Render(m.Style.Cursor))
			line.WriteString(strings.Repeat(" ", m.Style.CursorSpacing))
		} else {
			line.WriteString(strings.Repeat(" ", cursorWidth))
		}

		// Item name
		name := item.Name
		if isSelected {
			name = m.Style.SelectedStyle.Render(name)
		} else {
			name = m.Style.ItemStyle.Render(name)
		}
		line.WriteString(name)

		// Description (if enabled)
		if m.Style.ShowDescriptions && item.Description != "" {
			padding := maxNameWidth - lipgloss.Width(item.Name) + m.Style.DescriptionSpacing
			line.WriteString(strings.Repeat(" ", padding))
			line.WriteString(m.Style.DescriptionStyle.Render(item.Description))
		}

		lines = append(lines, line.String())
	}

	// Show scroll indicator at bottom if needed
	if endIdx < len(m.Items) {
		lines = append(lines, m.Style.DescriptionStyle.Render("  ..."))
	}

	return m.Style.ContainerStyle.Render(strings.Join(lines, "\n"))
}
