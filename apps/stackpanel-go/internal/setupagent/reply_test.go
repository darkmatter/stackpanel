package setupagent

import (
	"context"
	"reflect"
	"strings"
	"testing"
)

func TestRunRecoversReplyMissingFinalOuterBrace(t *testing.T) {
	plan := `{"status":"plan","plan":` + validPlan + `}`
	for _, tt := range []struct {
		name, message string
		readOnly      bool
	}{
		{"inspection", plan, true},
		{"setup", complete, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			agent := fakeAgent(t, "codex")
			// The provider completed normally, but omitted only the reply's
			// outermost closing brace. Its nested plan remains complete.
			t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", codexEvents(strings.TrimSuffix(tt.message, "}")))
			result, err := Run(context.Background(), agent, RunRequest{Dir: t.TempDir(), ReadOnly: tt.readOnly})
			if err != nil {
				t.Fatal(err)
			}
			actual, err := ParseReply(result.Message)
			if err != nil {
				t.Fatalf("completed provider reply was rejected: %v", err)
			}
			expected, err := ParseReply(tt.message)
			if err != nil || !reflect.DeepEqual(actual, expected) {
				t.Fatalf("recovery changed reply: got %+v, want %+v (%v)", actual, expected, err)
			}
		})
	}
}

func TestReplyRecoveryRejectsIncompleteOrInvalidContents(t *testing.T) {
	for _, tt := range []struct{ name, message string }{
		{"nested object", `{"status":"plan","plan":` + strings.TrimSuffix(validPlan, "}")},
		{"nested array", `{"status":"needs_input","questions":[{"id":"framework","prompt":"Framework?","kind":"text","required":true}`},
		{"unfinished string", `{"status":"complete","summary":"Done`},
		{"missing value", `{"status":"complete","summary":`},
		{"trailing comma", `{"status":"complete","summary":"Done",`},
		{"unknown field", `{"status":"complete","summary":"Done","unexpected":true`},
		{"invalid plan", `{"status":"plan","plan":{"summary":"No checks","expectations":{"version":1,"config":[]}}`},
	} {
		t.Run(tt.name, func(t *testing.T) {
			agent := fakeAgent(t, "codex")
			t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", codexEvents(tt.message))
			result, err := Run(context.Background(), agent, RunRequest{Dir: t.TempDir(), ReadOnly: true})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := ParseReply(result.Message); err == nil {
				t.Fatal("accepted incomplete or invalid reply")
			}
		})
	}
}
