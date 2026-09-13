package cmd

import (
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

func TestConversationCollectsAnswersWithoutPrintingJSON(t *testing.T) {
	root := t.TempDir()
	binary := filepath.Join(root, "codex")
	script := `#!/bin/sh
input=$(cat)
case "$input" in
  *'"values":["Go"]'*) reply='{"status":"complete","summary":"done"}' ;;
  *) reply='{"status":"needs_input","questions":[{"id":"language","prompt":"Language?","kind":"single","options":["Go"],"default":["Go"],"required":true}]}' ;;
esac
printf '{"type":"item.completed","item":{"type":"agent_message","text":"%s"}}\n' "$(printf '%s' "$reply" | sed 's/"/\\"/g')"
printf '{"type":"turn.completed"}\n'
`
	if err := os.WriteFile(binary, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	ui := tui.NewSetupUI(context.Background(), false, &output)
	defer ui.Close()
	request := setupagent.SetupRequest{Root: root}
	reply, err := runAgentPhase(context.Background(), setupagent.Agent{ID: "codex", Path: binary}, &request, setupagent.Setup, nil, "", ui, io.Discard)
	if err != nil || reply.Status != "complete" || len(request.Answers) != 1 {
		t.Fatalf("reply=%+v answers=%+v error=%v", reply, request.Answers, err)
	}
	if strings.Contains(output.String(), "turn.completed") {
		t.Fatal("raw JSON leaked")
	}
	if _, err := ui.Ask("Required", "text", nil, nil, true); err == nil {
		t.Fatal("silently accepted missing answer")
	}
}

func TestNewSetupTargetProtectsExistingDirectory(t *testing.T) {
	root := t.TempDir()
	file := filepath.Join(root, "keep")
	if err := os.WriteFile(file, []byte("user"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := prepareAgentSetupTarget(context.Background(), setupFlags{newDir: root}); err == nil {
		t.Fatal("accepted nonempty target")
	}
	newRoot, err := prepareAgentSetupTarget(context.Background(), setupFlags{newDir: filepath.Join(root, "new")})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(newRoot, ".git")); err != nil {
		t.Fatal(err)
	}
}

func TestSetupPlanDescribesVerificationScope(t *testing.T) {
	for _, tc := range []struct {
		opts setupFlags
		want string
	}{
		{setupFlags{}, "connect Studio, and verify runtime"},
		{setupFlags{noRuntime: true}, "Runtime and Studio checks are skipped"},
		{setupFlags{noBrowser: true}, "Studio check is skipped"},
	} {
		plan := &setupagent.Plan{Summary: "Create the app"}
		got := renderSetupPlan(plan, tc.opts)
		if !strings.Contains(got, tc.want) {
			t.Fatalf("plan promises the wrong verification scope: %s", got)
		}
	}
	if got := setupCommandLabel([]string{"go", "test", "./...", "a b"}); got != `go test ./... "a b"` {
		t.Fatalf("command argument boundaries lost in review: %s", got)
	}
}
