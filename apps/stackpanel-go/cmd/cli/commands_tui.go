package cmd

import (
	"fmt"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui/output"
)

type commandsViewState int

const (
	commandsViewList commandsViewState = iota
	commandsViewRunning
	commandsViewHelp
	commandsViewOutput
)

type commandEntry struct {
	Name    string
	Command SerializableCommand
}

type commandRunFinishedMsg struct {
	Name   string
	Output string
	Err    error
}

type returnToCommandsMsg struct{}

type commandsModel struct {
	commands []commandEntry

	devshellEnv map[string]string

	selected int
	width    int
	height   int

	state         commandsViewState
	outputViewer  output.ViewerModel
	hasViewer     bool
	runningLabel  string
	statusMessage string

	spinner spinner.Model
}

func newCommandsModel(commands map[string]SerializableCommand, devshellEnv map[string]string) commandsModel {
	entries := buildCommandEntries(commands)

	spin := spinner.New()
	spin.Spinner = spinner.Dot
	spin.Style = tui.SpinnerStyle

	return commandsModel{
		commands:    entries,
		devshellEnv: devshellEnv,
		selected:    0,
		state:       commandsViewList,
		spinner:     spin,
	}
}

func runCommandsTUI(commands map[string]SerializableCommand, devshellEnv map[string]string) error {
	model := newCommandsModel(commands, devshellEnv)
	program := tui.NewInteractiveProgram(model)
	_, err := program.Run()
	return err
}

func buildCommandEntries(commands map[string]SerializableCommand) []commandEntry {
	if len(commands) == 0 {
		return nil
	}

	names := make([]string, 0, len(commands))
	for name := range commands {
		names = append(names, name)
	}
	sort.Strings(names)

	entries := make([]commandEntry, 0, len(names))
	for _, name := range names {
		entries = append(entries, commandEntry{
			Name:    name,
			Command: commands[name],
		})
	}
	return entries
}

func (m commandsModel) Init() tea.Cmd {
	return nil
}

func (m commandsModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg.(type) {
	case returnToCommandsMsg:
		m.state = commandsViewList
		m.hasViewer = false
		m.runningLabel = ""
		return m, nil
	}

	if m.state == commandsViewHelp || m.state == commandsViewOutput {
		if ws, ok := msg.(tea.WindowSizeMsg); ok {
			m.width = ws.Width
			m.height = ws.Height
		}
		var cmd tea.Cmd
		var updated tea.Model
		updated, cmd = m.outputViewer.Update(msg)
		if viewer, ok := updated.(output.ViewerModel); ok {
			m.outputViewer = viewer
		}
		return m, cmd
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "up", "k":
			m.moveSelection(-1)
		case "down", "j":
			m.moveSelection(1)
		case "home", "g":
			m.selected = 0
		case "end", "G":
			if len(m.commands) > 0 {
				m.selected = len(m.commands) - 1
			}
		case "h", "?":
			return m.showHelp(), nil
		case "enter", " ":
			cmd := m.runSelected()
			if cmd != nil {
				m.state = commandsViewRunning
				m.runningLabel = m.commands[m.selected].Name
				return m, tea.Batch(m.spinner.Tick, cmd)
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case commandRunFinishedMsg:
		viewer := output.NewViewerModel(
			msg.Output,
			output.WithTitle(fmt.Sprintf("Command Output: %s", msg.Name)),
			output.WithReturnMsg(returnToCommandsMsg{}),
		)
		m.outputViewer = viewer
		m.hasViewer = true
		m.state = commandsViewOutput
		m.runningLabel = ""
		if m.width > 0 && m.height > 0 {
			m.updateViewerSize(tea.WindowSizeMsg{Width: m.width, Height: m.height})
		}
		return m, nil

	case spinner.TickMsg:
		if m.state == commandsViewRunning {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
	}

	return m, nil
}

func (m commandsModel) View() string {
	switch m.state {
	case commandsViewRunning:
		return tui.RenderFrame(m.renderRunningView())
	case commandsViewHelp, commandsViewOutput:
		return tui.RenderFrame(m.outputViewer.View())
	default:
		return tui.RenderFrame(m.renderListView())
	}
}

func (m *commandsModel) moveSelection(delta int) {
	if len(m.commands) == 0 {
		return
	}

	m.selected += delta
	if m.selected < 0 {
		m.selected = 0
	}
	if m.selected >= len(m.commands) {
		m.selected = len(m.commands) - 1
	}
}

func (m commandsModel) renderListView() string {
	if len(m.commands) == 0 {
		return tui.TitleStyle.Render("Stackpanel Commands") +
			"\n\n" +
			tui.TextDim.Render("No commands are defined in this project.") +
			"\n" +
			tui.HelpStyle.Render("q: quit")
	}

	listWidth := 48
	if m.width > 0 {
		listWidth = max(32, m.width/2)
	}
	detailWidth := 44
	if m.width > 0 {
		detailWidth = max(28, m.width-listWidth-6)
	}

	var b strings.Builder
	header := tui.TitleStyle.Render("Stackpanel Commands")
	subtitle := tui.SubtitleStyle.Render("Browse devshell commands, view help, and run them directly.")
	b.WriteString(header)
	b.WriteString("\n")
	b.WriteString(subtitle)
	b.WriteString("\n\n")

	left := m.renderCommandsList(listWidth)
	right := m.renderCommandDetails(detailWidth)

	content := lipgloss.JoinHorizontal(
		lipgloss.Top,
		left,
		right,
	)

	b.WriteString(content)
	b.WriteString("\n")

	help := "↑/↓: select • enter: run • h/?: help text • q: quit"
	b.WriteString(tui.HelpStyle.Render(help))

	if m.statusMessage != "" {
		b.WriteString("\n")
		b.WriteString(tui.RenderWarning(m.statusMessage))
	}

	return b.String()
}

func (m commandsModel) renderCommandsList(width int) string {
	items := make([]string, 0, len(m.commands))
	cursor := tui.SymbolArrow
	cursorSpacing := " "

	maxNameWidth := 0
	for _, entry := range m.commands {
		if w := lipgloss.Width(entry.Name); w > maxNameWidth {
			maxNameWidth = w
		}
	}

	for idx, entry := range m.commands {
		isSelected := idx == m.selected
		var line strings.Builder

		if isSelected {
			line.WriteString(tui.SpinnerStyle.Render(cursor))
		} else {
			line.WriteString(" ")
		}
		line.WriteString(cursorSpacing)

		nameStyle := tui.TextSubtle
		if isSelected {
			nameStyle = tui.TextBold.Foreground(tui.ColorWhite)
		}

		name := nameStyle.Render(entry.Name)
		line.WriteString(name)

		if desc := entry.description(); desc != "" {
			padding := maxNameWidth - lipgloss.Width(entry.Name) + 2
			line.WriteString(strings.Repeat(" ", padding))
			descStyle := tui.TextDim
			if isSelected {
				descStyle = lipgloss.NewStyle().Foreground(tui.ColorSubtle)
			}
			line.WriteString(descStyle.Render(desc))
		}

		items = append(items, line.String())
	}

	box := tui.BoxStyle.Width(width)
	return box.Render(strings.Join(items, "\n"))
}

func (m commandsModel) renderCommandDetails(width int) string {
	if len(m.commands) == 0 {
		return tui.BoxStyle.Width(width).Render(tui.TextDim.Render("Select a command to see details"))
	}

	entry := m.commands[m.selected]

	var b strings.Builder
	title := lipgloss.NewStyle().
		Foreground(tui.ColorPrimary).
		Bold(true).
		Render(entry.Name)
	b.WriteString(title)
	b.WriteString("\n")

	if desc := entry.description(); desc != "" {
		b.WriteString(tui.TextDim.Render(desc))
		b.WriteString("\n\n")
	} else {
		b.WriteString(tui.TextDim.Render("No description provided."))
		b.WriteString("\n\n")
	}

	// Display arguments if defined
	if len(entry.Command.Args) > 0 {
		b.WriteString(tui.TextSubtle.Render("Arguments"))
		b.WriteString("\n")
		argStyle := lipgloss.NewStyle().Foreground(tui.ColorPrimary)
		requiredStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#ef4444"))
		for _, arg := range entry.Command.Args {
			argLine := "  " + argStyle.Render(arg.Name)
			if arg.Required != nil && *arg.Required {
				argLine += " " + requiredStyle.Render("*")
			}
			if arg.Description != nil && *arg.Description != "" {
				argLine += " " + tui.TextDim.Render(*arg.Description)
			}
			b.WriteString(argLine)
			b.WriteString("\n")
		}
		b.WriteString("\n")
	}

	b.WriteString(tui.TextSubtle.Render("Exec"))
	b.WriteString("\n")
	code := lipgloss.NewStyle().
		Foreground(tui.ColorWhite).
		Background(tui.ColorSurface).
		Padding(0, 1).
		Width(width - 4).
		Render(strings.TrimSpace(entry.Command.Exec))
	b.WriteString(code)
	b.WriteString("\n\n")

	if len(entry.Command.Env) > 0 {
		b.WriteString(tui.TextSubtle.Render("Env overrides"))
		b.WriteString("\n")
		envLines := make([]string, 0, len(entry.Command.Env))
		keys := make([]string, 0, len(entry.Command.Env))
		for k := range entry.Command.Env {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			envLines = append(envLines, fmt.Sprintf("%s=%s", k, entry.Command.Env[k]))
		}
		b.WriteString(strings.Join(envLines, "\n"))
		b.WriteString("\n")
	} else {
		b.WriteString(tui.TextDim.Render("No command-specific environment."))
		b.WriteString("\n")
	}

	return tui.BoxStyle.Width(width).Render(b.String())
}

func (m commandsModel) renderRunningView() string {
	if len(m.commands) == 0 {
		return tui.TextDim.Render("No commands to run.")
	}

	line := fmt.Sprintf("%s Running %s ...", m.spinner.View(), m.runningLabel)
	return tui.TitleStyle.Render("Executing Command") + "\n\n" + line
}

func (m commandsModel) showHelp() commandsModel {
	if len(m.commands) == 0 {
		return m
	}

	entry := m.commands[m.selected]
	helpText := formatCommandHelp(entry)
	viewer := output.NewViewerModel(
		helpText,
		output.WithTitle(fmt.Sprintf("Help: %s", entry.Name)),
		output.WithMarkdown(),
		output.WithReturnMsg(returnToCommandsMsg{}),
	)
	m.outputViewer = viewer
	m.hasViewer = true
	m.state = commandsViewHelp
	if m.width > 0 && m.height > 0 {
		m.updateViewerSize(tea.WindowSizeMsg{Width: m.width, Height: m.height})
	}
	return m
}

func (m commandsModel) runSelected() tea.Cmd {
	if len(m.commands) == 0 {
		return nil
	}

	entry := m.commands[m.selected]
	return func() tea.Msg {
		outputText, err := runCommandCaptured(entry.Command, []string{}, m.devshellEnv)
		rendered := outputText
		if strings.TrimSpace(rendered) == "" && err == nil {
			rendered = "Command completed successfully (no output)"
		}
		if err != nil {
			rendered = tui.RenderError(err.Error()) + "\n\n" + rendered
		}
		return commandRunFinishedMsg{
			Name:   entry.Name,
			Output: rendered,
			Err:    err,
		}
	}
}

func (m *commandsModel) updateViewerSize(msg tea.WindowSizeMsg) {
	updated, _ := m.outputViewer.Update(msg)
	if viewer, ok := updated.(output.ViewerModel); ok {
		m.outputViewer = viewer
	}
}

func (c commandEntry) description() string {
	if c.Command.Description != nil {
		return strings.TrimSpace(*c.Command.Description)
	}
	return ""
}

func formatCommandHelp(entry commandEntry) string {
	var b strings.Builder
	b.WriteString("# ")
	b.WriteString(entry.Name)
	b.WriteString("\n\n")

	if desc := entry.description(); desc != "" {
		b.WriteString(desc)
		b.WriteString("\n\n")
	}

	// Display documented arguments
	if len(entry.Command.Args) > 0 {
		b.WriteString("## Arguments\n\n")
		for _, arg := range entry.Command.Args {
			// Argument name with indicators
			argLine := "- **" + arg.Name + "**"
			if arg.Required != nil && *arg.Required {
				argLine += " *(required)*"
			}
			if arg.Default != nil && *arg.Default != "" {
				argLine += fmt.Sprintf(" [default: `%s`]", *arg.Default)
			}
			b.WriteString(argLine)

			// Description
			if arg.Description != nil && *arg.Description != "" {
				b.WriteString(" — ")
				b.WriteString(*arg.Description)
			}
			b.WriteString("\n")
		}
		b.WriteString("\n")
	}

	b.WriteString("## Script\n\n")
	b.WriteString("```bash\n")
	b.WriteString(strings.TrimSpace(entry.Command.Exec))
	b.WriteString("\n```\n")

	if len(entry.Command.Env) > 0 {
		b.WriteString("\n## Environment overrides\n\n")
		keys := make([]string, 0, len(entry.Command.Env))
		for k := range entry.Command.Env {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			b.WriteString(fmt.Sprintf("- `%s=%s`\n", k, entry.Command.Env[k]))
		}
	}

	b.WriteString("\n")
	b.WriteString("_Press q/esc/enter to return_")
	return b.String()
}
