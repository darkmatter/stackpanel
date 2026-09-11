package tui

import (
	"context"
	"fmt"
	"io"
	"strconv"
	"strings"
	"sync"

	tea "github.com/charmbracelet/bubbletea"
)

// SetupUI owns terminal input and rendering for the whole setup conversation.
type SetupUI struct {
	ctx     context.Context
	cancel  context.CancelFunc
	out     io.Writer
	program *tea.Program
	done    chan struct{}
	mu      sync.Mutex
}

type setupProgress string
type setupQuestion struct {
	prompt  string
	options []string
	answer  chan setupAnswer
}
type setupAnswer struct {
	text string
	err  error
}
type setupModel struct {
	progress string
	question *setupQuestion
	input    string
}

func (m setupModel) Init() tea.Cmd { return nil }
func (m setupModel) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := message.(type) {
	case setupProgress:
		m.progress = string(msg)
	case setupQuestion:
		m.question = &msg
		m.input = ""
	case tea.KeyMsg:
		if msg.String() == "ctrl+c" || msg.String() == "esc" {
			if m.question != nil {
				m.question.answer <- setupAnswer{err: context.Canceled}
				m.question = nil
			}
			return m, tea.Quit
		}
		if m.question == nil {
			return m, nil
		}
		switch msg.Type {
		case tea.KeyEnter:
			m.question.answer <- setupAnswer{text: m.input}
			m.question = nil
			m.input = ""
		case tea.KeyBackspace, tea.KeyDelete:
			runes := []rune(m.input)
			if len(runes) > 0 {
				m.input = string(runes[:len(runes)-1])
			}
		case tea.KeyRunes:
			m.input += string(msg.Runes)
		case tea.KeySpace:
			m.input += " "
		}
	}
	return m, nil
}
func (m setupModel) View() string {
	s := "Stackpanel setup\n\n" + m.progress + "\n"
	if m.question != nil {
		s += "\n" + setupDisplayText(m.question.prompt) + "\n"
		for i, option := range m.question.options {
			s += fmt.Sprintf("  %d. %s\n", i+1, setupDisplayText(option))
		}
		s += "\n> " + setupDisplayText(m.input) + "\n"
	}
	return s + "\nEsc / Ctrl+C to cancel\n"
}

func NewSetupUI(ctx context.Context, interactive bool, out io.Writer) *SetupUI {
	ctx, cancel := context.WithCancel(ctx)
	u := &SetupUI{ctx: ctx, cancel: cancel, out: out, done: make(chan struct{})}
	if interactive {
		u.program = tea.NewProgram(setupModel{}, tea.WithOutput(out), tea.WithContext(ctx))
		go func() { _, _ = u.program.Run(); cancel(); close(u.done) }()
	} else {
		close(u.done)
	}
	return u
}
func (u *SetupUI) Context() context.Context { return u.ctx }
func (u *SetupUI) Close() {
	defer u.cancel()
	if u.program != nil {
		u.program.Quit()
		<-u.done
	}
}
func setupDisplayText(text string) string {
	// Do not render agent-supplied terminal control sequences.
	return strings.Map(func(r rune) rune {
		if r < 32 && r != '\n' && r != '\t' || r == 127 {
			return -1
		}
		return r
	}, text)
}
func (u *SetupUI) Progress(text string) {
	text = setupDisplayText(text)
	if u.program != nil {
		u.program.Send(setupProgress(text))
		return
	}
	u.mu.Lock()
	defer u.mu.Unlock()
	fmt.Fprintln(u.out, text)
}
func (u *SetupUI) Ask(prompt, kind string, options, defaults []string, required bool) ([]string, error) {
	if u.program == nil {
		if len(defaults) > 0 {
			return defaults, nil
		}
		if required {
			return nil, fmt.Errorf("interactive answer required: %s; rerun in a terminal without --yes/--non-interactive", prompt)
		}
		return nil, nil
	}
	for {
		label := prompt
		if len(defaults) > 0 {
			label += " (Enter for " + strings.Join(defaults, ", ") + ")"
		}
		if kind == "multi" {
			label += " (comma-separated numbers)"
		}
		answer := make(chan setupAnswer, 1)
		u.program.Send(setupQuestion{prompt: label, options: options, answer: answer})
		var a setupAnswer
		select {
		case a = <-answer:
		case <-u.ctx.Done():
			return nil, u.ctx.Err()
		case <-u.done:
			return nil, context.Canceled
		}
		if a.err != nil {
			return nil, a.err
		}
		text := strings.TrimSpace(a.text)
		if text == "" {
			if len(defaults) > 0 {
				return defaults, nil
			}
			if !required {
				return nil, nil
			}
			continue
		}
		if kind == "text" {
			return []string{text}, nil
		}
		var values []string
		valid := true
		for _, part := range strings.Split(text, ",") {
			i, err := strconv.Atoi(strings.TrimSpace(part))
			if err != nil || i < 1 || i > len(options) {
				valid = false
				break
			}
			values = append(values, options[i-1])
		}
		if valid && (kind == "multi" || len(values) == 1) {
			return values, nil
		}
		u.Progress("Choose a listed option by number.")
	}
}
func (u *SetupUI) ReviewPlan(summary string) (string, error) {
	if u.program != nil {
		u.program.Println(setupDisplayText(summary))
		u.Progress("Review the plan above.")
	} else {
		u.Progress(summary)
	}
	values, err := u.Ask("Apply this plan?", "single", []string{"Apply", "Revise", "Cancel"}, []string{"Apply"}, true)
	if err != nil {
		return "", err
	}
	return values[0], nil
}
func (u *SetupUI) ShowResult(result string) { u.Close(); fmt.Fprintln(u.out, result) }
