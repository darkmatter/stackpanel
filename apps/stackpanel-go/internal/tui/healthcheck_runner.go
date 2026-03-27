// Healthcheck runner: executes healthcheck definitions from Nix config locally.
//
// Healthchecks are defined in .stack/config.nix and evaluated into JSON by the
// Nix module system. The runner supports script, HTTP, and TCP check types.
// Nix-eval checks are deliberately skipped in CLI context (too slow).
//
// Results are cached to .stack/state/healthchecks.json with a 5-minute TTL.
// The MOTD reads this cache to display health status without re-running checks.

package tui

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
)

// HealthcheckResult represents the cached result of a single healthcheck run.
type HealthcheckResult struct {
	CheckID    string `json:"checkId"`
	Module     string `json:"module"`
	Name       string `json:"name"`
	Status     string `json:"status"` // "pass", "fail", "skip", "error"
	Severity   string `json:"severity"`
	Message    string `json:"message,omitempty"`
	DurationMs int64  `json:"durationMs"`
}

// HealthcheckCache is the on-disk cache format written to .stack/state/healthchecks.json.
type HealthcheckCache struct {
	Version   int                 `json:"version"`
	Timestamp time.Time           `json:"timestamp"`
	Results   []HealthcheckResult `json:"results"`
}

// ModuleHealthResult groups check results by module for MOTD display.
// Severity tracks the worst failure in the module so the MOTD can choose
// the right color (red for critical, yellow for warning).
type ModuleHealthResult struct {
	Module       string
	DisplayName  string
	TotalChecks  int
	PassingCount int
	FailingCount int
	SkippedCount int
	Severity     string // worst severity among failures, using proto enum strings
}

const (
	healthcheckCacheFile = "healthchecks.json"
	healthcheckCacheTTL  = 5 * time.Minute
)

// LoadHealthcheckResults loads cached healthcheck results from disk without
// ever running checks. Returns nil if no cache file exists. Unlike
// LoadHealthcheckCache this ignores the TTL — results are always returned
// regardless of age so callers can display elapsed time and a re-run hint.
func LoadHealthcheckResults(stateDir string) *HealthcheckCache {
	path := filepath.Join(stateDir, healthcheckCacheFile)

	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}

	var cache HealthcheckCache
	if err := json.Unmarshal(data, &cache); err != nil {
		return nil
	}

	return &cache
}

// RunFailedHealthchecks re-runs only failing/unknown checks while keeping
// passing results from cache. This avoids re-running expensive passing checks
// when the user just wants to fix failures. The merged result set is persisted.
func RunFailedHealthchecks(stateDir string, checks []nixconfig.Healthcheck) []HealthcheckResult {
	if len(checks) == 0 {
		return nil
	}

	// Load existing cache (ignore TTL)
	existingCache := LoadHealthcheckResults(stateDir)
	cachedByID := make(map[string]HealthcheckResult)
	if existingCache != nil {
		for _, r := range existingCache.Results {
			cachedByID[r.CheckID] = r
		}
	}

	// Partition checks into those that need re-running and those that can be kept
	var checksToRun []nixconfig.Healthcheck
	var keptResults []HealthcheckResult

	for _, check := range checks {
		if !check.Enabled {
			continue
		}
		cached, hasCached := cachedByID[check.ID]
		if hasCached && cached.Status == "pass" {
			keptResults = append(keptResults, cached)
		} else {
			checksToRun = append(checksToRun, check)
		}
	}

	// Run the failed/unknown checks
	freshResults := RunHealthchecks(checksToRun)

	// Merge
	allResults := append(keptResults, freshResults...)

	// Persist
	_ = SaveHealthcheckCache(stateDir, allResults)

	return allResults
}

// RunHealthchecks executes all healthcheck definitions concurrently and returns results.
// Each check runs in its own goroutine with an individual timeout. The results slice
// is pre-allocated and indexed by position, so order is deterministic despite parallelism.
func RunHealthchecks(checks []nixconfig.Healthcheck) []HealthcheckResult {
	if len(checks) == 0 {
		return nil
	}

	results := make([]HealthcheckResult, len(checks))
	var wg sync.WaitGroup

	for i, check := range checks {
		wg.Add(1)
		go func(idx int, c nixconfig.Healthcheck) {
			defer wg.Done()
			results[idx] = runSingleCheck(c)
		}(i, check)
	}

	wg.Wait()
	return results
}

// runSingleCheck executes a single healthcheck and returns the result.
func runSingleCheck(check nixconfig.Healthcheck) HealthcheckResult {
	result := HealthcheckResult{
		CheckID:  check.ID,
		Module:   check.Module,
		Name:     check.Name,
		Severity: check.Severity,
	}

	if !check.Enabled {
		result.Status = "skip"
		result.Message = "disabled"
		return result
	}

	timeout := time.Duration(check.Timeout) * time.Second
	if timeout == 0 {
		timeout = 10 * time.Second
	}

	start := time.Now()

	switch check.Type {
	case "HEALTHCHECK_TYPE_SCRIPT":
		result = runScriptCheck(check, timeout)
	case "HEALTHCHECK_TYPE_HTTP":
		result = runHTTPCheck(check, timeout)
	case "HEALTHCHECK_TYPE_TCP":
		result = runTCPCheck(check, timeout)
	case "HEALTHCHECK_TYPE_NIX":
		// Nix eval checks are expensive — skip in CLI/MOTD context
		result.Status = "skip"
		result.Message = "nix checks skipped in CLI"
	default:
		result.Status = "skip"
		result.Message = fmt.Sprintf("unknown type: %s", check.Type)
	}

	result.DurationMs = time.Since(start).Milliseconds()
	result.CheckID = check.ID
	result.Module = check.Module
	result.Name = check.Name
	result.Severity = check.Severity

	return result
}

func runScriptCheck(check nixconfig.Healthcheck, timeout time.Duration) HealthcheckResult {
	result := HealthcheckResult{}

	if check.ScriptPath == nil || *check.ScriptPath == "" {
		result.Status = "skip"
		result.Message = "no script path"
		return result
	}

	scriptPath := *check.ScriptPath

	// Check if the script exists (it's a Nix store path)
	if _, err := os.Stat(scriptPath); err != nil {
		result.Status = "skip"
		result.Message = "script not found"
		return result
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, scriptPath)
	cmd.Env = os.Environ()
	output, err := cmd.CombinedOutput()

	if ctx.Err() == context.DeadlineExceeded {
		result.Status = "fail"
		result.Message = "timeout"
		return result
	}

	if err != nil {
		result.Status = "fail"
		msg := string(output)
		if len(msg) > 200 {
			msg = msg[:200] + "..."
		}
		if msg == "" {
			msg = err.Error()
		}
		result.Message = msg
		return result
	}

	result.Status = "pass"
	return result
}

func runHTTPCheck(check nixconfig.Healthcheck, timeout time.Duration) HealthcheckResult {
	result := HealthcheckResult{}

	if check.HTTPUrl == nil || *check.HTTPUrl == "" {
		result.Status = "skip"
		result.Message = "no HTTP URL"
		return result
	}

	client := &http.Client{Timeout: timeout}
	req, err := http.NewRequest(check.HTTPMethod, *check.HTTPUrl, nil)
	if err != nil {
		result.Status = "fail"
		result.Message = err.Error()
		return result
	}

	resp, err := client.Do(req)
	if err != nil {
		result.Status = "fail"
		result.Message = err.Error()
		return result
	}
	defer resp.Body.Close()

	if resp.StatusCode == check.HTTPExpectedStatus {
		result.Status = "pass"
	} else {
		result.Status = "fail"
		result.Message = fmt.Sprintf("got status %d, expected %d", resp.StatusCode, check.HTTPExpectedStatus)
	}
	return result
}

func runTCPCheck(check nixconfig.Healthcheck, timeout time.Duration) HealthcheckResult {
	result := HealthcheckResult{}

	if check.TCPHost == nil || check.TCPPort == nil {
		result.Status = "skip"
		result.Message = "no TCP host/port"
		return result
	}

	addr := fmt.Sprintf("%s:%d", *check.TCPHost, *check.TCPPort)
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		result.Status = "fail"
		result.Message = err.Error()
		return result
	}
	conn.Close()

	result.Status = "pass"
	return result
}

// LoadHealthcheckCache reads cached results from disk.
// Returns nil if cache doesn't exist or is expired.
func LoadHealthcheckCache(stateDir string) *HealthcheckCache {
	path := filepath.Join(stateDir, healthcheckCacheFile)

	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}

	var cache HealthcheckCache
	if err := json.Unmarshal(data, &cache); err != nil {
		return nil
	}

	// Check TTL
	if time.Since(cache.Timestamp) > healthcheckCacheTTL {
		return nil
	}

	return &cache
}

// SaveHealthcheckCache writes results to disk cache.
func SaveHealthcheckCache(stateDir string, results []HealthcheckResult) error {
	cache := HealthcheckCache{
		Version:   1,
		Timestamp: time.Now(),
		Results:   results,
	}

	data, err := json.MarshalIndent(cache, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal healthcheck cache: %w", err)
	}

	path := filepath.Join(stateDir, healthcheckCacheFile)
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return fmt.Errorf("create state dir: %w", err)
	}

	return os.WriteFile(path, data, 0o644)
}

// RunOrLoadHealthchecks returns cached results if within TTL, otherwise runs all
// checks fresh. This is the main entry point for non-MOTD healthcheck consumers
// (e.g., the `sp healthcheck` command). Results are persisted after running.
func RunOrLoadHealthchecks(stateDir string, checks []nixconfig.Healthcheck) []HealthcheckResult {
	if len(checks) == 0 {
		return nil
	}

	// Try cache first
	if cache := LoadHealthcheckCache(stateDir); cache != nil {
		return cache.Results
	}

	// Run checks
	results := RunHealthchecks(checks)

	// Persist to disk (best-effort)
	_ = SaveHealthcheckCache(stateDir, results)

	return results
}

// AggregateByModule groups results by module and computes per-module summaries.
// Insertion order is preserved so modules appear in the same order as the checks.
// Skipped checks don't count toward TotalChecks (only pass/fail do).
func AggregateByModule(results []HealthcheckResult) []ModuleHealthResult {
	if len(results) == 0 {
		return nil
	}

	moduleMap := make(map[string]*ModuleHealthResult)
	moduleOrder := []string{}

	for _, r := range results {
		m, ok := moduleMap[r.Module]
		if !ok {
			m = &ModuleHealthResult{
				Module:      r.Module,
				DisplayName: r.Module,
			}
			moduleMap[r.Module] = m
			moduleOrder = append(moduleOrder, r.Module)
		}

		if r.Status == "skip" {
			m.SkippedCount++
			continue
		}

		m.TotalChecks++
		switch r.Status {
		case "pass":
			m.PassingCount++
		case "fail", "error":
			m.FailingCount++
			// Track worst severity
			if severityRank(r.Severity) > severityRank(m.Severity) {
				m.Severity = r.Severity
			}
		}
	}

	// Maintain stable order
	out := make([]ModuleHealthResult, 0, len(moduleOrder))
	for _, name := range moduleOrder {
		if m := moduleMap[name]; m.TotalChecks > 0 {
			out = append(out, *m)
		}
	}
	return out
}

// severityRank maps proto enum strings to comparable integers for max() comparison.
func severityRank(s string) int {
	switch s {
	case "HEALTHCHECK_SEVERITY_CRITICAL":
		return 3
	case "HEALTHCHECK_SEVERITY_WARNING":
		return 2
	case "HEALTHCHECK_SEVERITY_INFO":
		return 1
	default:
		return 0
	}
}

// HealthSummaryFromResults computes the HealthSummary used by the MOTD from raw results.
func HealthSummaryFromResults(results []HealthcheckResult) HealthSummary {
	summary := HealthSummary{Enabled: len(results) > 0}

	for _, r := range results {
		if r.Status == "skip" {
			continue
		}
		summary.TotalChecks++
		switch r.Status {
		case "pass":
			summary.PassingCount++
		case "fail", "error":
			summary.FailingCount++
		}
	}

	return summary
}
