package secrets

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

// Styles
var (
	sectionTitle = lipgloss.NewStyle().
			Bold(true).
			Foreground(tui.ColorPrimary).
			MarginBottom(1)

	sectionTitleActive = lipgloss.NewStyle().
				Bold(true).
				Foreground(tui.ColorSecondary).
				MarginBottom(1)

	itemStyle = lipgloss.NewStyle().
			PaddingLeft(2)

	itemActiveStyle = lipgloss.NewStyle().
			PaddingLeft(1).
			Foreground(tui.ColorSecondary)

	dimStyle = lipgloss.NewStyle().
			Foreground(tui.ColorDim)

	keyStyle = lipgloss.NewStyle().
			Foreground(tui.ColorInfo).
			Bold(true)

	valueStyle = lipgloss.NewStyle().
			Foreground(tui.ColorSuccess)

	errorStyle = lipgloss.NewStyle().
			Foreground(tui.ColorError)

	warningStyle = lipgloss.NewStyle().
			Foreground(tui.ColorWarning)

	badgeOK = lipgloss.NewStyle().
		Foreground(tui.ColorSuccess).
		Bold(true)

	badgeWarn = lipgloss.NewStyle().
			Foreground(tui.ColorWarning).
			Bold(true)

	headerStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(tui.ColorPrimary).
			BorderBottom(true).
			BorderStyle(lipgloss.NormalBorder()).
			BorderForeground(tui.ColorBorder).
			Width(60).
			MarginBottom(1)

	helpStyle = lipgloss.NewStyle().
			Foreground(tui.ColorDim).
			MarginTop(1)

	boxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(tui.ColorBorder).
			Padding(1, 2)

	detailLabel = lipgloss.NewStyle().
			Foreground(tui.ColorDim).
			Width(14)

	detailValue = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#ffffff"))
)

func (m Model) View() string {
	switch m.state {
	case viewDashboard:
		return m.viewDashboard()
	case viewGroupDetail:
		return m.viewGroupDetail()
	case viewSecretDetail:
		return m.viewSecretDetail()
	case viewRecipients:
		return m.viewRecipients()
	case viewHelp:
		return m.viewHelp()
	}
	return ""
}

func (m Model) viewDashboard() string {
	var b strings.Builder

	// Header
	b.WriteString(headerStyle.Render("Secrets Dashboard"))
	b.WriteString("\n")

	if m.loading {
		b.WriteString(m.spinner.View() + " Loading secrets...")
		return tui.RenderFrame(b.String())
	}

	if m.err != nil {
		b.WriteString(errorStyle.Render(tui.SymbolError+" Error: "+m.err.Error()) + "\n\n")
		b.WriteString(dimStyle.Render("Make sure the agent is running (stackpanel agent)"))
		b.WriteString("\n\n")
		b.WriteString(helpStyle.Render("r refresh  q quit"))
		return tui.RenderFrame(b.String())
	}

	// Status bar
	b.WriteString(m.renderStatusBar())
	b.WriteString("\n\n")

	// Groups section
	b.WriteString(m.renderGroupsSection())
	b.WriteString("\n")

	// Recipients section
	b.WriteString(m.renderRecipientsSection())
	b.WriteString("\n")

	// Setup section
	b.WriteString(m.renderSetupSection())
	b.WriteString("\n")

	// Help
	b.WriteString(helpStyle.Render("tab section  ↑↓ navigate  enter select  r refresh  ? help  q quit"))

	return tui.RenderFrame(b.String())
}

func (m Model) renderStatusBar() string {
	groupCount := len(m.groups)
	secretCount := m.totalSecrets()
	recipientCount := len(m.recipients)

	parts := []string{
		fmt.Sprintf("%s %d group(s)", tui.SymbolInfo, groupCount),
		fmt.Sprintf("%s %d secret(s)", tui.SymbolDot, secretCount),
		fmt.Sprintf("%s %d recipient(s)", tui.SymbolDot, recipientCount),
	}

	if m.workflow.Exists {
		parts = append(parts, badgeOK.Render(tui.SymbolSuccess+" rekey workflow"))
	} else {
		parts = append(parts, badgeWarn.Render(tui.SymbolWarning+" no rekey workflow"))
	}

	return dimStyle.Render(strings.Join(parts, "   "))
}

func (m Model) renderGroupsSection() string {
	var b strings.Builder

	title := sectionTitle
	if m.activeSection == sectionGroups {
		title = sectionTitleActive
	}
	b.WriteString(title.Render(tui.SymbolArrow + " Groups"))
	b.WriteString("\n")

	groupNames := m.sortedGroupNames()

	if len(groupNames) == 0 {
		b.WriteString(dimStyle.Render("  No groups found. Run: secrets:init-group <name>"))
		return b.String()
	}

	for i, name := range groupNames {
		group := m.groups[name]
		secretCount := len(group.Keys)

		cursor := "  "
		style := itemStyle
		if m.activeSection == sectionGroups && m.cursor == i {
			cursor = tui.SymbolArrow + " "
			style = itemActiveStyle
		}

		status := badgeOK.Render(tui.SymbolRunning)
		if !group.Initialized {
			status = badgeWarn.Render(tui.SymbolStopped)
		}

		line := fmt.Sprintf("%s%s %s  %s",
			cursor,
			status,
			style.Render(name),
			dimStyle.Render(fmt.Sprintf("(%d secrets)", secretCount)),
		)
		b.WriteString(line + "\n")
	}

	return b.String()
}

func (m Model) renderRecipientsSection() string {
	var b strings.Builder

	title := sectionTitle
	if m.activeSection == sectionRecipients {
		title = sectionTitleActive
	}
	b.WriteString(title.Render(tui.SymbolArrow + " Recipients"))
	b.WriteString("\n")

	cursor := "  "
	style := itemStyle
	if m.activeSection == sectionRecipients && m.cursor == 0 {
		cursor = tui.SymbolArrow + " "
		style = itemActiveStyle
	}

	count := len(m.recipients)
	if count == 0 {
		b.WriteString(fmt.Sprintf("%s%s", cursor, style.Render(dimStyle.Render("No recipients. Enter devshell to auto-register."))))
	} else {
		names := make([]string, 0, count)
		for _, r := range m.recipients {
			names = append(names, r.Name)
		}
		b.WriteString(fmt.Sprintf("%s%s  %s",
			cursor,
			style.Render(fmt.Sprintf("%d recipient(s)", count)),
			dimStyle.Render(strings.Join(names, ", ")),
		))
	}

	return b.String()
}

func (m Model) renderSetupSection() string {
	var b strings.Builder

	title := sectionTitle
	if m.activeSection == sectionSetup {
		title = sectionTitleActive
	}
	b.WriteString(title.Render(tui.SymbolArrow + " Setup Status"))
	b.WriteString("\n")

	// Group keys
	if len(m.groups) > 0 {
		b.WriteString("  " + badgeOK.Render(tui.SymbolSuccess) + " Groups initialized\n")
	} else {
		b.WriteString("  " + badgeWarn.Render(tui.SymbolWarning) + " No groups initialized\n")
		b.WriteString(dimStyle.Render("    Run: secrets:init-group dev") + "\n")
	}

	// Recipients
	if len(m.recipients) > 0 {
		b.WriteString("  " + badgeOK.Render(tui.SymbolSuccess) + " Recipients registered\n")
	} else {
		b.WriteString("  " + badgeWarn.Render(tui.SymbolWarning) + " No recipients registered\n")
	}

	// Rekey workflow
	if m.workflow.Exists {
		b.WriteString("  " + badgeOK.Render(tui.SymbolSuccess) + " Rekey workflow configured\n")
	} else {
		b.WriteString("  " + badgeWarn.Render(tui.SymbolWarning) + " Rekey workflow missing\n")
		b.WriteString(dimStyle.Render("    Run: secrets:init-group <name> --force-gh") + "\n")
	}

	return b.String()
}

// --- Group detail view ---

func (m Model) viewGroupDetail() string {
	var b strings.Builder

	group, ok := m.groups[m.selectedGroup]
	if !ok {
		b.WriteString(errorStyle.Render("Group not found: " + m.selectedGroup))
		return tui.RenderFrame(b.String())
	}

	b.WriteString(headerStyle.Render(fmt.Sprintf("Group: %s", m.selectedGroup)))
	b.WriteString("\n")

	// Group info
	b.WriteString(detailLabel.Render("Secrets:") + detailValue.Render(fmt.Sprintf("%d", len(group.Keys))) + "\n")
	if group.PubKey != "" {
		b.WriteString(detailLabel.Render("Public Key:") + dimStyle.Render(truncate(group.PubKey, 40)) + "\n")
	}
	b.WriteString("\n")

	// Secrets list
	if len(group.Keys) == 0 {
		b.WriteString(dimStyle.Render("  No secrets in this group.") + "\n")
		b.WriteString(dimStyle.Render("  Run: secrets:set <key> --group "+m.selectedGroup+" --value <value>") + "\n")
	} else {
		for i, key := range group.Keys {
			cursor := "  "
			style := itemStyle
			if m.cursor == i {
				cursor = tui.SymbolArrow + " "
				style = itemActiveStyle
			}
			b.WriteString(fmt.Sprintf("%s%s\n", cursor, style.Render(keyStyle.Render(key))))
		}
	}

	b.WriteString("\n")
	b.WriteString(helpStyle.Render("enter view  esc back  r refresh  q quit"))

	return tui.RenderFrame(b.String())
}

// --- Secret detail view ---

func (m Model) viewSecretDetail() string {
	var b strings.Builder

	b.WriteString(headerStyle.Render(fmt.Sprintf("Secret: %s/%s", m.selectedGroup, m.selectedKey)))
	b.WriteString("\n")

	b.WriteString(detailLabel.Render("Group:") + detailValue.Render(m.selectedGroup) + "\n")
	b.WriteString(detailLabel.Render("Key:") + keyStyle.Render(m.selectedKey) + "\n")
	b.WriteString("\n")

	if m.loadingSecret {
		b.WriteString(m.spinner.View() + " Decrypting...")
	} else if m.secretErr != nil {
		b.WriteString(detailLabel.Render("Value:") + errorStyle.Render("decryption failed: "+m.secretErr.Error()))
	} else {
		b.WriteString(detailLabel.Render("Value:") + "\n")
		b.WriteString(boxStyle.Render(valueStyle.Render(m.secretValue)))
	}

	b.WriteString("\n\n")
	b.WriteString(helpStyle.Render("esc back  r refresh  q quit"))

	return tui.RenderFrame(b.String())
}

// --- Recipients view ---

func (m Model) viewRecipients() string {
	var b strings.Builder

	b.WriteString(headerStyle.Render("Recipients"))
	b.WriteString("\n")

	if m.loading {
		b.WriteString(m.spinner.View() + " Loading...")
		return tui.RenderFrame(b.String())
	}

	if len(m.recipients) == 0 {
		b.WriteString(dimStyle.Render("No recipients registered.") + "\n\n")
		b.WriteString(dimStyle.Render("Recipients are auto-registered when team members enter the devshell.") + "\n")
		b.WriteString(dimStyle.Render("Their public key is saved to .stackpanel/secrets/recipients/<name>.age.pub") + "\n")
	} else {
		for _, r := range m.recipients {
			b.WriteString(fmt.Sprintf("  %s %s  %s\n",
				badgeOK.Render(tui.SymbolRunning),
				keyStyle.Render(r.Name),
				dimStyle.Render(truncate(r.PublicKey, 30)),
			))
		}
	}

	b.WriteString("\n")

	// Workflow status
	if m.workflow.Exists {
		b.WriteString(badgeOK.Render(tui.SymbolSuccess+" Rekey workflow active") + "\n")
		b.WriteString(dimStyle.Render("  New recipients are automatically re-keyed via GitHub Actions.") + "\n")
	} else {
		b.WriteString(warningStyle.Render(tui.SymbolWarning+" Rekey workflow not configured") + "\n")
		b.WriteString(dimStyle.Render("  Run: secrets:init-group <name> --force-gh") + "\n")
	}

	b.WriteString("\n")
	b.WriteString(helpStyle.Render("esc back  r refresh  q quit"))

	return tui.RenderFrame(b.String())
}

// --- Help view ---

func (m Model) viewHelp() string {
	var b strings.Builder

	b.WriteString(headerStyle.Render("Secrets Help"))
	b.WriteString("\n")

	sections := []struct {
		title string
		items []string
	}{
		{"Navigation", []string{
			"tab / shift+tab   Switch section",
			"↑ / ↓ / j / k     Navigate items",
			"enter             Select / drill in",
			"esc / backspace   Go back",
			"q / ctrl+c        Quit",
		}},
		{"Actions", []string{
			"r                 Refresh data",
			"?                 Toggle help",
		}},
		{"CLI Commands", []string{
			"secrets:set <key> --group <g> --value <v>   Set a secret",
			"secrets:get <key> --group <g>               Get a secret",
			"secrets:list [group]                        List secrets",
			"secrets:init-group <name>                   Initialize group",
			"secrets:init-group <name> --force-gh        Sync to GitHub",
			"secrets:show-keys                           Show key status",
		}},
		{"Key Naming", []string{
			"Rules: lowercase alphanumeric + hyphens only",
			"Valid: database-url, api-key-v2, my-secret",
			"Invalid: DATABASE_URL, /dev/key, my.secret",
		}},
		{"Team Onboarding", []string{
			"1. New member enters devshell (key auto-registered)",
			"2. Push the recipients/*.pub file",
			"3. GitHub Actions re-keys automatically",
			"4. Pull — secrets are now accessible",
		}},
	}

	for _, s := range sections {
		b.WriteString(sectionTitle.Render(s.title) + "\n")
		for _, item := range s.items {
			b.WriteString("  " + dimStyle.Render(item) + "\n")
		}
		b.WriteString("\n")
	}

	b.WriteString(helpStyle.Render("? close help  q quit"))

	return tui.RenderFrame(b.String())
}

// --- Utilities ---

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max-3] + "..."
}
