package tui

import (
	"context"
	"fmt"
	"io"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
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

type SetupStage int

const (
	SetupInspect SetupStage = iota
	SetupPlan
	SetupApply
	SetupVerify
	SetupConnect
)

var setupStages = []string{"Discover", "Plan", "Set up", "Doctor", "Studio"}

type setupProgress string
type setupActivity string
type setupDocument string
type setupFinished string
type setupVerified string
type setupClosed struct{}
type setupStage struct {
	stage SetupStage
	text  string
}
type setupIdentity struct{ root, agent string }
type setupQuestion struct {
	prompt   string
	kind     string
	options  []string
	defaults []string
	required bool
	answer   chan setupAnswer
}
type setupAnswer struct {
	values []string
	err    error
}
type setupModel struct {
	width, height int
	identity      setupIdentity
	stage         SetupStage
	progress      string
	activity      []string
	details       bool
	document      string
	question      *setupQuestion
	cursor        int
	selected      map[int]bool
	validation    string
	input         textinput.Model
	viewport      viewport.Model
	spinner       spinner.Model
	started       time.Time
	quitting      bool
	result        string
	verified      []string
}

func newSetupModel() setupModel {
	input := textinput.New()
	input.Prompt = "› "
	input.PromptStyle = SpinnerStyle
	input.CharLimit = 0
	s := spinner.New(spinner.WithSpinner(spinner.Dot), spinner.WithStyle(SpinnerStyle))
	return setupModel{width: 80, height: 24, input: input, spinner: s,
		viewport: viewport.New(70, 8), started: time.Now()}
}

func (m setupModel) Init() tea.Cmd { return m.spinner.Tick }
func (m setupModel) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	switch msg := message.(type) {
	case setupVerified:
		m.verified = append(m.verified, string(msg))
	case setupFinished:
		m.result = string(msg)
		return m, tea.Quit
	case setupClosed:
		m.quitting = true
		return m, tea.Quit
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case setupIdentity:
		m.identity = msg
	case setupStage:
		m.stage, m.progress = msg.stage, msg.text
		m.document = ""
		m.viewport.GotoTop()
	case setupProgress:
		m.progress = string(msg)
	case setupActivity:
		m.activity = append(m.activity, string(msg))
		if len(m.activity) > 40 {
			m.activity = m.activity[len(m.activity)-40:]
		}
	case setupDocument:
		m.document = string(msg)
		m.viewport.GotoTop()
	case setupQuestion:
		m.question, m.cursor, m.validation = &msg, 0, ""
		m.selected = make(map[int]bool)
		m.input.Reset()
		m.input.Placeholder = "Type your answer…"
		for i, option := range msg.options {
			if indexOf(msg.defaults, option) >= 0 {
				m.selected[i] = true
				m.cursor = i
			}
		}
		if msg.kind == "text" {
			if len(msg.defaults) > 0 {
				m.input.Placeholder = setupDisplayText(msg.defaults[0])
			}
			cmd = m.input.Focus()
		}
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc":
			if m.question != nil {
				m.question.answer <- setupAnswer{err: context.Canceled}
				m.question = nil
			}
			m.quitting = true
			return m, tea.Quit
		case "ctrl+d":
			m.details = !m.details
			m.viewport.GotoTop()
		case "pgup", "pgdown":
			m.viewport, cmd = m.viewport.Update(msg)
		default:
			if m.question == nil {
				m.viewport, cmd = m.viewport.Update(msg)
				break
			}
			if msg.Type == tea.KeyEnter {
				m.submit()
			} else if m.question.kind == "text" {
				m.input, cmd = m.input.Update(msg)
				m.validation = ""
			} else {
				switch msg.String() {
				case "up", "k":
					m.cursor = max(0, m.cursor-1)
				case "down", "j":
					m.cursor = min(len(m.question.options)-1, m.cursor+1)
				case " ":
					if m.question.kind == "multi" {
						m.selected[m.cursor] = !m.selected[m.cursor]
					}
				}
				m.validation = ""
			}
		}
	case spinner.TickMsg:
		m.spinner, cmd = m.spinner.Update(msg)
	default:
		if m.question != nil && m.question.kind == "text" {
			m.input, cmd = m.input.Update(message)
		}
	}
	m.render() // Keep viewport dimensions/content current for the next key event.
	return m, cmd
}

func (m *setupModel) submit() {
	q := m.question
	var values []string
	switch q.kind {
	case "text":
		if text := strings.TrimSpace(m.input.Value()); text != "" {
			values = []string{text}
		} else {
			values = q.defaults
		}
	case "multi":
		for i, option := range q.options {
			if m.selected[i] {
				values = append(values, option)
			}
		}
	default:
		if len(q.options) > 0 {
			values = []string{q.options[m.cursor]}
		}
	}
	if q.required && len(values) == 0 {
		m.validation = "Please enter an answer."
		if q.kind != "text" {
			m.validation = "Select at least one option with Space."
		}
		return
	}
	q.answer <- setupAnswer{values: values}
	m.question, m.document = nil, ""
	m.input.Blur()
	m.viewport.GotoTop()
}

func NewSetupUI(ctx context.Context, interactive bool, out io.Writer) *SetupUI {
	ctx, cancel := context.WithCancel(ctx)
	u := &SetupUI{ctx: ctx, cancel: cancel, out: out, done: make(chan struct{})}
	if interactive {
		u.program = tea.NewProgram(newSetupModel(), tea.WithOutput(out), tea.WithContext(ctx))
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
		u.program.Send(setupClosed{})
		<-u.done
	}
}
func setupDisplayText(text string) string {
	// Strip whole escape sequences, including OSC links, before filtering other
	// controls. Removing just ESC would leave raw [31m-style fragments visible.
	return strings.Map(func(r rune) rune {
		if unicode.IsControl(r) && r != '\n' && r != '\t' {
			return -1
		}
		return r
	}, ansi.Strip(text))
}
func (u *SetupUI) Identify(root, agent string) {
	if u.program != nil {
		u.program.Send(setupIdentity{setupDisplayText(root), setupDisplayText(agent)})
	}
}
func (u *SetupUI) Stage(stage SetupStage, text string) {
	if u.program != nil {
		u.program.Send(setupStage{stage, setupDisplayText(text)})
	} else {
		u.Progress(text)
	}
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
func (u *SetupUI) Activity(text string) {
	if u.program != nil {
		u.program.Send(setupActivity(ansi.Truncate(setupDisplayText(text), 4000, "…")))
	} else {
		u.Progress(text)
	}
}
func (u *SetupUI) Ask(prompt, kind string, options, defaults []string, required bool) ([]string, error) {
	if u.program == nil {
		if len(defaults) > 0 {
			return defaults, nil
		}
		if required {
			return nil, fmt.Errorf("interactive answer required: %s; rerun in a terminal without --yes/--non-interactive/--no-tui/--daemon", prompt)
		}
		return nil, nil
	}
	answer := make(chan setupAnswer, 1)
	u.program.Send(setupQuestion{prompt: prompt, kind: kind, options: options, defaults: defaults, required: required, answer: answer})
	select {
	case a := <-answer:
		return a.values, a.err
	case <-u.ctx.Done():
		return nil, u.ctx.Err()
	case <-u.done:
		return nil, context.Canceled
	}
}
func (u *SetupUI) ReviewPlan(summary string) (string, error) {
	u.Stage(SetupPlan, "Review your onboarding plan")
	if u.program != nil {
		u.program.Send(setupDocument(setupDisplayText(summary)))
	} else {
		u.Progress(summary)
	}
	values, err := u.Ask("Apply this plan?", "single", []string{"Apply", "Revise", "Cancel"}, []string{"Apply"}, true)
	if err != nil {
		return "", err
	}
	return values[0], nil
}
func (u *SetupUI) Verified(text string) {
	if u.program != nil {
		u.program.Send(setupVerified(setupDisplayText(text)))
	} else {
		u.Progress(text)
	}
}
func (u *SetupUI) ShowResult(result string) {
	result = setupDisplayText(result)
	if u.program != nil {
		u.program.Send(setupFinished(result))
		<-u.done
	} else {
		fmt.Fprintln(u.out, result)
	}
}
