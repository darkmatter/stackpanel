package navigation

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui/output"
	"github.com/spf13/cobra"
)

// ViewState represents the current view mode
type ViewState int

const (
	// ViewMenu shows the navigation menu
	ViewMenu ViewState = iota
	// ViewOutput shows command output
	ViewOutput
	// ViewCustom shows a custom view (like status dashboard)
	ViewCustom
)

// NavigationModel is the main Bubble Tea model for TUI navigation
type NavigationModel struct {
	// Tree structure of commands
	tree *CommandTree
	// Current node in the tree
	currentNode *CommandNode
	// Menu for current node's children
	menu *Menu
	// Stack of previous menu selections (for back navigation)
	selectionStack []int
	// Current view state
	viewState ViewState
	// Terminal dimensions
	width  int
	height int
	// Whether we're quitting
	quitting bool
	// Output buffer for command output display
	output string
	// Custom view model (for views like status dashboard)
	customView tea.Model
	// Help text to display
	helpText string
}

// Command execution messages
type (
	// CommandExecutedMsg is sent after a command finishes executing
	CommandExecutedMsg struct {
		Output string
		Err    error
	}
	// ReturnToMenuMsg is sent when user wants to return to menu from output view
	ReturnToMenuMsg struct{}
)

// NewNavigationModel creates a new navigation model from a cobra root command
func NewNavigationModel(rootCmd *cobra.Command) NavigationModel {
	tree := BuildTree(rootCmd)
	menu := NewMenu(tree.Root)

	return NavigationModel{
		tree:        tree,
		currentNode: tree.Root,
		menu:        menu,
		viewState:   ViewMenu,
		helpText:    "↑/↓: navigate • enter: select • esc: back • q: quit",
	}
}

// Init implements tea.Model
func (m NavigationModel) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model
func (m NavigationModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKeyMsg(msg)

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.menu.Width = msg.Width
		m.menu.Height = msg.Height
		return m, nil

	case CommandExecutedMsg:
		m.output = msg.Output
		if msg.Err != nil {
			m.output = tui.RenderError(msg.Err.Error()) + "\n\n" + m.output
		}
		m.viewState = ViewOutput
		m.helpText = "press any key to return"
		return m, nil

	case ReturnToMenuMsg:
		m.viewState = ViewMenu
		m.helpText = "↑/↓: navigate • enter: select • esc: back • q: quit"
		return m, nil
	}

	// If we have a custom view, update it
	if m.viewState == ViewCustom && m.customView != nil {
		var cmd tea.Cmd
		m.customView, cmd = m.customView.Update(msg)
		return m, cmd
	}

	return m, nil
}

// handleKeyMsg handles keyboard input
func (m NavigationModel) handleKeyMsg(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Handle output view - any key returns to menu
	if m.viewState == ViewOutput {
		m.viewState = ViewMenu
		m.output = ""
		m.helpText = "↑/↓: navigate • enter: select • esc: back • q: quit"
		return m, nil
	}

	// Handle custom view - pass through most keys, but handle esc/q
	if m.viewState == ViewCustom {
		switch msg.String() {
		case "esc":
			m.viewState = ViewMenu
			m.customView = nil
			m.helpText = "↑/↓: navigate • enter: select • esc: back • q: quit"
			return m, nil
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		default:
			if m.customView != nil {
				var cmd tea.Cmd
				m.customView, cmd = m.customView.Update(msg)
				return m, cmd
			}
		}
		return m, nil
	}

	// Handle menu view
	switch msg.String() {
	case "q", "ctrl+c":
		m.quitting = true
		return m, tea.Quit

	case "esc":
		return m.navigateBack()

	case "up", "k":
		m.menu.MoveUp()
		return m, nil

	case "down", "j":
		m.menu.MoveDown()
		return m, nil

	case "home", "g":
		m.menu.MoveToTop()
		return m, nil

	case "end", "G":
		m.menu.MoveToBottom()
		return m, nil

	case "enter", " ":
		return m.selectCurrentItem()
	}

	return m, nil
}

// navigateBack goes up one level in the command tree
func (m NavigationModel) navigateBack() (tea.Model, tea.Cmd) {
	if m.currentNode.Parent != nil {
		// Save current selection to restore later if we come back
		prevSelection := 0
		if len(m.selectionStack) > 0 {
			prevSelection = m.selectionStack[len(m.selectionStack)-1]
			m.selectionStack = m.selectionStack[:len(m.selectionStack)-1]
		}

		m.currentNode = m.currentNode.Parent
		m.menu.SetFromNode(m.currentNode)
		m.menu.SelectedIdx = prevSelection
	}
	return m, nil
}

// selectCurrentItem navigates into the selected command or executes it
func (m NavigationModel) selectCurrentItem() (tea.Model, tea.Cmd) {
	selected := m.menu.SelectedNode()
	if selected == nil {
		return m, nil
	}

	if selected.IsLeaf {
		// Execute the leaf command
		cmd := selected.CobraCmd
		if cmd == nil {
			return m, func() tea.Msg {
				return CommandExecutedMsg{
					Output: "Error: No command to execute",
				}
			}
		}

		// Return a command that executes the cobra command and captures output
		return m, func() tea.Msg {
			var execErr error
			buf := output.Capture(func() {
				execErr = cmd.Execute()
			})

			result := buf.Combined()
			if result == "" && execErr == nil {
				result = "Command completed successfully (no output)"
			}

			return CommandExecutedMsg{
				Output: result,
				Err:    execErr,
			}
		}
	}

	// Navigate into the selected node
	m.selectionStack = append(m.selectionStack, m.menu.SelectedIdx)
	m.currentNode = selected
	m.menu.SetFromNode(m.currentNode)
	m.menu.SelectedIdx = 0

	return m, nil
}

// View implements tea.Model
func (m NavigationModel) View() string {
	if m.quitting {
		return ""
	}

	switch m.viewState {
	case ViewOutput:
		return m.renderOutputView()
	case ViewCustom:
		if m.customView != nil {
			return m.customView.View()
		}
		return m.renderMenuView()
	default:
		return m.renderMenuView()
	}
}

// renderMenuView renders the main menu view
func (m NavigationModel) renderMenuView() string {
	var b strings.Builder

	// Header with banner (condensed)
	header := lipgloss.NewStyle().
		Foreground(tui.ColorSecondary).
		Bold(true).
		Render("Stackpanel")
	b.WriteString(header)
	b.WriteString("\n\n")

	// Breadcrumbs
	breadcrumbs := RenderBreadcrumbs(m.currentNode)
	b.WriteString(breadcrumbs)
	b.WriteString("\n")

	// Current node description if available
	if m.currentNode.Description != "" {
		desc := lipgloss.NewStyle().
			Foreground(tui.ColorDim).
			Italic(true).
			Render(m.currentNode.Description)
		b.WriteString(desc)
		b.WriteString("\n\n")
	} else {
		b.WriteString("\n")
	}

	// Menu
	maxVisible := 15 // Show up to 15 items before scrolling
	if m.height > 0 {
		// Adjust based on terminal height (leave room for header/footer)
		maxVisible = m.height - 10
		if maxVisible < 5 {
			maxVisible = 5
		}
	}
	b.WriteString(m.menu.RenderWithMaxHeight(maxVisible))
	b.WriteString("\n")

	// Help text
	help := tui.HelpStyle.Render("\n" + m.helpText)
	b.WriteString(help)

	return b.String()
}

// renderOutputView renders command output
func (m NavigationModel) renderOutputView() string {
	var b strings.Builder

	// Header
	header := lipgloss.NewStyle().
		Foreground(tui.ColorSecondary).
		Bold(true).
		Render("Command Output")
	b.WriteString(header)
	b.WriteString("\n\n")

	// Breadcrumbs showing what was executed
	breadcrumbs := RenderBreadcrumbs(m.currentNode)
	b.WriteString(breadcrumbs)
	b.WriteString("\n\n")

	// Output content
	outputStyle := lipgloss.NewStyle().
		PaddingLeft(2).
		Foreground(tui.ColorWhite)
	b.WriteString(outputStyle.Render(m.output))
	b.WriteString("\n")

	// Help text
	help := tui.HelpStyle.Render("\n" + m.helpText)
	b.WriteString(help)

	return b.String()
}

// SetCustomView sets a custom view to display (like status dashboard)
func (m *NavigationModel) SetCustomView(view tea.Model) {
	m.customView = view
	m.viewState = ViewCustom
}

// CurrentNode returns the currently selected node
func (m NavigationModel) CurrentNode() *CommandNode {
	return m.currentNode
}

// Tree returns the command tree
func (m NavigationModel) Tree() *CommandTree {
	return m.tree
}

// RunNavigation starts the TUI navigation
func RunNavigation(rootCmd *cobra.Command) error {
	model := NewNavigationModel(rootCmd)
	p := tea.NewProgram(model, tea.WithAltScreen())
	_, err := p.Run()
	return err
}
