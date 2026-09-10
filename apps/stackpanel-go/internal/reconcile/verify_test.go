package reconcile

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStrictVerificationRejectsIncompleteExecutionAndDrift(t *testing.T) {
	for _, tt := range []struct {
		name   string
		report Report
		fails  bool
	}{
		{"clean with optional offer", Report{Reconcilers: []string{"files"}, Coverage: []Coverage{{Reconciler: "files", Status: "complete"}}, Offers: []Offer{{ID: "optional"}}}, false},
		{"pending change", Report{Changes: []Change{{Reconciler: "files", Kind: ChangeUpdate, Path: "generated"}}}, true},
		{"skipped reconciler", Report{Reconcilers: []string{"files"}, Coverage: []Coverage{{Reconciler: "files", Status: "skipped", Reason: "manifest missing"}}}, true},
		{"absent coverage", Report{Reconcilers: []string{"checks"}}, true},
		{"skipped check", Report{CheckResults: []CheckResult{{ID: "required", Status: "skipped"}}}, true},
		{"warning check failure", Report{CheckResults: []CheckResult{{ID: "warning", Status: "fail"}}}, true},
		{"check timeout", Report{CheckResults: []CheckResult{{ID: "timeout", Status: "error"}}}, true},
		{"passed check", Report{CheckResults: []CheckResult{{ID: "ok", Status: "pass"}}}, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			tt.report.EnforceStrict()
			if tt.report.HasErrors() != tt.fails {
				t.Fatalf("HasErrors=%t, findings=%+v", tt.report.HasErrors(), tt.report.Findings)
			}
			count := len(tt.report.Findings)
			tt.report.EnforceStrict()
			if len(tt.report.Findings) != count {
				t.Fatal("strict enforcement is not idempotent")
			}
		})
	}
}

func TestRequiredChecksCannotDisappearBeDisabledOrBeSkipped(t *testing.T) {
	for _, tt := range []struct {
		name    string
		checks  []DoctorCheck
		results []CheckResult
		fails   bool
	}{
		{"missing", nil, nil, true},
		{"disabled", []DoctorCheck{{ID: "required"}}, []CheckResult{{ID: "required", Status: "pass"}}, true},
		{"not run", []DoctorCheck{{ID: "required", Enabled: true}}, nil, true},
		{"skipped", []DoctorCheck{{ID: "required", Enabled: true}}, []CheckResult{{ID: "required", Status: "skipped"}}, true},
		{"passing", []DoctorCheck{{ID: "required", Enabled: true}}, []CheckResult{{ID: "required", Status: "pass"}}, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			findings := checkRequiredChecks(&Context{Config: &ProjectConfig{Doctor: tt.checks}, CheckResults: tt.results}, []string{"required"})
			if (len(findings) > 0) != tt.fails {
				t.Fatalf("findings=%+v", findings)
			}
		})
	}
}

func TestConfigAssertionsCheckNestedPathsAndNull(t *testing.T) {
	yes, no := true, false
	var config map[string]any
	_ = json.Unmarshal([]byte(`{"apps":{"web":{"enable":true,"port":42,"optional":null}},"secret":"do-not-print"}`), &config)
	valid := []ConfigAssertion{
		{Path: []string{"apps", "web"}, Exists: &yes},
		{Path: []string{"apps", "missing"}, Exists: &no},
		{Path: []string{"apps", "web", "enable"}, Equals: json.RawMessage(`true`)},
		{Path: []string{"apps", "web", "port"}, Equals: json.RawMessage(`42.0`)},
		{Path: []string{"apps", "web", "optional"}, Equals: json.RawMessage(`null`)},
	}
	if got := checkConfigAssertions(config, valid); len(got) != 0 {
		t.Fatalf("valid assertions: %+v", got)
	}
	invalid := []ConfigAssertion{
		{Path: []string{"apps", "missing"}, Exists: &yes},
		{Path: []string{"apps", "web", "enable"}, Equals: json.RawMessage(`false`)},
		{Path: []string{"apps", "web", "enable", "nested"}, Exists: &yes},
		{Path: []string{"secret"}, Equals: json.RawMessage(`"different"`)},
	}
	got := checkConfigAssertions(config, invalid)
	if len(got) != len(invalid) {
		t.Fatalf("findings: %+v", got)
	}
	data, _ := json.Marshal(got)
	if strings.Contains(string(data), "do-not-print") {
		t.Fatal("report leaked configuration value")
	}
}

func TestLoadExpectationsRejectsMalformedContracts(t *testing.T) {
	for _, input := range []string{
		`{}`, `{"version":1}`, `{"version":2,"requiredChecks":["x"]}`,
		`{"version":1,"requiredChecks":["x","x"]}`,
		`{"version":1,"requiredChecks":[""]}`,
		`{"version":1,"config":[{"path":["apps"]}]}`,
		`{"version":1,"config":[{"path":[],"exists":true}]}`,
		`{"version":1,"config":[{"path":["apps"],"exists":false,"equals":true}]}`,
		`{"version":1,"requiredChecks":["x"],"typo":true}`,
		`{"version":1,"requiredChecks":["x"]} {}`,
	} {
		t.Run(input, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "expectations.json")
			if err := os.WriteFile(path, []byte(input), 0o600); err != nil {
				t.Fatal(err)
			}
			if _, err := LoadExpectations(path); err == nil {
				t.Fatal("invalid contract accepted")
			}
		})
	}
}

func TestCoverageDistinguishesMissingAndEmptyManifests(t *testing.T) {
	root := t.TempDir()
	filePath := filepath.Join(root, "files.json")
	if err := os.WriteFile(filePath, []byte(`{"version":2,"files":[]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, reconciler := range []Reconciler{&FilesReconciler{}, &FileopsReconciler{}, &CodegenReconciler{}, &ChecksReconciler{}} {
		ctx := &Context{Ctx: context.Background(), ProjectRoot: root, StateDir: filepath.Join(root, "state"), Getenv: func(string) string { return "" }}
		report := NewRegistry(reconciler).Diagnose(ctx)
		report.EnforceStrict()
		if !report.HasErrors() || report.Coverage[0].Status != "skipped" {
			t.Fatalf("%s missing input accepted: %+v", reconciler.ID(), report)
		}
		if reconciler.ID() == "files" || reconciler.ID() == "fileops" {
			ctx.Getenv = func(string) string { return filePath }
			report = NewRegistry(reconciler).Diagnose(ctx)
			report.EnforceStrict()
			if report.HasErrors() || report.Coverage[0].Status != "complete" {
				t.Fatalf("%s empty manifest rejected: %+v", reconciler.ID(), report)
			}
		}
	}
	report := NewRegistry(&fakeReconciler{id: "broken", fail: true}).Diagnose(&Context{})
	if report.Coverage[0].Status != "error" {
		t.Fatal("failed reconciler did not record error coverage")
	}
}

func TestNewContextPreservesConfigLoadingError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bad.json")
	if err := os.WriteFile(path, []byte(`{`), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STACKPANEL_CONFIG_JSON", path)
	ctx, err := NewContext(context.Background(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if ctx.Config != nil || ctx.ConfigError == nil {
		t.Fatalf("invalid config silently ignored: %+v", ctx)
	}
}

func TestCheckExpectationsUsesLockedPureFreshEvaluation(t *testing.T) {
	root := t.TempDir()
	fixture := filepath.Join(root, "evaluated.json")
	argsPath := filepath.Join(root, "nix-args")
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$VERIFY_ARGS\"\ncat \"$VERIFY_CONFIG\"\n"
	if err := os.WriteFile(filepath.Join(root, "nix"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", root+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("VERIFY_ARGS", argsPath)
	t.Setenv("VERIFY_CONFIG", fixture)
	check := DoctorCheck{ID: "app-build", Enabled: true, Scope: "build"}
	ctx := &Context{Ctx: context.Background(), ProjectRoot: root, Getenv: func(string) string { return "x86_64-linux" }, Config: &ProjectConfig{Doctor: []DoctorCheck{check}}, CheckResults: []CheckResult{{ID: check.ID, Status: "pass"}}}
	expected := Expectations{Version: 1, Config: []ConfigAssertion{{Path: []string{"apps", "web", "enable"}, Equals: json.RawMessage(`true`)}}, RequiredChecks: []string{check.ID}}
	if got := CheckExpectations(ctx, expected); len(got) == 0 {
		t.Fatal("missing lockfile accepted")
	}
	if _, err := os.Stat(argsPath); !os.IsNotExist(err) {
		t.Fatal("Nix ran before checking locked inputs")
	}
	if err := os.WriteFile(filepath.Join(root, "flake.lock"), []byte(`{}`), 0o600); err != nil {
		t.Fatal(err)
	}
	config := map[string]any{"apps": map[string]any{"web": map[string]any{"enable": true}}, "doctorList": []DoctorCheck{check}}
	data, _ := json.Marshal(config)
	if err := os.WriteFile(fixture, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if got := CheckExpectations(ctx, expected); len(got) != 0 {
		t.Fatalf("valid contract failed: %+v", got)
	}
	args, _ := os.ReadFile(argsPath)
	for _, want := range []string{"--json", "--no-update-lock-file", "--no-write-lock-file", root + "#legacyPackages.x86_64-linux.stackpanelConfig"} {
		if !strings.Contains(string(args), want+"\n") {
			t.Fatalf("missing %q in %s", want, args)
		}
	}
	if strings.Contains(string(args), "--impure") {
		t.Fatal("verification evaluated impurely")
	}
	check.Timeout = 99
	config["doctorList"] = []DoctorCheck{check}
	data, _ = json.Marshal(config)
	if err := os.WriteFile(fixture, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if got := CheckExpectations(ctx, expected); len(got) != 1 || !strings.HasPrefix(got[0].ID, "stale:") {
		t.Fatalf("stale execution accepted: %+v", got)
	}

	// These records mirror serializeCheck/doctorList in core/options/doctor.nix:
	// build records omit all detector fields; runtime/repo records include them
	// along with fields not exported into the CLI config (script, nixExpr, etc.).
	nixShaped := `{"apps":{"web":{"enable":true}},"doctorList":[
 {"id":"go-build","name":"build","description":null,"module":"go","displayName":"Go","scope":"build","severity":"HEALTHCHECK_SEVERITY_CRITICAL","type":"HEALTHCHECK_TYPE_DERIVATION","checkName":"go-build","drvPath":"/nix/store/check.drv","timeout":300,"tags":[],"required":true,"enabled":true,"fixCommand":null},
 {"id":"go-layout","name":"layout","description":null,"module":"go","displayName":"Go","scope":"repo","severity":"HEALTHCHECK_SEVERITY_WARNING","type":"HEALTHCHECK_TYPE_SCRIPT","script":"test -f go.mod","scriptPath":"/nix/store/layout/bin/check","scriptDrvPath":"/nix/store/layout.drv","scriptSource":"inline","nixExpr":null,"httpUrl":null,"httpMethod":"GET","httpExpectedStatus":200,"tcpHost":null,"tcpPort":null,"timeout":10,"interval":60,"tags":[],"enabled":true,"fixCommand":null}
 ]}`
	var serialized struct {
		Doctor []DoctorCheck `json:"doctorList"`
	}
	if err := json.Unmarshal([]byte(nixShaped), &serialized); err != nil {
		t.Fatal(err)
	}
	ctx.Config.Doctor = append([]DoctorCheck(nil), serialized.Doctor...)
	// core/cli.nix supplies these defaults on build entries.
	ctx.Config.Doctor[0].HTTPMethod = "GET"
	ctx.Config.Doctor[0].HTTPExpectedStatus = 200
	ctx.CheckResults = []CheckResult{{ID: "go-build", Status: "pass"}, {ID: "go-layout", Status: "pass"}}
	expected.RequiredChecks = []string{"go-build", "go-layout"}
	if err := os.WriteFile(fixture, []byte(nixShaped), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := CheckExpectations(ctx, expected); len(got) != 0 {
		t.Fatalf("Nix-shaped definitions rejected: %+v", got)
	}
}

func TestChecksReconcilerReportsSelectedExecution(t *testing.T) {
	root := t.TempDir()
	pass := filepath.Join(root, "pass")
	fail := filepath.Join(root, "fail")
	if err := os.WriteFile(pass, []byte("#!/bin/sh\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(fail, []byte("#!/bin/sh\nexit 1\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	ctx := &Context{Ctx: context.Background(), ProjectRoot: root, Config: &ProjectConfig{Doctor: []DoctorCheck{
		{ID: "pass", Module: "test", Scope: "repo", Enabled: true, Type: "HEALTHCHECK_TYPE_SCRIPT", ScriptPath: &pass},
		{ID: "fail", Module: "test", Scope: "repo", Enabled: true, Type: "HEALTHCHECK_TYPE_SCRIPT", ScriptPath: &fail},
		{ID: "skip", Module: "test", Scope: "repo", Enabled: true, Type: "HEALTHCHECK_TYPE_NIX"},
		{ID: "runtime", Module: "test", Scope: "runtime", Enabled: true, Type: "HEALTHCHECK_TYPE_SCRIPT", ScriptPath: &fail},
		{ID: "build", Module: "test", Scope: "build", Enabled: true},
		{ID: "disabled", Module: "test", Scope: "repo", Enabled: false},
	}}}
	report := NewRegistry(&ChecksReconciler{Scopes: []string{"repo", "build"}}).Diagnose(ctx)
	statuses := map[string]string{}
	for _, result := range report.CheckResults {
		statuses[result.ID] = result.Status
	}
	if len(statuses) != 4 || statuses["pass"] != "pass" || statuses["fail"] != "fail" || statuses["skip"] != "skipped" || statuses["build"] != "skipped" {
		t.Fatalf("unexpected execution: %+v", statuses)
	}
	if report.HasErrors() {
		t.Fatal("ordinary doctor changed warning/skip semantics")
	}
	report.EnforceStrict()
	if !report.HasErrors() {
		t.Fatal("strict doctor accepted nonpassing checks")
	}
	ctx.Build = true
	report = NewRegistry(&ChecksReconciler{Scopes: []string{"build"}}).Diagnose(ctx)
	if len(report.CheckResults) != 1 || report.CheckResults[0].Status != "skipped" || !strings.Contains(report.CheckResults[0].Message, "derivation") {
		t.Fatalf("missing derivation unreported: %+v", report.CheckResults)
	}
}

func TestBuildChecksRecordSuccessFailureAndCancellation(t *testing.T) {
	root := t.TempDir()
	script := "#!/bin/sh\ncase \"$3\" in\n*/success.drv^*) exit 0 ;;\n*) printf 'build failed\\n' >&2; exit 1 ;;\nesac\n"
	if err := os.WriteFile(filepath.Join(root, "nix"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", root+string(os.PathListSeparator)+os.Getenv("PATH"))
	good, bad := "/fake/success.drv", "/fake/failure.drv"
	ctx := &Context{Ctx: context.Background(), ProjectRoot: root, Build: true, Config: &ProjectConfig{Doctor: []DoctorCheck{
		{ID: "success", Scope: "build", Enabled: true, DrvPath: &good},
		{ID: "failure", Scope: "build", Enabled: true, DrvPath: &bad},
	}}}
	report := NewRegistry(&ChecksReconciler{}).Diagnose(ctx)
	if len(report.CheckResults) != 2 || report.CheckResults[0].Status != "pass" || report.CheckResults[1].Status != "fail" {
		t.Fatalf("build results: %+v", report.CheckResults)
	}
	if !strings.Contains(report.CheckResults[1].Message, "build failed") {
		t.Fatalf("missing build diagnostic: %+v", report.CheckResults[1])
	}
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	ctx.Ctx = cancelled
	report = NewRegistry(&ChecksReconciler{}).Diagnose(ctx)
	for _, result := range report.CheckResults {
		if result.Status != "error" {
			t.Fatalf("cancelled check reported %s", result.Status)
		}
	}
	report.EnforceStrict()
	if !report.HasErrors() {
		t.Fatal("cancelled build verification passed")
	}
}

func TestFreshChecksCoverModuleChecksWithoutFrozenIDs(t *testing.T) {
	original := DoctorCheck{ID: "module-build", Scope: "build", Enabled: true}
	changed := original
	changed.Timeout = 60
	disabled := original
	disabled.Enabled = false
	requiredDisabled := disabled
	requiredDisabled.Required = true
	runtimeCheck := DoctorCheck{ID: "runtime", Scope: "runtime", Enabled: true, Required: true}
	runtimeChanged := runtimeCheck
	runtimeChanged.Timeout = 60
	for _, tt := range []struct {
		name       string
		old, fresh []DoctorCheck
		results    []CheckResult
		fails      bool
	}{
		{"unchanged", []DoctorCheck{original}, []DoctorCheck{original}, []CheckResult{{ID: original.ID, Status: "pass"}}, false},
		{"new check", nil, []DoctorCheck{original}, nil, true},
		{"changed check", []DoctorCheck{original}, []DoctorCheck{changed}, []CheckResult{{ID: original.ID, Status: "pass"}}, true},
		{"removed check", []DoctorCheck{original}, nil, []CheckResult{{ID: original.ID, Status: "pass"}}, true},
		{"disabled check", []DoctorCheck{original}, []DoctorCheck{disabled}, []CheckResult{{ID: original.ID, Status: "pass"}}, true},
		{"required disabled", []DoctorCheck{requiredDisabled}, []DoctorCheck{requiredDisabled}, nil, true},
		{"missing execution", []DoctorCheck{original}, []DoctorCheck{original}, nil, true},
		{"runtime intentionally excluded", []DoctorCheck{runtimeCheck}, []DoctorCheck{runtimeChanged}, nil, false},
		{"plain repo with no checks", nil, nil, nil, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			ctx := &Context{Config: &ProjectConfig{Doctor: tt.old}, CheckScopes: []string{"repo", "build"}, CheckResults: tt.results}
			findings := checkFreshChecks(ctx, tt.fresh, nil)
			if (len(findings) > 0) != tt.fails {
				t.Fatalf("findings: %+v", findings)
			}
		})
	}
}

func TestStrictDoctorRejectsDisabledDeclaredRequiredCheck(t *testing.T) {
	ctx := &Context{Ctx: context.Background(), Config: &ProjectConfig{Doctor: []DoctorCheck{{ID: "module-required", Scope: "build", Required: true, Enabled: false}}}}
	report := NewRegistry(&ChecksReconciler{Scopes: []string{"build"}}).Diagnose(ctx)
	if report.HasErrors() {
		t.Fatal("ordinary doctor should keep disabled-check reporting informational")
	}
	report.EnforceStrict()
	if !report.HasErrors() {
		t.Fatal("disabled required declaration passed strict doctor")
	}
}

func TestCheckCoverageDistinguishesMissingAndEmptyDoctorLists(t *testing.T) {
	for _, tt := range []struct {
		name   string
		checks []DoctorCheck
		fails  bool
	}{
		{"missing", nil, true}, {"empty", []DoctorCheck{}, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			report := NewRegistry(&ChecksReconciler{}).Diagnose(&Context{Ctx: context.Background(), Config: &ProjectConfig{Doctor: tt.checks}})
			report.EnforceStrict()
			if report.HasErrors() != tt.fails {
				t.Fatalf("coverage: %+v, findings: %+v", report.Coverage, report.Findings)
			}
		})
	}
}
