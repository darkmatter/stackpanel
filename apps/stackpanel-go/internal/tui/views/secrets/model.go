package secrets

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

// Package secrets provides the TUI view for browsing and inspecting SOPS-encrypted
// secrets. It communicates with the stackpanel agent API to list groups, recipients,
// and decrypt individual secret values on demand.

// --- Messages ---

type dataLoadedMsg struct {
	groups     map[string]groupData
	recipients []recipient
	workflow   workflowStatus
	err        error
}

type secretValueMsg struct {
	key   string
	group string
	value string
	err   error
}

type tickMsg time.Time

type returnMsg struct{}

// --- Data types ---

type groupData struct {
	Name        string
	Keys        []string
	PubKey      string
	Initialized bool
}

type recipient struct {
	Name      string `json:"name"`
	PublicKey string `json:"publicKey"`
}

type workflowStatus struct {
	Exists bool `json:"exists"`
}

// --- View states ---

type viewState int

const (
	viewDashboard viewState = iota
	viewGroupDetail
	viewSecretDetail
	viewRecipients
	viewHelp
)

// --- Sections in dashboard ---

type section int

const (
	sectionGroups section = iota
	sectionRecipients
	sectionSetup
)

// --- Model ---

// Model is the Bubble Tea model for the secrets dashboard. It supports
// drill-down navigation: dashboard → group detail → secret detail, with
// esc/backspace to go back. Secret values are decrypted lazily on demand.
type Model struct {
	// Data
	groups     map[string]groupData
	recipients []recipient
	workflow   workflowStatus
	loading    bool
	err        error

	// Navigation
	state         viewState
	activeSection section
	cursor        int
	selectedGroup string
	selectedKey   string

	// Secret value (when viewing a secret)
	secretValue   string
	secretErr     error
	loadingSecret bool

	// UI
	spinner   spinner.Model
	width     int
	height    int
	returnMsg tea.Msg

	// Agent
	agentURL   string
	agentToken string
}

// Option pattern
type Option func(*Model)

func WithReturnMsg(msg tea.Msg) Option {
	return func(m *Model) {
		m.returnMsg = msg
	}
}

// New creates a secrets Model. The agent URL defaults to localhost:21234 (the
// standard agent port for secrets), not the main agent port 9876. The agent
// token is read from STACKPANEL_AGENT_TOKEN for authenticated requests.
func New(opts ...Option) Model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = tui.SpinnerStyle

	agentURL := os.Getenv("STACKPANEL_AGENT_URL")
	if agentURL == "" {
		agentURL = "http://localhost:21234"
	}

	m := Model{
		spinner:    s,
		loading:    true,
		agentURL:   agentURL,
		agentToken: os.Getenv("STACKPANEL_AGENT_TOKEN"),
		groups:     make(map[string]groupData),
	}

	for _, opt := range opts {
		opt(&m)
	}

	return m
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		m.loadData(),
	)
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKey(msg)

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case dataLoadedMsg:
		m.loading = false
		if msg.err != nil {
			m.err = msg.err
		} else {
			m.groups = msg.groups
			m.recipients = msg.recipients
			m.workflow = msg.workflow
			m.err = nil
		}
		return m, nil

	case secretValueMsg:
		m.loadingSecret = false
		if msg.err != nil {
			m.secretErr = msg.err
		} else {
			m.secretValue = msg.value
			m.secretErr = nil
		}
		return m, nil

	case tickMsg:
		return m, tea.Tick(5*time.Second, func(t time.Time) tea.Msg {
			return tickMsg(t)
		})

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	}

	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch m.state {
	case viewDashboard:
		return m.handleDashboardKey(msg)
	case viewGroupDetail:
		return m.handleGroupDetailKey(msg)
	case viewSecretDetail:
		return m.handleSecretDetailKey(msg)
	case viewRecipients:
		return m.handleRecipientsKey(msg)
	case viewHelp:
		return m.handleHelpKey(msg)
	}
	return m, nil
}

func (m Model) handleDashboardKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "esc":
		if m.returnMsg != nil {
			return m, func() tea.Msg { return m.returnMsg }
		}
		return m, tea.Quit
	case "?":
		m.state = viewHelp
		return m, nil
	case "r":
		m.loading = true
		return m, m.loadData()
	case "tab":
		m.activeSection = (m.activeSection + 1) % 3
		m.cursor = 0
		return m, nil
	case "shift+tab":
		m.activeSection = (m.activeSection + 2) % 3
		m.cursor = 0
		return m, nil
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
		return m, nil
	case "down", "j":
		m.cursor = min(m.cursor+1, m.maxCursor()-1)
		return m, nil
	case "enter":
		return m.handleEnter()
	}
	return m, nil
}

func (m Model) handleEnter() (tea.Model, tea.Cmd) {
	switch m.activeSection {
	case sectionGroups:
		groupNames := m.sortedGroupNames()
		if m.cursor < len(groupNames) {
			m.selectedGroup = groupNames[m.cursor]
			m.state = viewGroupDetail
			m.cursor = 0
		}
	case sectionRecipients:
		m.state = viewRecipients
		m.cursor = 0
	}
	return m, nil
}

func (m Model) handleGroupDetailKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	group, ok := m.groups[m.selectedGroup]
	if !ok {
		m.state = viewDashboard
		return m, nil
	}

	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "esc", "backspace":
		m.state = viewDashboard
		m.cursor = 0
		m.secretValue = ""
		m.secretErr = nil
		return m, nil
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
		return m, nil
	case "down", "j":
		m.cursor = min(m.cursor+1, len(group.Keys)-1)
		return m, nil
	case "enter":
		if m.cursor < len(group.Keys) {
			m.selectedKey = group.Keys[m.cursor]
			m.state = viewSecretDetail
			m.loadingSecret = true
			m.secretValue = ""
			m.secretErr = nil
			return m, m.loadSecretValue(m.selectedGroup, m.selectedKey)
		}
	case "r":
		m.loading = true
		return m, m.loadData()
	case "?":
		m.state = viewHelp
		return m, nil
	}
	return m, nil
}

func (m Model) handleSecretDetailKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "esc", "backspace":
		m.state = viewGroupDetail
		m.secretValue = ""
		m.secretErr = nil
		return m, nil
	case "r":
		m.loadingSecret = true
		return m, m.loadSecretValue(m.selectedGroup, m.selectedKey)
	}
	return m, nil
}

func (m Model) handleRecipientsKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "esc", "backspace":
		m.state = viewDashboard
		m.cursor = 0
		return m, nil
	case "r":
		m.loading = true
		return m, m.loadData()
	}
	return m, nil
}

func (m Model) handleHelpKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "esc", "backspace", "?":
		m.state = viewDashboard
		return m, nil
	}
	return m, nil
}

// --- Data loading ---

func (m Model) loadData() tea.Cmd {
	return func() tea.Msg {
		groups := make(map[string]groupData)
		var recipients []recipient
		var workflow workflowStatus

		// Load groups + secrets
		groupResp, err := m.fetchAPI("/api/secrets/group/list")
		if err != nil {
			return dataLoadedMsg{err: fmt.Errorf("agent not reachable: %w", err)}
		}
		if groupMap, ok := groupResp["groups"].(map[string]interface{}); ok {
			for name, data := range groupMap {
				gd := groupData{Name: name, Initialized: true}
				if dataMap, ok := data.(map[string]interface{}); ok {
					if keys, ok := dataMap["keys"].([]interface{}); ok {
						for _, k := range keys {
							if s, ok := k.(string); ok {
								gd.Keys = append(gd.Keys, s)
							}
						}
					}
				}
				groups[name] = gd
			}
		}

		// Load recipients
		recipResp, err := m.fetchAPI("/api/secrets/recipients")
		if err == nil {
			if recipList, ok := recipResp["recipients"].([]interface{}); ok {
				for _, r := range recipList {
					b, _ := json.Marshal(r)
					var rec recipient
					json.Unmarshal(b, &rec)
					recipients = append(recipients, rec)
				}
			}
		}

		// Load workflow status
		wfResp, err := m.fetchAPI("/api/secrets/rekey-workflow")
		if err == nil {
			if exists, ok := wfResp["exists"].(bool); ok {
				workflow.Exists = exists
			}
		}

		return dataLoadedMsg{
			groups:     groups,
			recipients: recipients,
			workflow:   workflow,
		}
	}
}

func (m Model) loadSecretValue(group, key string) tea.Cmd {
	return func() tea.Msg {
		resp, err := m.fetchAPIPost("/api/secrets/group/read", map[string]string{
			"key":   key,
			"group": group,
		})
		if err != nil {
			return secretValueMsg{key: key, group: group, err: err}
		}
		value, _ := resp["value"].(string)
		return secretValueMsg{key: key, group: group, value: value}
	}
}

// fetchAPI makes a GET request to the agent and unwraps the {"data": ...} envelope.
// Returns the inner data map, or the raw response if no "data" key exists.
func (m Model) fetchAPI(path string) (map[string]interface{}, error) {
	url := strings.TrimRight(m.agentURL, "/") + path
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	if m.agentToken != "" {
		req.Header.Set("Authorization", "Bearer "+m.agentToken)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	if data, ok := result["data"].(map[string]interface{}); ok {
		return data, nil
	}
	return result, nil
}

func (m Model) fetchAPIPost(path string, body interface{}) (map[string]interface{}, error) {
	url := strings.TrimRight(m.agentURL, "/") + path
	bodyBytes, _ := json.Marshal(body)
	req, err := http.NewRequest("POST", url, strings.NewReader(string(bodyBytes)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if m.agentToken != "" {
		req.Header.Set("Authorization", "Bearer "+m.agentToken)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body2, _ := io.ReadAll(resp.Body)

	var result map[string]interface{}
	if err := json.Unmarshal(body2, &result); err != nil {
		return nil, err
	}

	if data, ok := result["data"].(map[string]interface{}); ok {
		return data, nil
	}
	return result, nil
}

// --- Helpers ---

// sortedGroupNames returns group names in alphabetical order for stable rendering.
// Uses bubble sort since group count is always small (typically 1-5).
func (m Model) sortedGroupNames() []string {
	names := make([]string, 0, len(m.groups))
	for name := range m.groups {
		names = append(names, name)
	}
	for i := 0; i < len(names); i++ {
		for j := i + 1; j < len(names); j++ {
			if names[i] > names[j] {
				names[i], names[j] = names[j], names[i]
			}
		}
	}
	return names
}

func (m Model) maxCursor() int {
	switch m.activeSection {
	case sectionGroups:
		n := len(m.groups)
		if n == 0 {
			return 1
		}
		return n
	case sectionRecipients:
		return 1
	case sectionSetup:
		return 1
	}
	return 1
}

func (m Model) totalSecrets() int {
	total := 0
	for _, g := range m.groups {
		total += len(g.Keys)
	}
	return total
}

// --- Entry point ---

func RunSecretsDashboard() error {
	m := New()
	p := tui.NewInteractiveProgram(m)
	_, err := p.Run()
	return err
}

// compile-time interface check
var _ tea.Model = Model{}
