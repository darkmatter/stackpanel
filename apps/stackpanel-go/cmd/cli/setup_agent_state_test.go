package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
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

func TestSetupManifestRejectsCorruption(t *testing.T) {
	setupStateTestEnvironment(t)
	root := t.TempDir()
	s := &setupManifest{Version: 1, Root: root, Stage: "apply", path: setupStatePath(root), Plan: &setupagent.Plan{Expectations: reconcile.Expectations{Version: 1}}}
	if err := s.save(); err != nil {
		t.Fatal(err)
	}
	for _, content := range []string{`{"version":`, `{"version":99,"root":` + jsonString(root) + `,"stage":"inspection"}`, `{"version":1,"root":"/wrong","stage":"inspection"}`, `{"version":1,"root":` + jsonString(root) + `,"stage":"apply"}`} {
		if err := os.WriteFile(s.path, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := loadSetupManifest(root); err == nil {
			t.Fatalf("accepted invalid manifest: %s", content)
		}
	}
}

func jsonString(s string) string { b, _ := json.Marshal(s); return string(b) }

func TestSetupAnswersCheckpointBeforeNextQuestion(t *testing.T) {
	setupStateTestEnvironment(t)
	root := t.TempDir()
	s := &setupManifest{Version: 1, Root: root, Stage: "inspection", path: setupStatePath(root), Pending: []setupagent.Question{
		{ID: "language", Prompt: "Language?", Kind: "single", Options: []string{"Go"}, Default: []string{"Go"}, Required: true},
		{ID: "name", Prompt: "Name?", Kind: "text", Required: true},
	}}
	var output bytes.Buffer
	ui := tui.NewSetupUI(context.Background(), false, &output)
	defer ui.Close()
	if err := answerSetupQuestions(s, &s.Request, ui); err == nil {
		t.Fatal("missing required answer did not stop setup")
	}
	saved, err := loadSetupManifest(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(saved.Pending) != 1 || saved.Pending[0].ID != "name" || len(saved.Request.Answers) != 1 || len(saved.Conversation) != 1 {
		t.Fatalf("lost completed answer or pending question: %+v", saved)
	}
	// Supply the remaining answer through the same UI path; the saved language
	// answer must survive without being appended or asked a second time.
	saved.Pending[0].Default = []string{"hello"}
	if err := answerSetupQuestions(saved, &saved.Request, ui); err != nil {
		t.Fatal(err)
	}
	saved, err = loadSetupManifest(root)
	if err != nil || len(saved.Request.Answers) != 2 || len(saved.Conversation) != 2 || len(saved.Pending) != 0 {
		t.Fatalf("resume answers: %+v %v", saved, err)
	}
}

func TestSetupResumeProtectsEditsBetweenRuns(t *testing.T) {
	for _, change := range []string{"none", "working", "staged", "head", "uncheckpointed"} {
		t.Run(change, func(t *testing.T) {
			setupStateTestEnvironment(t)
			root := setupGitFixture(t)
			ctx := context.Background()
			g, err := captureSetupGit(ctx, root)
			if err != nil {
				t.Fatal(err)
			}
			s := &setupManifest{Version: 1, Root: root, Stage: "inspection", path: setupStatePath(root)}
			writeSetupGitFile(t, root, "clean.txt", "setup work")
			writeSetupGitFile(t, root, ".stack/new.nix", "{}")
			if err := s.checkpoint(ctx, g); err != nil {
				t.Fatal(err)
			}
			switch change {
			case "working":
				writeSetupGitFile(t, root, "clean.txt", "user edited after failure")
			case "staged":
				setupGitTestRun(t, root, "add", "clean.txt")
			case "head":
				setupGitTestRun(t, root, "commit", "--allow-empty", "-qm", "user commit")
			case "uncheckpointed":
				writeSetupGitFile(t, root, "clean.txt", "unknown work after checkpoint")
			}
			g, err = captureSetupGit(ctx, root)
			if err != nil {
				t.Fatal(err)
			}
			saved, err := loadSetupManifest(root)
			if err != nil {
				t.Fatal(err)
			}
			saved.restoreGit(g)
			_, protected := g.protected["clean.txt"]
			if protected != (change != "none") {
				t.Fatalf("protected=%v after %s", protected, change)
			}
			if _, ok := g.protected["unstaged.txt"]; !ok {
				t.Fatal("lost original user edit protection")
			}
			if change == "none" {
				writeSetupGitFile(t, root, "clean.txt", "continued setup work")
				if err := g.AddNixInputs(ctx); err != nil {
					t.Fatal(err)
				}
				if len(g.owned[".stack/new.nix"]) != 1 {
					t.Fatal("partial Nix input was not visible on resume")
				}
				if err := g.Check(ctx); err != nil {
					t.Fatal(err)
				}
			}
		})
	}
}

func TestSetupResumeRestoresOptionsWithoutWeakeningPlan(t *testing.T) {
	s := &setupManifest{Agent: "claude", Options: setupSavedOptions{Template: "minimal", With: []string{"go"}, NoRuntime: true}}
	cmd := &cobra.Command{}
	cmd.Flags().StringSlice("with", nil, "")
	cmd.Flags().Bool("no-runtime", false, "")
	opts := setupFlags{template: "default", experimentalAgent: "auto"}
	if err := s.restoreOptions(cmd, &opts); err != nil {
		t.Fatal(err)
	}
	if opts.template != "minimal" || opts.experimentalAgent != "claude" || !opts.noRuntime || len(opts.with) != 1 {
		t.Fatalf("lost selections: %+v", opts)
	}
	if err := cmd.Flags().Set("with", "typescript"); err != nil {
		t.Fatal(err)
	}
	opts.with = []string{"typescript"}
	if err := s.restoreOptions(cmd, &opts); err == nil || !strings.Contains(err.Error(), "--restart") {
		t.Fatalf("changed contract accepted: %v", err)
	}
	cmd.Flags().Lookup("with").Changed = false
	if err := cmd.Flags().Set("no-runtime", "false"); err != nil {
		t.Fatal(err)
	}
	opts.noRuntime = false
	if err := s.restoreOptions(cmd, &opts); err != nil || opts.noRuntime {
		t.Fatalf("could not enable runtime on retry: %v", err)
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
	if err := loaded.restoreOptions(cmd, &opts); err != nil {
		t.Fatal(err)
	}
	if opts.experimentalAgent != "pi" || opts.agentModel != "openai/gpt-5" || len(loaded.Pi.Messages) != 1 {
		t.Fatal("Pi conversation or selection was lost on resume")
	}
	cmd.Flags().Set("agent-model", "openai/another-model")
	opts.agentModel = "openai/another-model"
	if err := loaded.restoreOptions(cmd, &opts); err == nil {
		t.Fatal("changed model accepted without restart")
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

func TestSetupResumeDoesNotForgetGitViolation(t *testing.T) {
	setupStateTestEnvironment(t)
	root := setupGitFixture(t)
	ctx := context.Background()
	g, err := captureSetupGit(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(filepath.Join(root, "unstaged.txt"))
	if err != nil {
		t.Fatal(err)
	}
	writeSetupGitFile(t, root, "unstaged.txt", "agent overwrote user edits")
	s := &setupManifest{Version: 1, Root: root, Stage: "inspection", path: setupStatePath(root), GitViolation: &setupGitCheckpoint{
		Root: g.root, Head: g.head, Index: g.index, Protected: g.protected,
	}}
	if err := s.save(); err != nil {
		t.Fatal(err)
	}
	s, err = loadSetupManifest(root)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.checkGitViolation(ctx); err == nil {
		t.Fatal("retry accepted an unresolved Git violation")
	}
	writeSetupGitFile(t, root, "unstaged.txt", string(before))
	if err := s.checkGitViolation(ctx); err != nil || s.GitViolation != nil {
		t.Fatalf("could not resume after restoring edits: %v", err)
	}
}
