package setupagent

import (
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
)

type Phase string

const (
	Inspection Phase = "inspection"
	Setup      Phase = "setup"
	Repair     Phase = "repair"
)

type SetupRequest struct {
	Root            string `json:"root"`
	StackExecutable string `json:"stackExecutable"`
	FlakeRef        string `json:"flakeRef"`
	// InspectionRef optionally identifies an immutable source for scaffolding.
	// FlakeRef is the durable reference to persist in the target flake.
	InspectionRef string     `json:"inspectionRef"`
	Template      string     `json:"template"`
	Context       string     `json:"context"`
	Constraints   string     `json:"constraints"`
	Mode          string     `json:"mode"`
	Answers       []Answer   `json:"answers,omitempty"`
	Resuming      bool       `json:"resuming"`
	PreviousError string     `json:"previousError,omitempty"`
	Conversation  []Exchange `json:"-"`
}

type Plan struct {
	Summary      string                 `json:"summary"`
	Expectations reconcile.Expectations `json:"expectations"`
	Services     []string               `json:"services,omitempty"`
	Prepare      []PrepareCommand       `json:"prepare,omitempty"`
}

// PrepareCommand is a host step the user approves with the plan, such as a
// dependency install or lockfile generation. Setup runs it before doctor.
type PrepareCommand struct {
	ID   string   `json:"id"`
	Dir  string   `json:"dir"`
	Argv []string `json:"argv"`
}

type Question struct {
	ID       string   `json:"id"`
	Prompt   string   `json:"prompt"`
	Kind     string   `json:"kind"` // text, single, multi
	Options  []string `json:"options,omitempty"`
	Required bool     `json:"required"`
	Default  []string `json:"default,omitempty"`
}

type Answer struct {
	ID     string   `json:"id"`
	Values []string `json:"values"`
}

type Exchange struct {
	Question Question `json:"question"`
	Answer   Answer   `json:"answer"`
}

// Reply statuses. Only inspection returns a plan; write phases return complete.
// Any phase may ask questions or report that it is blocked.
const (
	StatusNeedsInput = "needs_input"
	StatusPlan       = "plan"
	StatusComplete   = "complete"
	StatusBlocked    = "blocked"
)

type Reply struct {
	Status    string     `json:"status"`
	Summary   string     `json:"summary,omitempty"`
	Questions []Question `json:"questions,omitempty"`
	Plan      *Plan      `json:"plan,omitempty"`
}

// ParseReply reads an agent's final message. Agents wrap JSON in prose or
// Markdown fences, stop a few characters early, and add fields, so the reply
// is the first usable JSON object in the message, and entries the host cannot
// use are dropped instead of rejecting the reply.
func ParseReply(message string) (*Reply, error) {
	reply := decodeReply(message)
	if reply == nil {
		return nil, errors.New("reply contains no setup JSON object")
	}
	reply.Summary = strings.TrimSpace(reply.Summary)
	switch reply.Status {
	case StatusNeedsInput:
		reply.Questions = normalizeQuestions(reply.Questions)
		if len(reply.Questions) == 0 {
			return nil, errors.New("reply asks for input but has no usable questions")
		}
	case StatusPlan:
		if reply.Plan == nil {
			reply.Plan = &Plan{}
		}
		if strings.TrimSpace(reply.Plan.Summary) == "" {
			reply.Plan.Summary = reply.Summary
		}
		NormalizePlan(reply.Plan)
	}
	return reply, nil
}

// replyCandidate also accepts a bare plan object, which some agents return
// instead of {"status":"plan","plan":{...}}.
type replyCandidate struct {
	Reply
	Expectations *reconcile.Expectations `json:"expectations"`
	Services     []string                `json:"services"`
	Prepare      []PrepareCommand        `json:"prepare"`
}

func decodeReply(message string) *Reply {
	// Each attempt decodes from one opening brace; a bound keeps a long message
	// full of braces from taking quadratic time.
	for start, attempts := strings.IndexByte(message, '{'), 0; start >= 0 && attempts < 64; attempts++ {
		text := message[start:]
		for _, attempt := range []string{text, closeJSON(text)} {
			// A mistyped value is not decoded partially: "exists":"yes"
			// would become an assertion that the option is absent.
			var candidate replyCandidate
			if json.NewDecoder(strings.NewReader(attempt)).Decode(&candidate) == nil {
				if reply := candidate.reply(); reply != nil {
					return reply
				}
			}
		}
		next := strings.IndexByte(message[start+1:], '{')
		if next < 0 {
			break
		}
		start += next + 1
	}
	return nil
}

func (c *replyCandidate) reply() *Reply {
	reply := c.Reply
	reply.Status = normalizeStatus(reply.Status)
	if reply.Status != "" {
		return &reply
	}
	switch {
	case reply.Plan != nil:
		reply.Status = StatusPlan
	case c.Expectations != nil:
		reply.Status = StatusPlan
		reply.Plan = &Plan{Summary: reply.Summary, Expectations: *c.Expectations, Services: c.Services, Prepare: c.Prepare}
	case len(reply.Questions) > 0:
		reply.Status = StatusNeedsInput
	case strings.TrimSpace(reply.Summary) != "":
		reply.Status = StatusComplete
	default:
		return nil // Some other JSON object, such as an example in prose.
	}
	return &reply
}

func normalizeStatus(status string) string {
	switch strings.NewReplacer("-", "_", " ", "_").Replace(strings.ToLower(strings.TrimSpace(status))) {
	case "needs_input", "input", "question", "questions":
		return StatusNeedsInput
	case "plan":
		return StatusPlan
	case "complete", "completed", "done", "success":
		return StatusComplete
	case "blocked", "error", "failed":
		return StatusBlocked
	default:
		return ""
	}
}

// closeJSON adds the quote, brackets, and braces missing from a JSON value that
// was cut off, or trims anything after a complete value.
func closeJSON(text string) string {
	var closers []byte
	inString, escaped := false, false
	for i := 0; i < len(text); i++ {
		c := text[i]
		switch {
		case escaped:
			escaped = false
		case inString:
			if c == '\\' {
				escaped = true
			} else if c == '"' {
				inString = false
			}
		case c == '"':
			inString = true
		case c == '{':
			closers = append(closers, '}')
		case c == '[':
			closers = append(closers, ']')
		case c == '}' || c == ']':
			if len(closers) > 0 {
				closers = closers[:len(closers)-1]
			}
			if len(closers) == 0 {
				return text[:i+1]
			}
		}
	}
	if inString {
		text += `"`
	} else {
		text = strings.TrimRight(text, " \t\r\n,")
	}
	for i := len(closers) - 1; i >= 0; i-- {
		text += string(closers[i])
	}
	return text
}

func normalizeQuestions(questions []Question) []Question {
	var out []Question
	ids := map[string]bool{}
	for i, q := range questions {
		q.Prompt = strings.TrimSpace(q.Prompt)
		if q.Prompt == "" {
			continue
		}
		q.ID = uniqueID(strings.TrimSpace(q.ID), fmt.Sprintf("question-%d", i+1), ids)
		q.Options = uniqueStrings(q.Options)
		kind := strings.ToLower(strings.TrimSpace(q.Kind))
		switch {
		case len(q.Options) == 0 || kind == "text":
			q.Kind = "text"
		case kind == "multi" || kind == "multiple" || kind == "multiselect":
			q.Kind = "multi"
		default:
			q.Kind = "single"
		}
		defaults := uniqueStrings(q.Default)
		if q.Kind != "text" {
			defaults = filterStrings(defaults, q.Options)
		}
		if q.Kind == "single" && len(defaults) == 0 {
			defaults = q.Options[:1]
		}
		if q.Kind != "multi" && len(defaults) > 1 {
			defaults = defaults[:1]
		}
		q.Default = defaults
		out = append(out, q)
	}
	return out
}

// NormalizePlan drops plan entries the host cannot run or check, so a plan
// with a bad entry is still usable.
func NormalizePlan(plan *Plan) {
	plan.Summary = strings.TrimSpace(plan.Summary)
	plan.Services = uniqueStrings(plan.Services)
	var prepare []PrepareCommand
	ids := map[string]bool{}
	for i, c := range plan.Prepare {
		dir, ok := localPath(c.Dir)
		if !ok || len(c.Argv) == 0 || strings.TrimSpace(c.Argv[0]) == "" {
			continue
		}
		c.Dir = dir
		c.ID = uniqueID(strings.TrimSpace(c.ID), fmt.Sprintf("prepare-%d", i+1), ids)
		prepare = append(prepare, c)
	}
	plan.Prepare = prepare
	plan.Expectations = normalizeExpectations(plan.Expectations)
}

// Required check IDs are dropped: doctor already runs every enabled check, and
// an ID the agent guessed could only fail.
func normalizeExpectations(e reconcile.Expectations) reconcile.Expectations {
	out := reconcile.Expectations{Version: 1}
	paths := map[string]bool{}
	for _, a := range e.Config {
		if a.Exists != nil && !*a.Exists {
			a.Equals = nil // An absent option has no value to compare.
		}
		key := strings.Join(a.Path, "\x00")
		if (a.Exists == nil && len(a.Equals) == 0) || !assertablePath(a.Path) || paths[key] {
			continue
		}
		paths[key] = true
		out.Config = append(out.Config, a)
	}
	files := map[string]bool{}
	for _, file := range e.Files {
		if file, ok := localPath(file); ok && file != "." && !files[file] {
			files[file] = true
			out.Files = append(out.Files, file)
		}
	}
	ids := map[string]bool{}
	for i, c := range e.Commands {
		dir, ok := localPath(c.Dir)
		if !ok || len(c.Argv) == 0 || strings.TrimSpace(c.Argv[0]) == "" {
			continue
		}
		c.Dir = dir
		if c.Scope != "repo" {
			c.Scope = "build"
		}
		c.ID = uniqueID(strings.TrimSpace(c.ID), fmt.Sprintf("command-%d", i+1), ids)
		out.Commands = append(out.Commands, c)
	}
	return out
}

// Attributes named bun are left out of the evaluated configuration, so an
// assertion about one could never pass.
func assertablePath(path []string) bool {
	for _, part := range path {
		if strings.TrimSpace(part) == "" || part == "bun" {
			return false
		}
	}
	return len(path) > 0
}

// localPath cleans a repository-relative path; empty means the repository root.
func localPath(path string) (string, bool) {
	path = filepath.Clean(strings.TrimSpace(path))
	return path, filepath.IsLocal(path)
}

func uniqueID(id, fallback string, seen map[string]bool) string {
	if id == "" {
		id = fallback
	}
	for base, n := id, 2; seen[id]; n++ {
		id = fmt.Sprintf("%s-%d", base, n)
	}
	seen[id] = true
	return id
}

func uniqueStrings(values []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, value := range values {
		if value = strings.TrimSpace(value); value != "" && !seen[value] {
			seen[value] = true
			out = append(out, value)
		}
	}
	return out
}

func filterStrings(values, allowed []string) []string {
	var out []string
	for _, value := range values {
		for _, option := range allowed {
			if value == option {
				out = append(out, value)
				break
			}
		}
	}
	return out
}

// BuildPrompt describes one agent turn. The agent edits repository files; the
// host runs Nix, preparation commands, and doctor afterwards.
func BuildPrompt(req SetupRequest, phase Phase, plan *Plan, failure string) string {
	var p strings.Builder
	fmt.Fprintf(&p, `Stackpanel onboarding · phase %s.
Setup mode: %s. Repository: %q.

The user ran "stack setup" and asked you to set up Stackpanel in this repository.
You may create and change any repository files the setup needs, including
existing ones; the user reviews the result in Git. Do not commit, push, stage
files, or read secrets.

How Stackpanel is configured:
- .stack/config.nix returns the Stackpanel configuration directly, without an
  outer "stackpanel" attribute, and may take { pkgs, ... }: to use packages.
  The option schema below lists the supported option paths, relative to that
  file (replace <name> with the app or entry key). Use only those options.
- flake.nix sets inputs.stackpanel.url = %q. A new flake makes nixpkgs and
  flake-parts follow stackpanel/nixpkgs and stackpanel/flake-parts; keep any
  pins an existing flake already has.
- Template files are a starting point: keep the apps, modules, services, and
  secrets this repository needs, and drop the examples it does not.
- .stack/gen/ and packages/gen/env/src/ are generated; do not edit them.

After your turn the host locks flake inputs, enters the devshell, runs the
plan's prepare commands, and runs stack doctor. Do not run nix, direnv, or
stack yourself, and do not edit flake.lock.

Template %q, addons, and option schema (JSON):
%s

Choices the user passed as flags (JSON): %s
`, phase, req.Mode, req.Root, req.FlakeRef, req.Template, req.Context, req.Constraints)
	if len(req.Answers) > 0 {
		answers, _ := json.Marshal(req.Answers)
		fmt.Fprintf(&p, "Answers so far (JSON; an empty answer leaves the choice to you): %s\n", answers)
	}
	if len(req.Conversation) > 0 {
		conversation, _ := json.Marshal(req.Conversation)
		fmt.Fprintf(&p, "Questions asked so far, with answers (JSON): %s\n", conversation)
	}
	if req.Resuming {
		p.WriteString("\nResuming saved onboarding: earlier turns may already have made some of these changes. Check the current files and continue from them; do not ask answered questions again.\n")
		if req.PreviousError != "" {
			fmt.Fprintf(&p, "The previous run stopped with: %s\n", req.PreviousError)
		}
	}
	if phase == Inspection {
		p.WriteString(inspectionInstructions)
		return p.String()
	}
	p.WriteString("\nThis turn: make the changes in the accepted plan below. Stackpanel has already written any template files that were missing.\n")
	if plan != nil {
		encoded, _ := json.MarshalIndent(plan, "", "  ")
		fmt.Fprintf(&p, "\nAccepted plan (JSON):\n%s\n", encoded)
	}
	if phase == Repair {
		fmt.Fprintf(&p, "\nThis is the repair turn. The host checked the changes and found these problems; fix them:\n%s\n", failure)
	}
	p.WriteString(`
When you are done, reply {"status":"complete","summary":"what you changed"}.
If only the user can decide something, reply with questions instead:
{"status":"needs_input","questions":[{"id":"name","prompt":"Project name?","kind":"text"}]}
If you cannot finish, reply {"status":"blocked","summary":"why"}; the host still
checks the changes you made.
`)
	return p.String()
}

const inspectionInstructions = `
This turn: inspect the repository and propose a plan. Do not change files yet.
Read the project manifests, workspace layout, development commands, flakes, and
services. Read files directly rather than through shell redirection or
heredocs: the inspection sandbox is read-only, including /tmp.

For a new repository, first ask what the user wants to build. Ask about any
choice that is the user's to make instead of guessing, by replying:
{"status":"needs_input","questions":[{"id":"framework","prompt":"Which framework?","kind":"single","options":["Bun","Go"],"default":["Bun"]}]}
Question kinds are text, single, and multi. Never ask for credentials or secrets.

When you know what to do, reply with the plan:
{"status":"plan","plan":{"summary":"...","services":[],"prepare":[{"id":"deps","dir":".","argv":["bun","install"]}],"expectations":{"config":[{"path":["apps","web"],"exists":true},{"path":["modules","go","enable"],"equals":true}],"files":["apps/web/src/index.ts"],"commands":[{"id":"web-test","scope":"build","dir":"apps/web","argv":["bun","test"]}]}}}

- summary: the changes you will make and the files they touch.
- services: local services Stackpanel should start, from the supported list.
- prepare: commands the host runs in the devshell, in order, before checking,
  such as dependency installs and lockfile generation. Do not write the files
  they produce yourself. An app with bun.enable is built from bun.nix: plan
  bun install and then bun2nix -o bun.nix in the directory with bun.lock, and
  set apps.<name>.bun.generateFiles = false for an app whose package.json you
  write.
- expectations: what doctor checks afterwards. config lists settings the
  evaluated configuration must have, such as each app (exists) and each enabled
  module (enable equals true); each entry has exists or equals. files lists
  files you will create. commands lists build or test commands that show the
  setup works, as argv arrays without shell syntax.
`
