package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

// HealthStatus represents the current health status
type HealthStatus string

const (
	HealthStatusUnspecified HealthStatus = "HEALTH_STATUS_UNSPECIFIED"
	HealthStatusHealthy     HealthStatus = "HEALTH_STATUS_HEALTHY"
	HealthStatusDegraded    HealthStatus = "HEALTH_STATUS_DEGRADED"
	HealthStatusUnhealthy   HealthStatus = "HEALTH_STATUS_UNHEALTHY"
	HealthStatusUnknown     HealthStatus = "HEALTH_STATUS_UNKNOWN"
	HealthStatusDisabled    HealthStatus = "HEALTH_STATUS_DISABLED"
)

// HealthcheckType represents the type of healthcheck
type HealthcheckType string

const (
	HealthcheckTypeUnspecified HealthcheckType = "HEALTHCHECK_TYPE_UNSPECIFIED"
	HealthcheckTypeScript      HealthcheckType = "HEALTHCHECK_TYPE_SCRIPT"
	HealthcheckTypeNix         HealthcheckType = "HEALTHCHECK_TYPE_NIX"
	HealthcheckTypeHTTP        HealthcheckType = "HEALTHCHECK_TYPE_HTTP"
	HealthcheckTypeTCP         HealthcheckType = "HEALTHCHECK_TYPE_TCP"
)

// HealthcheckSeverity represents the severity of a healthcheck
type HealthcheckSeverity string

const (
	HealthcheckSeverityUnspecified HealthcheckSeverity = "HEALTHCHECK_SEVERITY_UNSPECIFIED"
	HealthcheckSeverityCritical    HealthcheckSeverity = "HEALTHCHECK_SEVERITY_CRITICAL"
	HealthcheckSeverityWarning     HealthcheckSeverity = "HEALTHCHECK_SEVERITY_WARNING"
	HealthcheckSeverityInfo        HealthcheckSeverity = "HEALTHCHECK_SEVERITY_INFO"
)

// Healthcheck represents a healthcheck definition from Nix config
type Healthcheck struct {
	ID                 string              `json:"id"`
	Name               string              `json:"name"`
	Description        *string             `json:"description,omitempty"`
	Type               HealthcheckType     `json:"type"`
	Severity           HealthcheckSeverity `json:"severity"`
	Script             *string             `json:"script,omitempty"`
	ScriptPath         *string             `json:"scriptPath,omitempty"`
	ScriptDrvPath      *string             `json:"scriptDrvPath,omitempty"`
	NixExpr            *string             `json:"nixExpr,omitempty"`
	HTTPUrl            *string             `json:"httpUrl,omitempty"`
	HTTPMethod         *string             `json:"httpMethod,omitempty"`
	HTTPExpectedStatus *int                `json:"httpExpectedStatus,omitempty"`
	TCPHost            *string             `json:"tcpHost,omitempty"`
	TCPPort            *int                `json:"tcpPort,omitempty"`
	Timeout            int                 `json:"timeout"`
	Interval           *int                `json:"interval,omitempty"`
	Module             string              `json:"module"`
	Tags               []string            `json:"tags,omitempty"`
	Enabled            bool                `json:"enabled"`
}

// HealthcheckResult represents the result of running a healthcheck
type HealthcheckResult struct {
	CheckID    string       `json:"checkId"`
	Status     HealthStatus `json:"status"`
	Message    *string      `json:"message,omitempty"`
	Error      *string      `json:"error,omitempty"`
	Output     *string      `json:"output,omitempty"`
	DurationMs int64        `json:"durationMs"`
	Timestamp  string       `json:"timestamp"`
	// Check contains the original healthcheck definition (for UI display)
	Check *Healthcheck `json:"check,omitempty"`
}

// ModuleHealth represents the health status for a module
type ModuleHealth struct {
	Module       string              `json:"module"`
	DisplayName  string              `json:"displayName"`
	Status       HealthStatus        `json:"status"`
	Checks       []HealthcheckResult `json:"checks"`
	HealthyCount int                 `json:"healthyCount"`
	TotalCount   int                 `json:"totalCount"`
	LastUpdated  string              `json:"lastUpdated"`
}

// HealthSummary represents the overall health summary
type HealthSummary struct {
	OverallStatus HealthStatus             `json:"overallStatus"`
	Modules       map[string]*ModuleHealth `json:"modules"`
	TotalHealthy  int                      `json:"totalHealthy"`
	TotalChecks   int                      `json:"totalChecks"`
	LastUpdated   string                   `json:"lastUpdated"`
}

// healthcheckCache stores the last healthcheck results
type healthcheckCache struct {
	mu          sync.RWMutex
	results     map[string]*HealthcheckResult
	lastUpdated time.Time
}

var globalHealthcheckCache = &healthcheckCache{
	results: make(map[string]*HealthcheckResult),
}

// handleHealthchecks handles healthcheck-related API requests
func (s *Server) handleHealthchecks(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleGetHealthchecks(w, r)
	case http.MethodPost:
		s.handleRunHealthchecks(w, r)
	default:
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// handleGetHealthchecks returns the current health status
func (s *Server) handleGetHealthchecks(w http.ResponseWriter, r *http.Request) {
	module := r.URL.Query().Get("module")
	checkID := r.URL.Query().Get("check")
	cached := r.URL.Query().Get("cached") != "false"

	// Get healthcheck definitions from config
	healthchecks, err := s.getHealthcheckDefinitions()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to get healthcheck definitions: "+err.Error())
		return
	}

	// If requesting a specific check
	if checkID != "" {
		for _, check := range healthchecks {
			if check.ID == checkID {
				var result *HealthcheckResult
				if cached {
					result = s.getCachedResult(checkID)
				}
				if result == nil {
					result = s.runHealthcheck(r.Context(), check)
					s.cacheResult(result)
				}
				s.writeAPI(w, http.StatusOK, result)
				return
			}
		}
		s.writeAPIError(w, http.StatusNotFound, "healthcheck not found: "+checkID)
		return
	}

	// Build health summary
	summary := s.buildHealthSummary(r.Context(), healthchecks, module, cached)
	s.writeAPI(w, http.StatusOK, summary)
}

// handleRunHealthchecks runs healthchecks and returns results
func (s *Server) handleRunHealthchecks(w http.ResponseWriter, r *http.Request) {
	module := r.URL.Query().Get("module")
	checkID := r.URL.Query().Get("check")

	// Get healthcheck definitions from config
	healthchecks, err := s.getHealthcheckDefinitions()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to get healthcheck definitions: "+err.Error())
		return
	}

	var checksToRun []Healthcheck
	for _, check := range healthchecks {
		if !check.Enabled {
			continue
		}
		if checkID != "" && check.ID != checkID {
			continue
		}
		if module != "" && check.Module != module {
			continue
		}
		checksToRun = append(checksToRun, check)
	}

	if len(checksToRun) == 0 {
		s.writeAPIError(w, http.StatusNotFound, "no healthchecks found matching criteria")
		return
	}

	// Run healthchecks in parallel
	results := s.runHealthchecksParallel(r.Context(), checksToRun)

	// Cache results
	for _, result := range results {
		s.cacheResult(&result)
	}

	// Build summary
	summary := s.buildHealthSummaryFromResults(healthchecks, results, module)

	// Broadcast SSE event
	s.broadcastSSE(SSEEvent{
		Event: "healthchecks.updated",
		Data:  summary,
	})

	s.writeAPI(w, http.StatusOK, summary)
}

// getHealthcheckDefinitions retrieves healthcheck definitions from Nix config
func (s *Server) getHealthcheckDefinitions() ([]Healthcheck, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	var config map[string]any
	var err error

	// Try FlakeWatcher first
	if s.flakeWatcher != nil {
		config, err = s.flakeWatcher.GetConfig(ctx)
	}

	// Fallback to direct evaluation
	if config == nil || err != nil {
		config, err = s.evaluateConfig()
		if err != nil {
			return nil, err
		}
	}

	// Extract healthchecksList from config
	healthchecksList, ok := config["healthchecksList"]
	if !ok {
		// No healthchecks configured
		return []Healthcheck{}, nil
	}

	// Convert to JSON and back to parse into struct
	data, err := json.Marshal(healthchecksList)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal healthchecks: %w", err)
	}

	var healthchecks []Healthcheck
	if err := json.Unmarshal(data, &healthchecks); err != nil {
		return nil, fmt.Errorf("failed to unmarshal healthchecks: %w", err)
	}

	return healthchecks, nil
}

// runHealthcheck executes a single healthcheck and returns the result
func (s *Server) runHealthcheck(ctx context.Context, check Healthcheck) *HealthcheckResult {
	start := time.Now()
	result := &HealthcheckResult{
		CheckID:   check.ID,
		Status:    HealthStatusUnknown,
		Timestamp: time.Now().Format(time.RFC3339),
	}

	// Create timeout context
	timeout := time.Duration(check.Timeout) * time.Second
	if timeout == 0 {
		timeout = 10 * time.Second
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	var err error
	var output string
	var healthy bool

	switch check.Type {
	case HealthcheckTypeScript:
		healthy, output, err = s.runScriptHealthcheck(ctx, check)
	case HealthcheckTypeHTTP:
		healthy, output, err = s.runHTTPHealthcheck(ctx, check)
	case HealthcheckTypeTCP:
		healthy, output, err = s.runTCPHealthcheck(ctx, check)
	case HealthcheckTypeNix:
		healthy, output, err = s.runNixHealthcheck(ctx, check)
	default:
		err = fmt.Errorf("unknown healthcheck type: %s", check.Type)
	}

	result.DurationMs = time.Since(start).Milliseconds()

	if err != nil {
		errStr := err.Error()
		result.Error = &errStr
		result.Status = HealthStatusUnhealthy
	} else if healthy {
		result.Status = HealthStatusHealthy
		msg := "Check passed"
		result.Message = &msg
	} else {
		result.Status = HealthStatusUnhealthy
		msg := "Check failed"
		result.Message = &msg
	}

	if output != "" {
		result.Output = &output
	}

	return result
}

// runScriptHealthcheck runs a script-based healthcheck
func (s *Server) runScriptHealthcheck(ctx context.Context, check Healthcheck) (bool, string, error) {
	var script string
	if check.ScriptPath != nil && *check.ScriptPath != "" {
		script = *check.ScriptPath
	} else if check.Script != nil {
		script = *check.Script
	} else {
		return false, "", fmt.Errorf("no script defined for script healthcheck")
	}

	var cmd *exec.Cmd
	if check.ScriptPath != nil && *check.ScriptPath != "" {
		if err := s.ensureScriptPath(*check.ScriptPath, check.ScriptDrvPath); err != nil {
			return false, "", err
		}
		cmd = exec.CommandContext(ctx, *check.ScriptPath)
	} else {
		cmd = exec.CommandContext(ctx, "sh", "-c", script)
	}

	cmd.Dir = s.config.ProjectRoot

	output, err := cmd.CombinedOutput()
	outputStr := strings.TrimSpace(string(output))

	if err != nil {
		if _, ok := err.(*exec.ExitError); ok {
			// Non-zero exit code means unhealthy
			return false, outputStr, nil
		}
		return false, outputStr, err
	}

	return true, outputStr, nil
}

// ensureScriptPath ensures the scriptPath exists by attempting to build the derivation if needed.
func (s *Server) ensureScriptPath(scriptPath string, scriptDrvPath *string) error {
	if _, err := os.Stat(scriptPath); err == nil {
		return nil
	}

	if scriptDrvPath == nil || *scriptDrvPath == "" {
		return fmt.Errorf("script path not found: %s", scriptPath)
	}

	// Attempt to build the derivation to realize the script in the store.
	// Use ^* suffix to build all outputs of the derivation (required for .drv paths)
	drvPathWithOutputs := *scriptDrvPath + "^*"
	res, err := s.exec.RunNix("build", "--no-link", drvPathWithOutputs)
	if err != nil {
		return fmt.Errorf("failed to build healthcheck script derivation: %w", err)
	}
	if res.ExitCode != 0 {
		return fmt.Errorf("failed to build healthcheck script derivation: %s", strings.TrimSpace(res.Stderr))
	}

	if _, err := os.Stat(scriptPath); err != nil {
		return fmt.Errorf("script path not found after build: %s", scriptPath)
	}

	return nil
}

// runHTTPHealthcheck runs an HTTP-based healthcheck
func (s *Server) runHTTPHealthcheck(ctx context.Context, check Healthcheck) (bool, string, error) {
	if check.HTTPUrl == nil || *check.HTTPUrl == "" {
		return false, "", fmt.Errorf("no URL defined for HTTP healthcheck")
	}

	method := "GET"
	if check.HTTPMethod != nil && *check.HTTPMethod != "" {
		method = *check.HTTPMethod
	}

	expectedStatus := 200
	if check.HTTPExpectedStatus != nil {
		expectedStatus = *check.HTTPExpectedStatus
	}

	req, err := http.NewRequestWithContext(ctx, method, *check.HTTPUrl, nil)
	if err != nil {
		return false, "", fmt.Errorf("failed to create request: %w", err)
	}

	client := &http.Client{
		Timeout: time.Duration(check.Timeout) * time.Second,
	}

	resp, err := client.Do(req)
	if err != nil {
		return false, "", err
	}
	defer resp.Body.Close()

	output := fmt.Sprintf("HTTP %d %s", resp.StatusCode, resp.Status)
	healthy := resp.StatusCode == expectedStatus

	return healthy, output, nil
}

// runTCPHealthcheck runs a TCP-based healthcheck
func (s *Server) runTCPHealthcheck(ctx context.Context, check Healthcheck) (bool, string, error) {
	if check.TCPHost == nil || *check.TCPHost == "" {
		return false, "", fmt.Errorf("no host defined for TCP healthcheck")
	}
	if check.TCPPort == nil {
		return false, "", fmt.Errorf("no port defined for TCP healthcheck")
	}

	addr := fmt.Sprintf("%s:%d", *check.TCPHost, *check.TCPPort)

	var d net.Dialer
	d.Timeout = time.Duration(check.Timeout) * time.Second

	conn, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return false, fmt.Sprintf("Failed to connect to %s", addr), nil
	}
	conn.Close()

	return true, fmt.Sprintf("Connected to %s", addr), nil
}

// runNixHealthcheck runs a Nix expression-based healthcheck
func (s *Server) runNixHealthcheck(ctx context.Context, check Healthcheck) (bool, string, error) {
	if check.NixExpr == nil || *check.NixExpr == "" {
		return false, "", fmt.Errorf("no Nix expression defined for Nix healthcheck")
	}

	// Evaluate the Nix expression
	cmd := exec.CommandContext(ctx, "nix", "eval", "--impure", "--expr", *check.NixExpr)
	cmd.Dir = s.config.ProjectRoot

	output, err := cmd.CombinedOutput()
	outputStr := strings.TrimSpace(string(output))

	if err != nil {
		return false, outputStr, err
	}

	// Nix eval returns "true" or "false" for boolean expressions
	healthy := outputStr == "true"
	return healthy, outputStr, nil
}

// runHealthchecksParallel runs multiple healthchecks in parallel
func (s *Server) runHealthchecksParallel(ctx context.Context, checks []Healthcheck) []HealthcheckResult {
	results := make([]HealthcheckResult, len(checks))
	var wg sync.WaitGroup

	for i, check := range checks {
		wg.Add(1)
		go func(idx int, c Healthcheck) {
			defer wg.Done()
			result := s.runHealthcheck(ctx, c)
			results[idx] = *result
		}(i, check)
	}

	wg.Wait()
	return results
}

// buildHealthSummary builds a health summary from the config
func (s *Server) buildHealthSummary(ctx context.Context, healthchecks []Healthcheck, moduleFilter string, useCached bool) *HealthSummary {
	summary := &HealthSummary{
		OverallStatus: HealthStatusHealthy,
		Modules:       make(map[string]*ModuleHealth),
		LastUpdated:   time.Now().Format(time.RFC3339),
	}

	// Group healthchecks by module
	moduleChecks := make(map[string][]Healthcheck)
	for _, check := range healthchecks {
		if !check.Enabled {
			continue
		}
		if moduleFilter != "" && check.Module != moduleFilter {
			continue
		}
		moduleChecks[check.Module] = append(moduleChecks[check.Module], check)
	}

	// Run/get results for each module
	for moduleName, checks := range moduleChecks {
		moduleHealth := &ModuleHealth{
			Module:      moduleName,
			DisplayName: moduleName,
			Status:      HealthStatusHealthy,
			Checks:      make([]HealthcheckResult, 0, len(checks)),
			TotalCount:  len(checks),
			LastUpdated: time.Now().Format(time.RFC3339),
		}

		for _, check := range checks {
			var result *HealthcheckResult
			if useCached {
				result = s.getCachedResult(check.ID)
			}
			if result == nil {
				result = s.runHealthcheck(ctx, check)
				s.cacheResult(result)
			}

			// Attach the check definition for UI display
			checkCopy := check
			result.Check = &checkCopy

			moduleHealth.Checks = append(moduleHealth.Checks, *result)

			if result.Status == HealthStatusHealthy {
				moduleHealth.HealthyCount++
				summary.TotalHealthy++
			}
			summary.TotalChecks++

			// Update module status based on check severity
			if result.Status != HealthStatusHealthy {
				severity := check.Severity
				if severity == HealthcheckSeverityCritical {
					moduleHealth.Status = HealthStatusUnhealthy
				} else if severity == HealthcheckSeverityWarning && moduleHealth.Status != HealthStatusUnhealthy {
					moduleHealth.Status = HealthStatusDegraded
				}
			}
		}

		summary.Modules[moduleName] = moduleHealth

		// Update overall status
		if moduleHealth.Status == HealthStatusUnhealthy {
			summary.OverallStatus = HealthStatusUnhealthy
		} else if moduleHealth.Status == HealthStatusDegraded && summary.OverallStatus != HealthStatusUnhealthy {
			summary.OverallStatus = HealthStatusDegraded
		}
	}

	return summary
}

// buildHealthSummaryFromResults builds a summary from pre-computed results
func (s *Server) buildHealthSummaryFromResults(healthchecks []Healthcheck, results []HealthcheckResult, moduleFilter string) *HealthSummary {
	summary := &HealthSummary{
		OverallStatus: HealthStatusHealthy,
		Modules:       make(map[string]*ModuleHealth),
		LastUpdated:   time.Now().Format(time.RFC3339),
	}

	// Create a map of results by check ID
	resultMap := make(map[string]HealthcheckResult)
	for _, result := range results {
		resultMap[result.CheckID] = result
	}

	// Create a map of checks by ID for severity lookup
	checkMap := make(map[string]Healthcheck)
	for _, check := range healthchecks {
		checkMap[check.ID] = check
	}

	// Group results by module
	for _, result := range results {
		check, ok := checkMap[result.CheckID]
		if !ok {
			continue
		}

		if moduleFilter != "" && check.Module != moduleFilter {
			continue
		}

		moduleName := check.Module
		if _, exists := summary.Modules[moduleName]; !exists {
			summary.Modules[moduleName] = &ModuleHealth{
				Module:      moduleName,
				DisplayName: moduleName,
				Status:      HealthStatusHealthy,
				Checks:      []HealthcheckResult{},
				LastUpdated: time.Now().Format(time.RFC3339),
			}
		}

		moduleHealth := summary.Modules[moduleName]

		// Attach the check definition for UI display
		resultWithCheck := result
		checkCopy := check
		resultWithCheck.Check = &checkCopy

		moduleHealth.Checks = append(moduleHealth.Checks, resultWithCheck)
		moduleHealth.TotalCount++
		summary.TotalChecks++

		if result.Status == HealthStatusHealthy {
			moduleHealth.HealthyCount++
			summary.TotalHealthy++
		} else {
			// Update module status based on severity
			if check.Severity == HealthcheckSeverityCritical {
				moduleHealth.Status = HealthStatusUnhealthy
			} else if check.Severity == HealthcheckSeverityWarning && moduleHealth.Status != HealthStatusUnhealthy {
				moduleHealth.Status = HealthStatusDegraded
			}
		}
	}

	// Update overall status
	for _, moduleHealth := range summary.Modules {
		if moduleHealth.Status == HealthStatusUnhealthy {
			summary.OverallStatus = HealthStatusUnhealthy
		} else if moduleHealth.Status == HealthStatusDegraded && summary.OverallStatus != HealthStatusUnhealthy {
			summary.OverallStatus = HealthStatusDegraded
		}
	}

	return summary
}

// getCachedResult retrieves a cached healthcheck result
func (s *Server) getCachedResult(checkID string) *HealthcheckResult {
	globalHealthcheckCache.mu.RLock()
	defer globalHealthcheckCache.mu.RUnlock()
	return globalHealthcheckCache.results[checkID]
}

// cacheResult stores a healthcheck result in the cache
func (s *Server) cacheResult(result *HealthcheckResult) {
	globalHealthcheckCache.mu.Lock()
	defer globalHealthcheckCache.mu.Unlock()
	globalHealthcheckCache.results[result.CheckID] = result
	globalHealthcheckCache.lastUpdated = time.Now()
}

// InvalidateHealthcheckCache clears the healthcheck cache
func InvalidateHealthcheckCache() {
	globalHealthcheckCache.mu.Lock()
	defer globalHealthcheckCache.mu.Unlock()
	globalHealthcheckCache.results = make(map[string]*HealthcheckResult)
	globalHealthcheckCache.lastUpdated = time.Time{}
}
