package reconcile

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"sort"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
)

// ChecksReconciler runs `stackpanel.doctor` checks. Runtime and repo checks
// execute through the same runner `stack healthcheck` uses. Build checks
// are listed, and realized with `nix build` only when the context asks for it,
// because they can be slow. Apply is a no-op: the doctor observes.
type ChecksReconciler struct {
	// Only restricts to these check IDs (empty = all).
	Only []string
	// Scopes restricts checks to repo, runtime, and/or build (empty = all).
	Scopes []string
}

const checksID = "checks"

// ID implements Reconciler.
func (r *ChecksReconciler) ID() string { return checksID }

func severityFor(protoSeverity string) Severity {
	switch protoSeverity {
	case "HEALTHCHECK_SEVERITY_CRITICAL":
		return SeverityError
	case "HEALTHCHECK_SEVERITY_INFO":
		return SeverityInfo
	default:
		return SeverityWarning
	}
}

// Diagnose implements Reconciler.
func (r *ChecksReconciler) Diagnose(ctx *Context) (*Diagnosis, error) {
	if !ctx.InDevshell() {
		return &Diagnosis{
			Notes:    []string{"skipped: not inside the devshell (no evaluated config)"},
			Coverage: &Coverage{Status: "skipped", Reason: "evaluated config unavailable"},
		}, nil
	}
	if ctx.Config.Doctor == nil {
		return &Diagnosis{Coverage: &Coverage{Status: "skipped", Reason: "evaluated doctor check list unavailable"}}, nil
	}
	only := map[string]bool{}
	for _, id := range r.Only {
		only[id] = true
	}

	scopes := map[string]bool{}
	for _, scope := range r.Scopes {
		scopes[scope] = true
	}
	var runnable []nixconfig.Healthcheck
	byID := map[string]DoctorCheck{}
	var build []DoctorCheck
	diag := &Diagnosis{}
	for _, c := range ctx.Config.Doctor {
		if len(scopes) > 0 && !scopes[c.Scope] {
			continue
		}
		if len(only) > 0 && !only[c.ID] {
			continue
		}
		if !c.Enabled {
			if c.Required {
				diag.CheckResults = append(diag.CheckResults, CheckResult{ID: c.ID, Module: c.Module, Scope: c.Scope, Status: "skipped", Message: "required check is disabled"})
			}
			continue
		}
		byID[c.ID] = c
		if c.Scope == "build" {
			build = append(build, c)
			continue
		}
		runnable = append(runnable, c.Healthcheck())
	}

	results := tui.RunHealthchecks(runnable)
	passing := map[string]int{}
	total := map[string]int{}
	for _, res := range results {
		c := byID[res.CheckID]
		status := res.Status
		if status == "skip" {
			status = "skipped"
		}
		diag.CheckResults = append(diag.CheckResults, CheckResult{
			ID: res.CheckID, Module: c.Module, Scope: c.Scope, Status: status,
			Message: res.Message, DurationMs: res.DurationMs,
		})
		total[c.Module]++
		switch res.Status {
		case "pass":
			passing[c.Module]++
		case "skip":
			diag.Notes = append(
				diag.Notes,
				fmt.Sprintf("%s skipped: %s", res.CheckID, res.Message),
			)
		default:
			f := Finding{
				Reconciler: checksID,
				ID:         c.ID,
				Severity:   severityFor(c.Severity),
				Title:      fmt.Sprintf("%s: %s (%s)", c.Module, c.Name, c.Scope),
				Detail:     strings.TrimSpace(res.Message),
			}
			if c.FixCommand != nil {
				f.FixCommand = *c.FixCommand
			}
			diag.Findings = append(diag.Findings, f)
		}
	}

	modules := make([]string, 0, len(total))
	for m := range total {
		modules = append(modules, m)
	}
	sort.Strings(modules)
	for _, m := range modules {
		diag.Notes = append(
			diag.Notes,
			fmt.Sprintf("%s %d/%d passing", m, passing[m], total[m]),
		)
	}

	if len(build) > 0 {
		if ctx.Build {
			r.runBuildChecks(ctx, build, diag)
		} else {
			for _, c := range build {
				diag.CheckResults = append(diag.CheckResults, CheckResult{ID: c.ID, Module: c.Module, Scope: c.Scope, Status: "skipped", Message: "pass --build to realize this check"})
			}
			diag.Notes = append(
				diag.Notes,
				fmt.Sprintf(
					"%d build check(s) not run; pass --build to realize them with nix",
					len(build),
				),
			)
		}
	}
	return diag, nil
}

// runBuildChecks realizes build-scope derivations with `nix build --no-link`.
// A failed build is an error finding naming the flake check.
func (r *ChecksReconciler) runBuildChecks(
	ctx *Context,
	checks []DoctorCheck,
	diag *Diagnosis,
) {
	for _, c := range checks {
		result := CheckResult{ID: c.ID, Module: c.Module, Scope: c.Scope, Status: "pass"}
		if c.DrvPath == nil || *c.DrvPath == "" {
			result.Status = "skipped"
			result.Message = "build check has no derivation path"
			diag.CheckResults = append(diag.CheckResults, result)
			continue
		}
		timeout := time.Duration(c.Timeout) * time.Second
		if timeout <= 0 {
			timeout = 5 * time.Minute
		}
		bctx, cancel := context.WithTimeout(ctx.Ctx, timeout)
		cmd := exec.CommandContext(bctx, "nix", "build", "--no-link", *c.DrvPath+"^*")
		cmd.Dir = ctx.ProjectRoot
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		start := time.Now()
		err := cmd.Run()
		result.DurationMs = time.Since(start).Milliseconds()
		if err != nil {
			result.Status = "fail"
			result.Message = trimNixNoise(stderr.String())
			if result.Message == "" {
				result.Message = err.Error()
			}
			if bctx.Err() != nil {
				result.Status = "error"
				result.Message = bctx.Err().Error()
			}
		}
		diag.CheckResults = append(diag.CheckResults, result)
		cancel()
		if err != nil {
			name := c.ID
			if c.CheckName != nil {
				name = *c.CheckName
			}
			diag.Findings = append(diag.Findings, Finding{
				Reconciler: checksID,
				ID:         c.ID,
				Severity:   severityFor(c.Severity),
				Title:      fmt.Sprintf("%s: build check %s failed", c.Module, name),
				Detail:     result.Message,
				FixCommand: "nix build .#checks.<system>." + name,
			})
		}
	}
}

// Apply implements Reconciler. Observation only.
func (r *ChecksReconciler) Apply(*Context) (*ApplyResult, error) {
	return &ApplyResult{}, nil
}
