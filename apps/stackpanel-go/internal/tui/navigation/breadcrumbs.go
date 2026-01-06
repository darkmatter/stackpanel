package navigation

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/darkmatter/stackpanel/apps/stackpanel-go/internal/tui"
)

// BreadcrumbsStyle defines the styling for breadcrumb rendering
type BreadcrumbsStyle struct {
	// Separator between breadcrumb items (default: " > ")
	Separator string
	// Style for inactive (parent) breadcrumb items
	InactiveStyle lipgloss.Style
	// Style for active (current) breadcrumb item
	ActiveStyle lipgloss.Style
	// Style for the separator
	SeparatorStyle lipgloss.Style
	// Container style (padding, margin, etc.)
	ContainerStyle lipgloss.Style
}

// DefaultBreadcrumbsStyle returns the default breadcrumb styling
func DefaultBreadcrumbsStyle() BreadcrumbsStyle {
	return BreadcrumbsStyle{
		Separator:      " > ",
		InactiveStyle:  lipgloss.NewStyle().Foreground(tui.ColorDim),
		ActiveStyle:    lipgloss.NewStyle().Foreground(tui.ColorSecondary).Bold(true),
		SeparatorStyle: lipgloss.NewStyle().Foreground(tui.ColorMuted),
		ContainerStyle: lipgloss.NewStyle().MarginBottom(1),
	}
}

// RenderBreadcrumbs renders a breadcrumb trail for the given node
func RenderBreadcrumbs(node *CommandNode) string {
	return RenderBreadcrumbsWithStyle(node, DefaultBreadcrumbsStyle())
}

// RenderBreadcrumbsWithStyle renders breadcrumbs with custom styling
func RenderBreadcrumbsWithStyle(node *CommandNode, style BreadcrumbsStyle) string {
	if node == nil {
		return ""
	}

	path := node.GetPath()
	if len(path) == 0 {
		return ""
	}

	var parts []string
	for i, name := range path {
		isLast := i == len(path)-1
		if isLast {
			parts = append(parts, style.ActiveStyle.Render(name))
		} else {
			parts = append(parts, style.InactiveStyle.Render(name))
		}
	}

	separator := style.SeparatorStyle.Render(style.Separator)
	result := strings.Join(parts, separator)

	return style.ContainerStyle.Render(result)
}

// RenderBreadcrumbsFromPath renders breadcrumbs from a path slice
func RenderBreadcrumbsFromPath(path []string) string {
	return RenderBreadcrumbsFromPathWithStyle(path, DefaultBreadcrumbsStyle())
}

// RenderBreadcrumbsFromPathWithStyle renders breadcrumbs from a path slice with custom styling
func RenderBreadcrumbsFromPathWithStyle(path []string, style BreadcrumbsStyle) string {
	if len(path) == 0 {
		return ""
	}

	var parts []string
	for i, name := range path {
		isLast := i == len(path)-1
		if isLast {
			parts = append(parts, style.ActiveStyle.Render(name))
		} else {
			parts = append(parts, style.InactiveStyle.Render(name))
		}
	}

	separator := style.SeparatorStyle.Render(style.Separator)
	result := strings.Join(parts, separator)

	return style.ContainerStyle.Render(result)
}
