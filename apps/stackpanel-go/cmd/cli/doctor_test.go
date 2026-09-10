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
	"github.com/spf13/cobra"
)

func TestDoctorStrictReportsMissingAndInvalidConfig(t *testing.T) {
	root := t.TempDir()
	for _, tt := range []struct{ name, config string }{
		{"absent", ""},
		{"malformed", "{"},
		{"empty", "{}"},
		{"wrong root", `{"version":1,"projectName":"test","projectRoot":"/different-root"}`},
	} {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("STACKPANEL_CONFIG_JSON", "")
			if tt.config != "" {
				path := filepath.Join(t.TempDir(), "config.json")
				if err := os.WriteFile(path, []byte(tt.config), 0o600); err != nil {
					t.Fatal(err)
				}
				t.Setenv("STACKPANEL_CONFIG_JSON", path)
			}
			t.Setenv("STACKPANEL_FILES_MANIFEST", "")
			report, err := collectDoctorReport(context.Background(), root, doctorOptions{Strict: true, Only: []string{"files"}})
			if err != nil {
				t.Fatal(err)
			}
			if !report.HasErrors() {
				t.Fatal("strict doctor accepted invalid or missing config")
			}
			found := false
			for _, finding := range report.Findings {
				if finding.Reconciler == "verification" && finding.ID == "config" {
					found = true
				}
			}
			if !found {
				t.Fatalf("missing config finding: %+v", report.Findings)
			}
			ordinary, err := collectDoctorReport(context.Background(), root, doctorOptions{Only: []string{"files"}})
			if err != nil || ordinary.HasErrors() {
				t.Fatalf("ordinary doctor changed missing-config exit behavior: report=%+v, err=%v", ordinary, err)
			}
		})
	}
}

func TestDoctorFiltersCannotWeakenExpectations(t *testing.T) {
	path := filepath.Join(t.TempDir(), "expectations.json")
	if err := os.WriteFile(path, []byte(`{"version":1,"requiredChecks":["web-build"]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, opts := range []doctorOptions{
		{Only: []string{"checks"}, ExpectationsPath: path},
		{Skip: []string{"checks"}, ExpectationsPath: path},
		{Skip: []string{"files"}, ExpectationsPath: path},
	} {
		_, err := collectDoctorReport(context.Background(), t.TempDir(), opts)
		if err == nil || !strings.Contains(err.Error(), "--expectations requires") {
			t.Fatalf("unsafe filter accepted: opts=%+v, err=%v", opts, err)
		}
	}
	if _, err := collectDoctorReport(context.Background(), t.TempDir(), doctorOptions{Scopes: []string{"typo"}}); err == nil {
		t.Fatal("unknown scope accepted")
	}
}

func TestDoctorStrictCleanSelectedReconciler(t *testing.T) {
	root := t.TempDir()
	configPath := filepath.Join(root, "config.json")
	config, _ := json.Marshal(map[string]any{"version": 1, "projectName": "test", "projectRoot": root})
	if err := os.WriteFile(configPath, config, 0o600); err != nil {
		t.Fatal(err)
	}
	manifestPath := filepath.Join(root, "files.json")
	if err := os.WriteFile(manifestPath, []byte(`{"version":2,"files":[]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STACKPANEL_CONFIG_JSON", configPath)
	t.Setenv("STACKPANEL_FILES_MANIFEST", manifestPath)
	t.Setenv("STACKPANEL_STATE_DIR", filepath.Join(root, "state"))
	report, err := collectDoctorReport(context.Background(), root, doctorOptions{Strict: true, Only: []string{"files"}})
	if err != nil {
		t.Fatal(err)
	}
	if report.HasErrors() {
		t.Fatalf("clean strict verification failed: %+v", report)
	}
}

func TestRunDoctorReturnsErrorAfterWritingJSON(t *testing.T) {
	savedJSON, savedOnly, savedSkip, savedBuild := doctorJSON, doctorOnly, doctorSkip, doctorBuild
	savedStrict, savedScope, savedExpectations := doctorStrict, doctorScope, doctorExpectations
	t.Cleanup(func() {
		doctorJSON, doctorOnly, doctorSkip, doctorBuild = savedJSON, savedOnly, savedSkip, savedBuild
		doctorStrict, doctorScope, doctorExpectations = savedStrict, savedScope, savedExpectations
	})
	doctorJSON = true
	doctorStrict = true
	doctorOnly = []string{"files"}
	doctorSkip = nil
	doctorBuild = false
	doctorScope = nil
	doctorExpectations = ""
	t.Setenv("STACKPANEL_ROOT", t.TempDir())
	t.Setenv("STACKPANEL_CONFIG_JSON", "")
	t.Setenv("STACKPANEL_FILES_MANIFEST", "")
	command := &cobra.Command{}
	command.SetContext(context.Background())
	var stdout, stderr bytes.Buffer
	command.SetOut(&stdout)
	command.SetErr(&stderr)
	if err := runDoctor(command, nil); err == nil {
		t.Fatal("missing strict configuration should return an error")
	}
	var report reconcile.Report
	if err := json.Unmarshal(stdout.Bytes(), &report); err != nil {
		t.Fatalf("failure report is not JSON: %s (%v)", stdout.String(), err)
	}
	if !report.HasErrors() || len(report.Coverage) == 0 {
		t.Fatalf("incomplete failure report: %+v", report)
	}
	for _, name := range []string{"strict", "scope", "expectations"} {
		if doctorCmd.Flags().Lookup(name) == nil {
			t.Fatalf("missing --%s flag", name)
		}
	}
}
