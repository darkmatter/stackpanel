package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupagent"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupsession"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/spf13/cobra"
)

func setupStateTestEnvironment(t *testing.T) {
	t.Helper()
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "stackpanel.yaml"))
}

func TestSetupManifestTargetRecovery(t *testing.T) {
	setupStateTestEnvironment(t)
	t.Chdir(t.TempDir())
	ctx := context.Background()
	for _, target := range []string{"tmp", "new"} {
		t.Run(target, func(t *testing.T) {
			opts := setupFlags{template: "minimal", tmp: target == "tmp"}
			if target == "new" {
				opts.newDir = filepath.Join(t.TempDir(), "new")
			}
			s, closeState, resuming, err := openSetupManifest(ctx, opts)
			if err != nil || resuming {
				t.Fatalf("open: resumed=%v err=%v", resuming, err)
			}
			root, path := s.Root, s.path
			if target == "tmp" {
				t.Cleanup(func() { os.RemoveAll(root) })
			}
			if filepath.IsLocal(mustSetupRelative(t, root, path)) {
				t.Fatal("manifest stored in agent workspace")
			}
			writeSetupGitFile(t, root, "partial.txt", "partial setup output")
			if _, _, _, err := openSetupManifest(ctx, opts); err == nil {
				t.Fatal("concurrent setup acquired lock")
			}
			closeState()
			s, closeState, resuming, err = openSetupManifest(ctx, opts)
			if err != nil || !resuming || s.Root != root || s.Options.Template != "minimal" {
				t.Fatalf("resume: state=%+v resuming=%v err=%v", s, resuming, err)
			}
			closeState()
			info, err := os.Stat(path)
			if err != nil || info.Mode().Perm() != 0o600 {
				t.Fatalf("manifest permissions: %v %v", info, err)
			}
			opts.restart = true
			fresh, closeFresh, resuming, err := openSetupManifest(ctx, opts)
			if err != nil || resuming {
				t.Fatalf("restart: %v %v", resuming, err)
			}
			defer closeFresh()
			if target == "tmp" {
				defer os.RemoveAll(fresh.Root)
				if fresh.Root == root {
					t.Fatal("--restart reused temporary repository")
				}
			} else if fresh.Root != root {
				t.Fatal("--restart moved explicit repository")
			}
			if _, err := os.Stat(filepath.Join(root, "partial.txt")); err != nil {
				t.Fatal("restart removed previous output")
			}
		})
	}
}

func mustSetupRelative(t *testing.T, root, path string) string {
	t.Helper()
	rel, err := filepath.Rel(root, path)
	if err != nil {
		t.Fatal(err)
	}
	return rel
}

func TestSetupManifestLoadsOlderAndDamagedState(t *testing.T) {
	setupStateTestEnvironment(t)
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	path := setupStatePath(root)
	load := func(content string) (*setupManifest, error) {
		t.Helper()
		if err := writeSetupJSON(path, json.RawMessage(content)); err != nil {
			t.Fatal(err)
		}
		return loadSetupManifest(root)
	}
	// Older releases saved Git checkpoints and malformed replies.
	loaded, err := load(`{"version":1,"root":` + jsonString(root) + `,"stage":"apply","git":{"head":"x"},"pendingReply":{"message":"x"},
		"plan":{"summary":"x","expectations":{"version":1,"config":[{"path":["enable"],"equals":true}],"requiredChecks":["old-check"]},
		"prepare":[{"id":"deps","dir":".","argv":["bun","install"]},{"id":"escape","dir":"../outside","argv":["sh"]}]}}`)
	if err != nil || loaded.Stage != stageApply || len(loaded.Plan.Prepare) != 1 || len(loaded.Plan.Expectations.RequiredChecks) != 0 {
		t.Fatalf("older manifest: %+v, %v", loaded, err)
	}
	if loaded, err := load(`{"version":1,"root":` + jsonString(root) + `,"stage":"verify"}`); err != nil || loaded.Stage != stageInspection {
		t.Fatalf("a stage without its plan must restart inspection: %+v, %v", loaded, err)
	}
	for _, content := range []string{`{"version":99,"root":` + jsonString(root) + `}`, `{"version":1,"root":"/wrong"}`} {
		if _, err := load(content); err == nil {
			t.Fatalf("accepted another release's or repository's manifest: %s", content)
		}
	}
	// Setup starts over rather than stopping on a manifest it cannot use.
	if err := os.WriteFile(path, []byte(`{"version":`), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Chdir(root)
	s, closeState, resuming, err := openSetupManifest(context.Background(), setupFlags{})
	if err != nil || resuming || s.Stage != stageInspection {
		t.Fatalf("damaged manifest: %+v %v %v", s, resuming, err)
	}
	closeState()
}

func jsonString(s string) string { b, _ := json.Marshal(s); return string(b) }

func TestSetupAnswersAreSavedAndNotAskedAgain(t *testing.T) {
	setupStateTestEnvironment(t)
	root := t.TempDir()
	questions := []setupagent.Question{
		{ID: "language", Prompt: "Language?", Kind: "single", Options: []string{"Go"}, Default: []string{"Go"}, Required: true},
		{ID: "name", Prompt: "Name?", Kind: "text", Required: true},
	}
	s := &setupManifest{Version: 1, Root: root, Stage: stageInspection, path: setupStatePath(root), Pending: questions}
	var output bytes.Buffer
	ui := tui.NewSetupUI(context.Background(), false, &output)
	defer ui.Close()
	// Without a person to ask, a question with no default leaves the choice to
	// the agent instead of stopping setup.
	if err := answerSetupQuestions(s, &s.Request, ui); err != nil {
		t.Fatal(err)
	}
	saved, err := loadSetupManifest(root)
	if err != nil || len(saved.Pending) != 0 || len(saved.Conversation) != 2 || len(saved.Request.Answers) != 2 ||
		saved.Request.Answers[0].Values[0] != "Go" || len(saved.Request.Answers[1].Values) != 0 {
		t.Fatalf("answers not saved: %+v %v", saved, err)
	}
	saved.Pending = questions
	if err := answerSetupQuestions(saved, &saved.Request, ui); err != nil || len(saved.Request.Answers) != 2 {
		t.Fatalf("answered questions asked again: %+v %v", saved.Request.Answers, err)
	}
}

func TestSetupResumeRestoresOptionsOrStartsANewPlan(t *testing.T) {
	s := &setupManifest{Agent: "claude", Options: setupSavedOptions{Template: "minimal", With: []string{"go"}, NoRuntime: true}}
	cmd := &cobra.Command{}
	cmd.Flags().StringSlice("with", nil, "")
	cmd.Flags().Bool("no-runtime", false, "")
	opts := setupFlags{template: "default", experimentalAgent: "auto"}
	if changed := s.restoreOptions(cmd, &opts); changed != "" {
		t.Fatal(changed)
	}
	if opts.template != "minimal" || opts.experimentalAgent != "claude" || !opts.noRuntime || len(opts.with) != 1 {
		t.Fatalf("lost selections: %+v", opts)
	}
	if err := cmd.Flags().Set("with", "typescript"); err != nil {
		t.Fatal(err)
	}
	opts.with = []string{"typescript"}
	if changed := s.restoreOptions(cmd, &opts); changed != "with" || opts.with[0] != "typescript" {
		t.Fatalf("changed selection: %q %+v", changed, opts)
	}
	cmd.Flags().Lookup("with").Changed = false
	if err := cmd.Flags().Set("no-runtime", "false"); err != nil {
		t.Fatal(err)
	}
	opts.noRuntime = false
	if changed := s.restoreOptions(cmd, &opts); changed != "" || opts.noRuntime {
		t.Fatalf("could not enable runtime on retry: %q", changed)
	}
}

func TestSetupResumeRestoresPiModelAndConversation(t *testing.T) {
	setupStateTestEnvironment(t)
	root := t.TempDir()
	s := &setupManifest{Version: 1, Root: root, Agent: "pi", Stage: "inspection", path: setupStatePath(root),
		Options: setupSavedOptions{AgentModel: "openai/gpt-5"},
		Pi:      &setupagent.PiState{Model: "openai/gpt-5", Messages: []json.RawMessage{json.RawMessage(`{"role":"user","content":"saved choice","timestamp":1}`)}},
	}
	if err := s.save(); err != nil {
		t.Fatal(err)
	}
	loaded, err := loadSetupManifest(root)
	if err != nil {
		t.Fatal(err)
	}
	cmd := &cobra.Command{}
	cmd.Flags().String("agent-model", "", "")
	opts := setupFlags{experimentalAgent: "auto"}
	if changed := loaded.restoreOptions(cmd, &opts); changed != "" {
		t.Fatal(changed)
	}
	if opts.experimentalAgent != "pi" || opts.agentModel != "openai/gpt-5" || len(loaded.Pi.Messages) != 1 {
		t.Fatal("Pi conversation or selection was lost on resume")
	}
	cmd.Flags().Set("agent-model", "openai/another-model")
	opts.agentModel = "openai/another-model"
	if changed := loaded.restoreOptions(cmd, &opts); changed != "agent-model" {
		t.Fatalf("changed model kept the saved conversation: %q", changed)
	}
	info, err := os.Stat(s.path)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("private manifest: %v", err)
	}
}

func TestPiMissingKeyStopsBeforeScaffolding(t *testing.T) {
	setupStateTestEnvironment(t)
	t.Setenv("OPENAI_API_KEY", "")
	root := filepath.Join(t.TempDir(), "new-project")
	cmd := &cobra.Command{}
	cmd.SetContext(context.Background())
	var output bytes.Buffer
	cmd.SetOut(&output)
	cmd.SetErr(&output)
	err := runAgentSetup(cmd, setupFlags{experimentalAgent: "pi", agentModel: "openai/gpt-5", newDir: root, yes: true, noRuntime: true})
	if err == nil || !strings.Contains(err.Error(), "OPENAI_API_KEY") {
		t.Fatalf("credential preflight: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "flake.nix")); !os.IsNotExist(err) {
		t.Fatalf("scaffold ran without credentials: %v", err)
	}
	state, err := loadSetupManifest(root)
	if err != nil || state.Options.AgentModel != "openai/gpt-5" {
		t.Fatalf("selection not saved: %v", err)
	}
}

func TestSetupResumeStudioReceipt(t *testing.T) {
	setupStateTestEnvironment(t)
	root := t.TempDir()
	s := &setupManifest{Version: 1, Root: root, Stage: "inspection", path: setupStatePath(root)}
	want := setupsession.Session{Root: root, ProjectID: "project", AgentID: "agent", Endpoint: "http://localhost", Origin: "https://studio.example", RequireBrowser: true}
	first, err := resumeSetupStudioSession(s, want)
	if err != nil {
		t.Fatal(err)
	}
	saved, err := loadSetupManifest(root)
	if err != nil {
		t.Fatal(err)
	}
	second, err := resumeSetupStudioSession(saved, want)
	if err != nil || first.ID != second.ID {
		t.Fatalf("valid receipt not resumed: %+v %v", second, err)
	}
	want.AgentID = "replacement-agent"
	replacement, err := resumeSetupStudioSession(saved, want)
	if err != nil || replacement.ID == first.ID {
		t.Fatalf("reused receipt from another agent: %+v %v", replacement, err)
	}
}
