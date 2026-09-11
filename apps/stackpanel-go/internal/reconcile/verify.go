package reconcile

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"sort"
	"strings"
	"time"
)

// Expectations is the frozen onboarding contract, evaluated independently of
// the agent's final message. Paths are relative to stackpanelConfig.
type Expectations struct {
	Version        int                 `json:"version"`
	Config         []ConfigAssertion   `json:"config"`
	RequiredChecks []string            `json:"requiredChecks"`
	Files          []string            `json:"files,omitempty"`
	Commands       []AcceptanceCommand `json:"commands,omitempty"`
}

type ConfigAssertion struct {
	Path   []string        `json:"path"`
	Exists *bool           `json:"exists,omitempty"`
	Equals json.RawMessage `json:"equals,omitempty"`
}

func ValidateExpectations(expected Expectations) error {
	if err := validateAcceptance(expected); err != nil {
		return err
	}
	if expected.Version != 1 {
		return fmt.Errorf("unsupported expectations version %d (expected 1)", expected.Version)
	}
	if len(expected.Config) == 0 && len(expected.RequiredChecks) == 0 {
		return fmt.Errorf("expectations must include configuration assertions or required checks")
	}
	paths := map[string]bool{}
	for _, assertion := range expected.Config {
		if len(assertion.Path) == 0 {
			return fmt.Errorf("configuration assertion has an empty path")
		}
		for _, part := range assertion.Path {
			if strings.TrimSpace(part) == "" {
				return fmt.Errorf("configuration assertion contains an empty path component")
			}
		}
		encoded, _ := json.Marshal(assertion.Path)
		if paths[string(encoded)] {
			return fmt.Errorf("duplicate configuration assertion for %s", strings.Join(assertion.Path, "."))
		}
		paths[string(encoded)] = true
		if assertion.Exists == nil && len(assertion.Equals) == 0 {
			return fmt.Errorf("configuration assertion for %s needs exists or equals", strings.Join(assertion.Path, "."))
		}
		if len(assertion.Equals) > 0 {
			if !json.Valid(assertion.Equals) {
				return fmt.Errorf("invalid equals JSON for %s", strings.Join(assertion.Path, "."))
			}
			if assertion.Exists != nil && !*assertion.Exists {
				return fmt.Errorf("configuration assertion cannot combine exists=false with equals")
			}
		}
	}
	ids := map[string]bool{}
	for _, id := range expected.RequiredChecks {
		if strings.TrimSpace(id) == "" {
			return fmt.Errorf("required check ID must not be empty")
		}
		if ids[id] {
			return fmt.Errorf("duplicate required check %q", id)
		}
		ids[id] = true
	}
	return nil
}

func LoadExpectations(path string) (Expectations, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Expectations{}, fmt.Errorf("read expectations: %w", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var expected Expectations
	if err := decoder.Decode(&expected); err != nil {
		return expected, fmt.Errorf("parse expectations: %w", err)
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return expected, fmt.Errorf("expectations must contain exactly one JSON object")
	}
	return expected, ValidateExpectations(expected)
}

// CheckExpectations evaluates the current flake purely; shell-generation JSON
// alone cannot prove that configuration assertions still hold on disk.
func CheckExpectations(ctx *Context, expected Expectations) []Finding {
	var findings []Finding
	if err := ValidateExpectations(expected); err != nil {
		return append(findings, verificationFinding("expectations", err.Error()))
	}
	system := ctx.Getenv("system")
	if system == "" {
		arch := runtime.GOARCH
		switch arch {
		case "amd64":
			arch = "x86_64"
		case "arm64":
			arch = "aarch64"
		}
		system = arch + "-" + runtime.GOOS
	}
	switch system {
	case "x86_64-linux", "aarch64-linux", "x86_64-darwin", "aarch64-darwin":
	default:
		return append(findings, verificationFinding("config", "unsupported Nix system: "+system))
	}
	attr := ctx.ProjectRoot + "#legacyPackages." + system + ".stackpanelConfig"
	if _, err := os.Stat(filepath.Join(ctx.ProjectRoot, "flake.lock")); err != nil {
		return append(findings, verificationFinding("config", "locked inputs are required: "+err.Error()))
	}
	evalCtx, cancel := context.WithTimeout(ctx.Ctx, 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(evalCtx, "nix", "eval", "--json", "--no-update-lock-file", "--no-write-lock-file", attr)
	cmd.Dir = ctx.ProjectRoot
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	result, err := cmd.Output()
	if err != nil {
		return append(findings, verificationFinding("config", "pure configuration evaluation failed: "+err.Error()+"\n"+trimNixNoise(stderr.String())))
	}
	var config map[string]any
	if err := json.Unmarshal(result, &config); err != nil || config == nil {
		return append(findings, verificationFinding("config", "evaluated Stackpanel configuration is not a JSON object"))
	}
	if _, ok := config["doctorList"].([]any); !ok {
		return append(findings, verificationFinding("checks", "freshly evaluated doctorList is missing or is not an array"))
	}
	// Read required definitions from the fresh evaluation, not just shell state.
	var fresh struct {
		Doctor []DoctorCheck `json:"doctorList"`
	}
	if err := json.Unmarshal(result, &fresh); err != nil {
		return append(findings, verificationFinding("checks", "cannot decode freshly evaluated check definitions"))
	}
	findings = append(findings, checkFreshChecks(ctx, fresh.Doctor, expected.RequiredChecks)...)
	return append(findings, checkConfigAssertions(config, expected.Config)...)
}

// checkFreshChecks requires evidence for every currently selected check and
// verifies it describes the same definition that the shell actually executed.
// This includes checks inferred by modules, even when no IDs were frozen.
func checkFreshChecks(ctx *Context, fresh []DoctorCheck, requiredIDs []string) []Finding {
	scopes := map[string]bool{}
	for _, scope := range ctx.CheckScopes {
		scopes[scope] = true
	}
	selected := func(c DoctorCheck) bool {
		return (c.Enabled || c.Required) && (len(scopes) == 0 || scopes[c.Scope])
	}
	oldChecks := map[string]DoctorCheck{}
	candidates := map[string]bool{}
	required := map[string]bool{}
	for _, id := range requiredIDs {
		candidates[id] = true
		required[id] = true
	}
	if ctx.Config != nil {
		for _, c := range ctx.Config.Doctor {
			oldChecks[c.ID] = c
			if selected(c) {
				candidates[c.ID] = true
			}
		}
	}
	newChecks := map[string]DoctorCheck{}
	for _, c := range fresh {
		newChecks[c.ID] = c
		if selected(c) {
			candidates[c.ID] = true
			required[c.ID] = true
		}
	}
	ids := make([]string, 0, len(candidates))
	for id := range candidates {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	requiredList := make([]string, 0, len(required))
	for _, id := range ids {
		if required[id] {
			requiredList = append(requiredList, id)
		}
	}
	freshCtx := *ctx
	freshCtx.Config = &ProjectConfig{Doctor: fresh}
	findings := checkRequiredChecks(&freshCtx, requiredList)
	for _, id := range ids {
		old, hadOld := oldChecks[id]
		current, hasCurrent := newChecks[id]
		if hadOld != hasCurrent || (hadOld && !reflect.DeepEqual(normalizeDoctorCheck(old), normalizeDoctorCheck(current))) {
			findings = append(findings, verificationFinding("stale:"+id, id+": check was added, removed, disabled, or changed since shell entry; enter a fresh shell before verification"))
		}
	}
	return findings
}

// The CLI config adds defaults to fields absent from build-scope doctorList entries.
func normalizeDoctorCheck(check DoctorCheck) DoctorCheck {
	if check.HTTPMethod == "" {
		check.HTTPMethod = "GET"
	}
	if check.HTTPExpectedStatus == 0 {
		check.HTTPExpectedStatus = 200
	}
	return check
}

func checkRequiredChecks(ctx *Context, ids []string) []Finding {
	checks := map[string]DoctorCheck{}
	if ctx.Config != nil {
		for _, c := range ctx.Config.Doctor {
			checks[c.ID] = c
		}
	}
	results := map[string]CheckResult{}
	for _, result := range ctx.CheckResults {
		results[result.ID] = result
	}
	var findings []Finding
	for _, id := range ids {
		check, exists := checks[id]
		reason := ""
		switch {
		case !exists:
			reason = "required check is missing from evaluated configuration"
		case !check.Enabled:
			reason = "required check is disabled"
		case results[id].Status != "pass":
			reason = "required check did not pass (excluded, skipped, failed, or unavailable)"
		}
		if reason != "" {
			findings = append(findings, verificationFinding("check:"+id, id+": "+reason))
		}
	}
	return findings
}

func checkConfigAssertions(config map[string]any, assertions []ConfigAssertion) []Finding {
	var findings []Finding
	for _, assertion := range assertions {
		var value any = config
		exists := true
		for _, part := range assertion.Path {
			object, ok := value.(map[string]any)
			if !ok {
				exists = false
				break
			}
			value, exists = object[part]
			if !exists {
				break
			}
		}
		path := strings.Join(assertion.Path, ".")
		if assertion.Exists != nil && exists != *assertion.Exists {
			findings = append(findings, verificationFinding("config:"+path, fmt.Sprintf("%s: expected exists=%t, got %t", path, *assertion.Exists, exists)))
			continue
		}
		if len(assertion.Equals) > 0 {
			var want any
			_ = json.Unmarshal(assertion.Equals, &want) // validated by ValidateExpectations
			if !exists || !reflect.DeepEqual(value, want) {
				// Do not copy arbitrary configuration values (potentially secrets) into reports.
				findings = append(findings, verificationFinding("config:"+path, path+": evaluated value does not match onboarding expectations"))
			}
		}
	}
	return findings
}

func verificationFinding(id, title string) Finding {
	return Finding{Reconciler: "verification", ID: id, Severity: SeverityError, Title: title}
}

// EnforceStrict makes incomplete execution and drift fatal. Optional addon
// offers remain informational. This operation is idempotent.
func (r *Report) EnforceStrict() {
	add := func(f Finding) {
		for _, existing := range r.Findings {
			if existing.Reconciler == f.Reconciler && existing.ID == f.ID {
				return
			}
		}
		r.Findings = append(r.Findings, f)
	}
	coverage := map[string]Coverage{}
	for _, c := range r.Coverage {
		coverage[c.Reconciler] = c
	}
	for _, id := range r.Reconcilers {
		if id == "verification" {
			continue
		}
		if c := coverage[id]; c.Status != "complete" {
			add(Finding{Reconciler: id, ID: "strict:coverage", Severity: SeverityError, Title: "verification incomplete", Detail: c.Reason})
		}
	}
	for _, change := range r.Changes {
		add(Finding{Reconciler: change.Reconciler, ID: "strict:drift:" + change.Path, Severity: SeverityError, Title: "pending reconciliation change", Path: change.Path})
	}
	for _, result := range r.CheckResults {
		if result.Status != "pass" {
			add(Finding{Reconciler: checksID, ID: "strict:check:" + result.ID, Severity: SeverityError, Title: result.ID + ": check did not pass (" + result.Status + ")", Detail: result.Message})
		}
	}
	r.sort()
}
