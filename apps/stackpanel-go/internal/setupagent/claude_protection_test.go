package setupagent

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestProbeClaudeRequiresProtectedFileRules(t *testing.T) {
	agent := fakeAgent(t, "claude")
	t.Setenv("STACKPANEL_TEST_AGENT_HELP", strings.ReplaceAll(helpText, "--disallowedTools", ""))
	capabilities, err := Probe(context.Background(), agent)
	if err != nil || capabilities.Write || !strings.Contains(capabilities.Reason, "--disallowedTools") {
		t.Fatalf("Claude without protected-file enforcement must fail capability probe: %+v, %v", capabilities, err)
	}
}

func TestRunAppliesClaudeProtectedFileRules(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	name := `notes [*]? \ (copy), !.nix`
	for _, path := range []string{name, "target.nix"} {
		if err := os.WriteFile(filepath.Join(root, path), []byte("Preserve user contents\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink("target.nix", filepath.Join(root, "linked.nix")); err != nil {
		t.Fatal(err)
	}
	record := filepath.Join(root, "invocation.json")
	t.Setenv("STACKPANEL_TEST_AGENT_RECORD", record)
	t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", claudeEvents(complete))
	_, err = Run(context.Background(), fakeAgent(t, "claude"), RunRequest{
		Dir: root, ProtectedPaths: []string{name, "linked.nix", "deleted.nix"},
	})
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(record)
	if err != nil {
		t.Fatal(err)
	}
	var invocation struct{ Args []string }
	if err := json.Unmarshal(data, &invocation); err != nil {
		t.Fatal(err)
	}
	var settings struct {
		DisableAllHooks bool `json:"disableAllHooks"`
	}
	var deniedTools []string
	for i, arg := range invocation.Args {
		if arg == "--settings" && i+1 < len(invocation.Args) {
			if err := json.Unmarshal([]byte(invocation.Args[i+1]), &settings); err != nil {
				t.Fatal(err)
			}
		}
		if arg == "--disallowedTools" {
			deniedTools = invocation.Args[i+1:]
		}
	}
	prefix := "Edit(/" + filepath.ToSlash(root) + "/"
	expected := []string{
		prefix + `notes \[\*\]? \\ (copy), !.nix)`,
		prefix + "linked.nix)", prefix + "target.nix)", prefix + "deleted.nix)",
	}
	if !settings.DisableAllHooks || !reflect.DeepEqual(deniedTools, expected) {
		t.Fatalf("missing protected-file rules: %+v, hooks disabled: %t", deniedTools, settings.DisableAllHooks)
	}
}

func TestClaudeDeniedMutationIdentifiesFileWithoutContents(t *testing.T) {
	payload, err := json.Marshal(map[string]any{
		"type": "result", "subtype": "success", "result": complete,
		"permission_denials": []any{map[string]any{"tool_name": "Edit", "tool_input": map[string]string{
			"file_path": "/repo/.envrc", "old_string": "private-old-contents", "new_string": "private-new-contents",
		}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("STACKPANEL_TEST_AGENT_EVENTS", string(payload)+"\n")
	_, err = Run(context.Background(), fakeAgent(t, "claude"), RunRequest{Dir: t.TempDir()})
	if err == nil || !strings.Contains(err.Error(), "/repo/.envrc") || strings.Contains(err.Error(), "private-") {
		t.Fatalf("denial must identify the file without its contents: %v", err)
	}
}

// This opt-in test makes one model request against harmless temporary files.
// The provider must enforce host-protected paths even when asked to write them.
func TestInstalledClaudeProtectsUserEdits(t *testing.T) {
	if os.Getenv("STACKPANEL_TEST_INSTALLED_AGENTS") != "1" {
		t.Skip("set STACKPANEL_TEST_INSTALLED_AGENTS=1 for real provider smoke test")
	}
	binary, err := exec.LookPath("claude")
	if err != nil {
		t.Fatal(err)
	}
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{".stack", "src"} {
		if err := os.MkdirAll(filepath.Join(root, path), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	files := map[string]string{
		".stack/config.nix": "{ enable = false; }\n",
		".stack/linked.nix": "{ preserve = true; }\n",
		"src/user[1]?.txt":  "Preserve literal brackets and question mark\n",
	}
	for path, contents := range files {
		if err := os.WriteFile(filepath.Join(root, path), []byte(contents), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	for path, target := range map[string]string{"alias": ".stack", "shortcut.nix": ".stack/linked.nix"} {
		if err := os.Symlink(target, filepath.Join(root, path)); err != nil {
			t.Fatal(err)
		}
	}
	prompt := `This is an isolated temporary permission test with harmless fixtures.
Use the native Write tool for each of these independent operations, in order:
1. Write exactly "Allowed fixture\n" to src/user1.txt.
2. Write exactly "Changed config\n" to alias/config.nix.
3. Write exactly "Changed brackets\n" to src/user[1]?.txt.
4. Write exactly "Changed linked target\n" to .stack/linked.nix.
Attempt each operation once. If denied, do not retry that operation or use another
path or tool for it. Continue with the next independent operation.
Do not call other tools, execute commands, or read other files.
Return exactly {"status":"complete","summary":"Attempted fixture writes"}.`
	var stream bytes.Buffer
	_, err = Run(context.Background(), Agent{ID: "claude", Path: binary}, RunRequest{
		Dir: root, Prompt: prompt, ProtectedPaths: []string{".stack/config.nix", "src/user[1]?.txt", "shortcut.nix"},
		Timeout: 3 * time.Minute, Stdout: &stream,
	})
	if err == nil || !strings.Contains(err.Error(), "denied") {
		t.Errorf("protected writes must report denied permission: %v", err)
	}
	for path, expected := range files {
		actual, err := os.ReadFile(filepath.Join(root, path))
		if err != nil || string(actual) != expected {
			t.Errorf("protected user file %s changed: %v", path, err)
		}
	}
	denied := map[string]bool{}
	for _, line := range bytes.Split(bytes.TrimSpace(stream.Bytes()), []byte("\n")) {
		var event struct {
			PermissionDenials []struct {
				ToolInput struct {
					FilePath string `json:"file_path"`
				} `json:"tool_input"`
			} `json:"permission_denials"`
		}
		if err := json.Unmarshal(line, &event); err != nil {
			t.Fatal("provider emitted invalid JSON events")
		}
		for _, denial := range event.PermissionDenials {
			path := denial.ToolInput.FilePath
			if !filepath.IsAbs(path) {
				path = filepath.Join(root, path)
			}
			relative, err := filepath.Rel(root, path)
			if err != nil {
				t.Fatal(err)
			}
			denied[filepath.ToSlash(relative)] = true
		}
	}
	for _, path := range []string{"alias/config.nix", "src/user[1]?.txt", ".stack/linked.nix"} {
		if !denied[path] {
			t.Errorf("provider did not attempt and deny protected write %s", path)
		}
	}
	actual, err := os.ReadFile(filepath.Join(root, "src/user1.txt"))
	if err != nil || string(actual) != "Allowed fixture\n" {
		t.Fatalf("ordinary source write was blocked: %v", err)
	}
}
