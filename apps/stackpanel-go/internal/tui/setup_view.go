package tui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

func (m setupModel) View() string { return m.render() }

func (m *setupModel) render() string {
	if m.quitting {
		return ""
	}
	width := max(12, min(90, m.width-2))
	inner := max(6, width-6)
	wrap := func(s string) string { return ansi.Wrap(s, inner, "") }
	if m.result != "" {
		result := TextBold.Foreground(ColorSecondary).Render("Setup complete")
		for _, verified := range m.verified {
			result += "\n" + RenderSuccess(wrap(verified))
		}
		result += "\n\n" + wrap(m.result)
		if m.identity.root != "" {
			result += "\n\n" + TextSubtle.Render("Repository") + "\n" + wrap(m.identity.root)
		}
		return "\n" + BoxSuccessStyle.Width(width-2).Render(result) + "\n"
	}
	header := TitleStyle.MarginBottom(0).Render("STACKPANEL") + "  " + TextSubtle.Render("Repository setup")
	if m.identity.root != "" {
		header += "\n" + TextDim.Render(ansi.Truncate(m.identity.root, width, "…"))
	}
	var stages []string
	for i, name := range setupStages {
		label := fmt.Sprintf("%d %s", i+1, name)
		if SetupStage(i) < m.stage {
			label = RenderSuccess(name)
		} else if SetupStage(i) == m.stage {
			label = TextBold.Foreground(ColorSecondary).Render(label)
		} else {
			label = TextDim.Render(label)
		}
		stages = append(stages, label)
	}
	steps := strings.Join(stages, TextDim.Render("  ›  "))
	if lipgloss.Width(steps) > width {
		steps = TextBold.Foreground(ColorSecondary).Render(fmt.Sprintf("%d / %d · %s", m.stage+1, len(setupStages), setupStages[m.stage]))
	}
	header = ansi.Wrap(header, width, "") + "\n\n" + steps

	status := m.spinner.View() + " " + m.progress
	if m.question != nil {
		status = RenderInfo("Your turn")
	}
	meta := time.Since(m.started).Round(time.Second).String()
	if m.identity.agent != "" {
		meta = m.identity.agent + " · " + meta
	}
	status = wrap(status) + "\n" + TextDim.Render(wrap(meta))

	// Keep the controls outside the viewport so a long plan cannot hide Apply,
	// and long lists keep the highlighted option in view as the user moves.
	controls := ""
	help := "Ctrl+D details · Esc cancel"
	if q := m.question; q != nil {
		controls = TextBold.Render(wrap(setupDisplayText(q.prompt))) + "\n"
		if q.kind == "text" {
			m.input.Width = max(1, inner-2)
			controls += m.input.View()
			help = "Enter continue · Esc cancel"
		} else {
			visible := min(5, max(1, m.height-16))
			start := max(0, min(m.cursor-visible+1, len(q.options)-visible))
			end := min(len(q.options), start+visible)
			for i := start; i < end; i++ {
				marker := "  "
				if i == m.cursor {
					marker = "› "
				}
				if q.kind == "multi" {
					if m.selected[i] {
						marker += "[✓] "
					} else {
						marker += "[ ] "
					}
				}
				line := marker + setupDisplayText(q.options[i])
				if indexOf(q.defaults, q.options[i]) >= 0 {
					line += " (default)"
				}
				line = wrap(line)
				if i == m.cursor {
					line = TextBold.Foreground(ColorSecondary).Render(line)
				}
				controls += line + "\n"
			}
			if len(q.options) > visible {
				controls += TextDim.Render(fmt.Sprintf("%d–%d of %d choices", start+1, end, len(q.options))) + "\n"
			}
			controls = strings.TrimSuffix(controls, "\n")
			help = "↑↓ choose · Enter continue · Esc cancel"
			if q.kind == "multi" {
				help = "↑↓ move · Space toggle · Enter continue · Esc cancel"
			}
		}
		if m.validation != "" {
			controls += "\n" + RenderError(wrap(m.validation))
		}
	}

	body := m.document
	if body == "" && m.question == nil {
		body = "Working on your repository. Ctrl+D shows recent activity."
		if m.stage == SetupConnect {
			body = "Studio will confirm when it connects to your local agent."
		}
	}
	if m.details && len(m.activity) > 0 {
		body += "\n\n" + TextSubtle.Render("Recent activity") + "\n" + strings.Join(m.activity, "\n")
	}
	body = wrap(body)
	if m.document != "" || m.details {
		help = "PgUp/PgDn scroll · " + help
	}
	help = ansi.Wrap(help, width, "")
	panel := status
	if body != "" {
		available := m.height - lipgloss.Height(header) - lipgloss.Height(status) - lipgloss.Height(help) - 9
		if controls != "" {
			available -= lipgloss.Height(controls) + 1
		}
		m.viewport.Width = inner
		m.viewport.Height = max(1, min(12, min(available, lipgloss.Height(body))))
		m.viewport.SetContent(body)
		panel += "\n\n" + m.viewport.View()
	}
	if controls != "" {
		panel += "\n\n" + controls
	}
	return "\n" + header + "\n\n" + BoxActiveStyle.Padding(1, 2).Width(width-2).Render(panel) + "\n" + TextDim.Render(help) + "\n"
}
