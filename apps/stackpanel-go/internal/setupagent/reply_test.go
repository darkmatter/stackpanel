package setupagent

import (
	"strings"
	"testing"
)

func TestParseReplyFindsTheReplyInWhateverTheAgentSent(t *testing.T) {
	plan := `{"status":"plan","plan":` + validPlan + `}`
	for _, tt := range []struct {
		name, message, status, summary string
	}{
		{"exact", plan, StatusPlan, "Add web app"},
		{"fenced with prose", "Here is the plan:\n```json\n" + plan + "\n```\nLet me know.", StatusPlan, "Add web app"},
		{"missing final braces", strings.TrimSuffix(plan, "}}"), StatusPlan, "Add web app"},
		{"cut off in a string", `{"status":"complete","summary":"Configured w`, StatusComplete, "Configured w"},
		{"unknown fields", `{"status":"complete","summary":"Done","confidence":0.9}`, StatusComplete, "Done"},
		{"bare plan", validPlan, StatusPlan, "Add web app"},
		{"status synonym", `{"status":"done","summary":"Done"}`, StatusComplete, "Done"},
		{"example before reply", `Assertions look like {"path":["apps"]}. ` + complete, StatusComplete, "Configured web"},
		{"blocked", `{"status":"blocked","summary":"No access"}`, StatusBlocked, "No access"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			reply, err := ParseReply(tt.message)
			if err != nil {
				t.Fatal(err)
			}
			summary := reply.Summary
			if reply.Plan != nil {
				summary = reply.Plan.Summary
			}
			if reply.Status != tt.status || summary != tt.summary {
				t.Fatalf("reply = %+v", reply)
			}
		})
	}
	for _, message := range []string{"", "I finished the setup.", `{"path":["apps"]}`, `{"status":"needs_input","questions":[{"prompt":" "}]}`,
		strings.Replace(plan, `"exists":true`, `"exists":"yes"`, 1)} {
		if _, err := ParseReply(message); err == nil {
			t.Fatalf("accepted a reply without usable content: %q", message)
		}
	}
}

func TestParseReplyKeepsTheUsableParts(t *testing.T) {
	reply, err := ParseReply(`{"status":"needs_input","questions":[
		{"prompt":"Name?","kind":"text","required":true},
		{"id":"db","prompt":"Database?","kind":"single","options":["postgres","sqlite","postgres"],"default":["mysql"]},
		{"id":"db","prompt":"Editors?","kind":"multiselect","options":["zed","vscode"],"default":["zed","vim"]},
		{"id":"tone","prompt":"Tone?","kind":"single"},
		{"id":"empty","prompt":""}]}`)
	if err != nil {
		t.Fatal(err)
	}
	q := reply.Questions
	if len(q) != 4 || q[0].ID != "question-1" || q[0].Kind != "text" ||
		q[1].Kind != "single" || len(q[1].Options) != 2 || q[1].Default[0] != "postgres" ||
		q[2].ID != "db-2" || q[2].Kind != "multi" || len(q[2].Default) != 1 || q[2].Default[0] != "zed" ||
		q[3].Kind != "text" {
		t.Fatalf("questions = %+v", q)
	}

	reply, err = ParseReply(`{"status":"plan","plan":{"summary":"Plan","services":["postgres","postgres"],
		"prepare":[{"id":"deps","dir":"","argv":["bun","install"]},{"id":"deps","dir":".","argv":["bun2nix"]},{"id":"x","dir":"../outside","argv":["sh"]},{"id":"y","dir":".","argv":[]}],
		"expectations":{"version":99,"requiredChecks":["guessed-check"],
			"config":[{"path":["apps","web"],"exists":true},{"path":["apps","web"],"exists":false},{"path":["apps","web","bun","enable"],"equals":true},{"path":["modules"]},{"path":["enable"],"exists":false,"equals":true}],
			"files":["src/index.ts","/etc/passwd","../outside","src/index.ts"],
			"commands":[{"dir":"","argv":["bun","test"]},{"id":"lint","scope":"lint","dir":".","argv":["bun","run","lint"]},{"id":"bad","dir":"/","argv":["true"]}]}}}`)
	if err != nil {
		t.Fatal(err)
	}
	p := reply.Plan
	e := p.Expectations
	if len(p.Services) != 1 || len(p.Prepare) != 2 || p.Prepare[0].Dir != "." || p.Prepare[1].ID != "deps-2" {
		t.Fatalf("services or preparation = %+v %+v", p.Services, p.Prepare)
	}
	if e.Version != 1 || len(e.RequiredChecks) != 0 || len(e.Config) != 2 || e.Config[1].Exists == nil || *e.Config[1].Exists || len(e.Config[1].Equals) != 0 {
		t.Fatalf("expectations = %+v", e)
	}
	if len(e.Files) != 1 || len(e.Commands) != 2 || e.Commands[0].ID != "command-1" || e.Commands[0].Scope != "build" || e.Commands[1].Scope != "build" {
		t.Fatalf("files or commands = %+v %+v", e.Files, e.Commands)
	}
}
