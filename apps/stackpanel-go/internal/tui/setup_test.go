package tui

import (
	"bytes"
	"context"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

func setupUpdate(m setupModel, messages ...tea.Msg) setupModel {
	for _, msg := range messages {
		updated, _ := m.Update(msg)
		m = updated.(setupModel)
	}
	return m
}

func TestSetupKeyboardChoices(t *testing.T) {
	answer := make(chan setupAnswer, 1)
	m := setupUpdate(newSetupModel(), setupQuestion{kind: "single", options: []string{"Apply", "Revise", "Cancel"}, defaults: []string{"Apply"}, answer: answer})
	setupUpdate(m, tea.KeyMsg{Type: tea.KeyDown}, tea.KeyMsg{Type: tea.KeyEnter})
	if got := <-answer; len(got.values) != 1 || got.values[0] != "Revise" {
		t.Fatalf("arrow key did not select Revise: %+v", got)
	}

	m = setupUpdate(newSetupModel(), setupQuestion{kind: "multi", options: []string{"Postgres", "Redis"}, defaults: []string{"Postgres"}, answer: answer})
	// Deselect the default, select the second item, and submit in option order.
	setupUpdate(m, tea.KeyMsg{Type: tea.KeySpace}, tea.KeyMsg{Type: tea.KeyDown}, tea.KeyMsg{Type: tea.KeySpace}, tea.KeyMsg{Type: tea.KeyEnter})
	if got := <-answer; len(got.values) != 1 || got.values[0] != "Redis" {
		t.Fatalf("checkbox selection was not preserved: %+v", got)
	}
}

func TestSetupTextEditingAndRequiredAnswers(t *testing.T) {
	answer := make(chan setupAnswer, 1)
	m := setupUpdate(newSetupModel(), setupQuestion{kind: "text", required: true, answer: answer}, tea.KeyMsg{Type: tea.KeyEnter})
	if len(answer) != 0 || m.validation == "" {
		t.Fatal("empty required answer was submitted without validation")
	}
	m = setupUpdate(m, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("G界")}, tea.KeyMsg{Type: tea.KeyLeft}, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("o")}, tea.KeyMsg{Type: tea.KeyDelete}, tea.KeyMsg{Type: tea.KeyEnter})
	if got := <-answer; len(got.values) != 1 || got.values[0] != "Go" {
		t.Fatalf("editing at the cursor failed: %+v", got)
	}
	m = setupUpdate(m, setupQuestion{kind: "multi", required: true, options: []string{"Go"}, answer: answer}, tea.KeyMsg{Type: tea.KeyEnter})
	if len(answer) != 0 || !strings.Contains(m.validation, "Space") {
		t.Fatal("required selection silently accepted no options")
	}
}

func TestSetupPlanScrollKeepsApprovalVisible(t *testing.T) {
	m := setupUpdate(newSetupModel(), tea.WindowSizeMsg{Width: 80, Height: 24}, setupDocument(strings.Repeat("A planned file\n", 60)), setupQuestion{prompt: "Apply this plan?", kind: "single", options: []string{"Apply", "Revise", "Cancel"}, answer: make(chan setupAnswer, 1)})
	m = setupUpdate(m, tea.KeyMsg{Type: tea.KeyPgDown})
	if m.viewport.YOffset == 0 || !strings.Contains(m.View(), "Apply this plan?") {
		t.Fatal("long plan did not scroll independently of approval controls")
	}
	for _, size := range []tea.WindowSizeMsg{{Width: 80, Height: 24}, {Width: 42, Height: 24}} {
		m = setupUpdate(m, size)
		if w, h := lipgloss.Size(m.View()); w > size.Width || h > size.Height {
			t.Fatalf("UI overflows %dx%d terminal: %dx%d", size.Width, size.Height, w, h)
		}
	}
}

func TestSetupDetailsAndCancellation(t *testing.T) {
	answer := make(chan setupAnswer, 1)
	m := setupUpdate(newSetupModel(), setupProgress("Preparing files"), setupActivity("a long shell command"))
	if strings.Contains(m.View(), "a long shell command") {
		t.Fatal("tool detail replaced the quiet progress view")
	}
	m = setupUpdate(m, tea.KeyMsg{Type: tea.KeyCtrlD})
	if !strings.Contains(m.View(), "a long shell command") {
		t.Fatal("details cannot be expanded")
	}
	m = setupUpdate(m, setupQuestion{kind: "text", answer: answer}, tea.KeyMsg{Type: tea.KeyEsc})
	if got := <-answer; got.err != context.Canceled || m.View() != "" {
		t.Fatal("cancel did not unblock the question and clear the UI")
	}
}

func TestSetupPlainOutputAndControlSequences(t *testing.T) {
	var out bytes.Buffer
	ui := NewSetupUI(context.Background(), false, &out)
	defer ui.Close()
	ui.Stage(SetupApply, "Creating \x1b[31mfiles\x1b[0m")
	ui.Activity("\x1b]52;c;payload\aSafe\x00")
	ui.ShowResult("Verified")
	if out.String() != "Creating files\nSafe\nVerified\n" {
		t.Fatalf("redirected output contains styling or controls: %q", out.String())
	}
	if _, err := ui.Ask("Required", "text", nil, nil, true); err == nil {
		t.Fatal("noninteractive required input silently accepted")
	}
}
