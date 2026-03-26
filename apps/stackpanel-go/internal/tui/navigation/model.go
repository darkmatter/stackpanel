// Package navigation provides the hierarchical menu system for the stackpanel TUI.
// It converts a Cobra command tree into a navigable, interactive menu with
// breadcrumbs, command execution, and output viewing. This is the default
// view when running `stackpanel` (or `sp`) with no arguments.
package navigation

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
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
	// ViewExecuting shows command execution spinner
	ViewExecuting
	// ViewOutput shows command output
	ViewOutput
	// ViewCustom shows a custom view (like status dashboard)
	ViewCustom
)

// NavigationModel is the main Bubble Tea model for TUI navigation.
// It manages a command tree, a selection stack for back-navigation,
// and delegates to sub-views (output viewer, custom views) when needed.
type NavigationModel struct {
	tree           *CommandTree
	currentNode    *CommandNode
	menu           *Menu
	selectionStack []int // Cursor positions for each depth level, enabling back-navigation
	viewState      ViewState
	width          int
	height         int
	quitting       bool
	outputViewer   output.ViewerModel
	hasOutput      bool
	customView     tea.Model // Pluggable sub-view (status dashboard, agent monitor, etc.)
	helpText       string
	spinner        spinner.Model
	runningCommand string
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
	spin := spinner.New()
	spin.Spinner = spinner.Dot
	spin.Style = tui.SpinnerStyle

	return NavigationModel{
		tree:        tree,
		currentNode: tree.Root,
		menu:        menu,
		viewState:   ViewMenu,
		helpText:    "↑/↓: navigate • enter: select • esc: back • q: quit",
		spinner:     spin,
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
		if m.viewState == ViewOutput && m.hasOutput {
			break
		}
		return m.handleKeyMsg(msg)

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.menu.Width = msg.Width
		m.menu.Height = msg.Height
		if m.viewState == ViewOutput && m.hasOutput {
			m.updateOutputViewerSize(msg)
		}

	case CommandExecutedMsg:
		content := msg.Output
		if msg.Err != nil {
			content = tui.RenderError(msg.Err.Error()) + "\n\n" + content
		}
		viewer := output.NewViewerModel(
			content,
			output.WithTitle("Command Output"),
			output.WithReturnMsg(ReturnToMenuMsg{}),
		)
		m.outputViewer = viewer
		m.hasOutput = true
		m.viewState = ViewOutput
		m.runningCommand = ""
		if m.width > 0 && m.height > 0 {
			m.updateOutputViewerSize(tea.WindowSizeMsg{Width: m.width, Height: m.height})
		}
		return m, nil

	case ReturnToMenuMsg:
		m.viewState = ViewMenu
		m.helpText = "↑/↓: navigate • enter: select • esc: back • q: quit"
		m.hasOutput = false
		return m, nil
	}

	if m.viewState == ViewExecuting {
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	}

	if m.viewState == ViewOutput && m.hasOutput {
		var cmd tea.Cmd
		var updated tea.Model
		updated, cmd = m.outputViewer.Update(msg)
		if viewer, ok := updated.(output.ViewerModel); ok {
			m.outputViewer = viewer
		}
		return m, cmd
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
	if m.viewState == ViewExecuting {
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		}
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
		if selected.HasRequiredArgs() {
			return m.showCommandArgsRequired(selected)
		}

		m.viewState = ViewExecuting
		m.runningCommand = m.renderCommandLabel(selected)
		m.helpText = "running command..."
		return m, tea.Batch(m.spinner.Tick, m.executeCommand(selected))
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

	var content string
	switch m.viewState {
	case ViewExecuting:
		content = m.renderExecutingView()
	case ViewOutput:
		if m.hasOutput {
			content = m.outputViewer.View()
			break
		}
		content = m.renderMenuView()
	case ViewCustom:
		if m.customView != nil {
			content = m.customView.View()
			break
		}
		content = m.renderMenuView()
	default:
		content = m.renderMenuView()
	}

	return tui.RenderFrame(content)
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

// renderExecutingView shows an execution spinner
func (m NavigationModel) renderExecutingView() string {
	var b strings.Builder

	// Header
	header := lipgloss.NewStyle().
		Foreground(tui.ColorSecondary).
		Bold(true).
		Render("Running Command")
	b.WriteString(header)
	b.WriteString("\n\n")

	// Breadcrumbs showing what was executed
	b.WriteString(RenderBreadcrumbs(m.currentNode))
	b.WriteString("\n\n")

	line := fmt.Sprintf("%s %s", m.spinner.View(), m.runningCommand)
	rendered := lipgloss.NewStyle().
		PaddingLeft(2).
		Foreground(tui.ColorWhite).
		Render(line)
	b.WriteString(rendered)

	return b.String()
}

func (m NavigationModel) renderCommandLabel(node *CommandNode) string {
	if node == nil {
		return "command"
	}
	path := node.GetPath()
	if len(path) > 1 {
		return fmt.Sprintf("stackpanel %s", strings.Join(path[1:], " "))
	}
	return "stackpanel"
}

func (m NavigationModel) showCommandArgsRequired(node *CommandNode) (tea.Model, tea.Cmd) {
	command := m.renderCommandLabel(node)
	msg := fmt.Sprintf("%s requires arguments.\n\nRun it directly:\n  %s <args>", command, command)
	viewer := output.NewViewerModel(
		msg,
		output.WithTitle("Command Requires Arguments"),
		output.WithReturnMsg(ReturnToMenuMsg{}),
	)
	m.outputViewer = viewer
	m.hasOutput = true
	m.viewState = ViewOutput
	return m, nil
}

// executeCommand runs a Cobra command by reconstructing its args from the tree path.
// The --no-tui flag is appended to prevent recursive TUI launches when the
// command would normally open its own interactive view.
// NOTE: root.SetArgs is reset to empty after execution to avoid polluting
// subsequent invocations of the same root command.
func (m NavigationModel) executeCommand(node *CommandNode) tea.Cmd {
	return func() tea.Msg {
		root := m.tree.Root.CobraCmd
		if root == nil {
			return CommandExecutedMsg{Output: "Error: No root command to execute"}
		}

		path := node.GetPath()
		if len(path) == 0 {
			return CommandExecutedMsg{Output: "Error: Command path is empty"}
		}

		args := append([]string{}, path[1:]...)
		args = append(args, "--no-tui")
		root.SetArgs(args)

		var execErr error
		buf := output.Capture(func() {
			execErr = root.Execute()
		})
		root.SetArgs([]string{})

		result := buf.Combined()
		if strings.TrimSpace(result) == "" && execErr == nil {
			result = "Command completed successfully (no output)"
		}

		return CommandExecutedMsg{
			Output: result,
			Err:    execErr,
		}
	}
}

func (m *NavigationModel) updateOutputViewerSize(msg tea.WindowSizeMsg) {
	updated, _ := m.outputViewer.Update(msg)
	if viewer, ok := updated.(output.ViewerModel); ok {
		m.outputViewer = viewer
	}
}

// SetCustomView replaces the menu with a custom sub-view (e.g., status dashboard).
// The navigation model handles esc/q to return to the menu; all other keys
// are forwarded to the custom view.
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
