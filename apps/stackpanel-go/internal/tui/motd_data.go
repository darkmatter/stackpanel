package tui

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

// MOTDFullData contains all data needed to render the improved MOTD
type MOTDFullData struct {
	// Project info
	ProjectName string
	ProjectRoot string
	Version     string

	// Status checks
	Agent       AgentStatus
	Services    []ServiceStatus
	AWS         AWSStatus
	Health      HealthSummary
	Files       FilesStatus
	Environment EnvironmentInfo

	// Commands
	DefaultCommands []MOTDCommand
	UserCommands    []MOTDCommand
	TotalCommands   int

	// Configuration
	ShortcutAlias string
	StudioURL     string
	DocsURL       string
	AgentPort     int

	// Missing flake inputs (from Nix config)
	MissingFlakeInputs []MissingFlakeInput

	// Computed
	Issues          []Issue
	UpdateAvailable *UpdateInfo
	ShellFreshness  ShellFreshness
}

// MissingFlakeInput represents a flake input that a module needs but isn't in flake.nix
type MissingFlakeInput struct {
	Name           string `json:"name"`
	URL            string `json:"url"`
	FollowsNixpkgs bool   `json:"followsNixpkgs"`
	RequiredBy     string `json:"requiredBy"`
}

// AgentStatus represents the status of the stackpanel agent
type AgentStatus struct {
	Running   bool
	URL       string
	ProjectID string
	Error     string
}

// AWSStatus represents the status of AWS credentials
type AWSStatus struct {
	Enabled    bool
	Valid      bool
	Message    string
	AccountID  string
	UserARN    string
	FixCommand string
}

// HealthSummary represents aggregated health check results
type HealthSummary struct {
	Enabled      bool
	TotalChecks  int
	PassingCount int
	FailingCount int
	WarningCount int
}

// FilesStatus represents the status of generated files
type FilesStatus struct {
	Enabled    bool
	TotalCount int
	StaleCount int
	StaleFiles []string // First few for display
	FixCommand string
}

// EnvironmentInfo represents enabled languages and tools
type EnvironmentInfo struct {
	Languages []LanguageInfo
	Tools     []ToolInfo
}

// LanguageInfo represents a detected language/runtime
type LanguageInfo struct {
	Name    string
	Version string
	Icon    string
}

// ToolInfo represents a detected tool
type ToolInfo struct {
	Name    string
	Version string
}

// Issue represents something requiring user action
type Issue struct {
	Severity   string // "error", "warning", "info"
	Message    string
	FixCommand string
}

// ShellFreshness represents the freshness status of the current shell
type ShellFreshness struct {
	Checked     bool          // Whether we were able to check freshness
	Fresh       bool          // True if shell matches current config
	StoredHash  string        // Hash computed when shell was entered
	CurrentHash string        // Hash computed now from current config files
	ShellAge    time.Duration // How long ago the shell was entered
	FixCommand  string        // Command to reload the shell
}

// UpdateInfo represents available update information
type UpdateInfo struct {
	CurrentVersion string
	LatestVersion  string
	UpdateCommand  string
}

// DefaultDocsURL is the default documentation URL
const DefaultDocsURL = "https://stackpanel.dev/docs"

// DefaultAgentPort is the default agent port
const DefaultAgentPort = 9876

// CheckAgentStatus checks if the stackpanel agent is running
func CheckAgentStatus(port int) AgentStatus {
	if port == 0 {
		port = DefaultAgentPort
	}

	url := fmt.Sprintf("http://localhost:%d", port)
	healthURL := fmt.Sprintf("%s/health", url)

	status := AgentStatus{
		Running: false,
		URL:     fmt.Sprintf("localhost:%d", port),
	}

	client := &http.Client{
		Timeout: 2 * time.Second,
	}

	resp, err := client.Get(healthURL)
	if err != nil {
		status.Error = "not running"
		return status
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		status.Running = true

		// Try to parse response for project info
		var healthResp struct {
			Status      string `json:"status"`
			HasProject  bool   `json:"has_project"`
			ProjectRoot string `json:"project_root"`
			AgentID     string `json:"agent_id"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&healthResp); err == nil {
			if healthResp.HasProject {
				status.ProjectID = healthResp.ProjectRoot
			}
		}
	} else {
		status.Error = fmt.Sprintf("unhealthy (status %d)", resp.StatusCode)
	}

	return status
}

// CheckAWSStatus checks if AWS credentials are valid
func CheckAWSStatus() AWSStatus {
	status := AWSStatus{
		Enabled:    false,
		Valid:      false,
		FixCommand: "stackpanel aws login",
	}

	// Check if AWS is configured via environment variables
	profileARN := os.Getenv("AWS_PROFILE_ARN")
	roleARN := os.Getenv("AWS_ROLE_ARN")
	accessKey := os.Getenv("AWS_ACCESS_KEY_ID")

	// AWS is enabled if we have either Roles Anywhere config or access keys
	if profileARN != "" || roleARN != "" || accessKey != "" {
		status.Enabled = true
	} else {
		status.Message = "not configured"
		return status
	}

	// Try to validate credentials using AWS STS get-caller-identity
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "aws", "sts", "get-caller-identity", "--output", "json")
	output, err := cmd.Output()
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			status.Message = "timeout checking credentials"
		} else {
			status.Message = "credentials invalid or expired"
		}
		return status
	}

	// Parse the response
	var identity struct {
		Account string `json:"Account"`
		Arn     string `json:"Arn"`
		UserID  string `json:"UserId"`
	}
	if err := json.Unmarshal(output, &identity); err == nil {
		status.Valid = true
		status.AccountID = identity.Account
		status.UserARN = identity.Arn
		status.Message = "authenticated"
	}

	return status
}

// CheckFilesStatus checks the status of generated files
func CheckFilesStatus(projectRoot string) FilesStatus {
	status := FilesStatus{
		Enabled:    false,
		FixCommand: "stackpanel files sync",
	}

	if projectRoot == "" {
		return status
	}

	// Try to get files status from the agent API
	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	resp, err := client.Get(fmt.Sprintf("http://localhost:%d/api/nix/files", DefaultAgentPort))
	if err != nil {
		// Agent not running, can't check files
		return status
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return status
	}

	var filesResp struct {
		Files []struct {
			Path         string `json:"path"`
			ExistsOnDisk bool   `json:"existsOnDisk"`
			IsStale      bool   `json:"isStale"`
			Enable       bool   `json:"enable"`
		} `json:"files"`
		TotalCount   int `json:"totalCount"`
		StaleCount   int `json:"staleCount"`
		EnabledCount int `json:"enabledCount"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&filesResp); err != nil {
		return status
	}

	status.Enabled = true
	status.TotalCount = filesResp.TotalCount
	status.StaleCount = filesResp.StaleCount

	// Collect first few stale files for display
	for _, f := range filesResp.Files {
		if f.IsStale && len(status.StaleFiles) < 3 {
			status.StaleFiles = append(status.StaleFiles, f.Path)
		}
	}

	return status
}

// GetEnvironmentInfo detects enabled languages and tools
func GetEnvironmentInfo() EnvironmentInfo {
	info := EnvironmentInfo{
		Languages: []LanguageInfo{},
		Tools:     []ToolInfo{},
	}

	// Check for common languages/runtimes
	languageChecks := []struct {
		name    string
		cmd     string
		args    []string
		icon    string
		extract func(string) string
	}{
		{"Node", "node", []string{"--version"}, "󰎙", extractVersion},
		{"Bun", "bun", []string{"--version"}, "󰟈", extractVersion},
		{"Go", "go", []string{"version"}, "", extractGoVersion},
		{"Python", "python3", []string{"--version"}, "", extractPythonVersion},
		{"Rust", "rustc", []string{"--version"}, "", extractRustVersion},
		{"Java", "java", []string{"--version"}, "", extractJavaVersion},
	}

	for _, check := range languageChecks {
		if version := getCommandVersion(check.cmd, check.args, check.extract); version != "" {
			info.Languages = append(info.Languages, LanguageInfo{
				Name:    check.name,
				Version: version,
				Icon:    check.icon,
			})
		}
	}

	// Check for common tools
	toolChecks := []struct {
		name    string
		cmd     string
		args    []string
		extract func(string) string
	}{
		{"PostgreSQL", "psql", []string{"--version"}, extractPostgresVersion},
		{"Redis", "redis-cli", []string{"--version"}, extractRedisVersion},
		{"Docker", "docker", []string{"--version"}, extractDockerVersion},
	}

	for _, check := range toolChecks {
		if version := getCommandVersion(check.cmd, check.args, check.extract); version != "" {
			info.Tools = append(info.Tools, ToolInfo{
				Name:    check.name,
				Version: version,
			})
		}
	}

	return info
}

// getCommandVersion runs a command and extracts the version
func getCommandVersion(cmd string, args []string, extract func(string) string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	c := exec.CommandContext(ctx, cmd, args...)
	output, err := c.Output()
	if err != nil {
		return ""
	}

	return extract(string(output))
}

// Version extraction helpers
func extractVersion(output string) string {
	// Handles "v20.11.0" or "20.11.0" style
	output = strings.TrimSpace(output)
	output = strings.TrimPrefix(output, "v")
	parts := strings.Fields(output)
	if len(parts) > 0 {
		return strings.TrimPrefix(parts[0], "v")
	}
	return output
}

func extractGoVersion(output string) string {
	// "go version go1.22.0 darwin/arm64"
	parts := strings.Fields(output)
	for _, p := range parts {
		if strings.HasPrefix(p, "go1.") || strings.HasPrefix(p, "go2.") {
			return strings.TrimPrefix(p, "go")
		}
	}
	return ""
}

func extractPythonVersion(output string) string {
	// "Python 3.12.0"
	parts := strings.Fields(output)
	if len(parts) >= 2 {
		return parts[1]
	}
	return ""
}

func extractRustVersion(output string) string {
	// "rustc 1.75.0 (82e1608df 2023-12-21)"
	parts := strings.Fields(output)
	if len(parts) >= 2 {
		return parts[1]
	}
	return ""
}

func extractJavaVersion(output string) string {
	// First line is like: openjdk 21.0.1 2023-10-17
	lines := strings.Split(output, "\n")
	if len(lines) > 0 {
		parts := strings.Fields(lines[0])
		if len(parts) >= 2 {
			return parts[1]
		}
	}
	return ""
}

func extractPostgresVersion(output string) string {
	// "psql (PostgreSQL) 16.1"
	parts := strings.Fields(output)
	if len(parts) >= 3 {
		return parts[2]
	}
	return ""
}

func extractRedisVersion(output string) string {
	// "redis-cli 7.2.3"
	parts := strings.Fields(output)
	if len(parts) >= 2 {
		return parts[1]
	}
	return ""
}

func extractDockerVersion(output string) string {
	// "Docker version 24.0.7, build afdd53b"
	parts := strings.Fields(output)
	if len(parts) >= 3 {
		return strings.TrimSuffix(parts[2], ",")
	}
	return ""
}

// GetUserCommands retrieves user-defined commands from nix config
// Returns the top N commands and the total count
func GetUserCommands(maxCommands int) ([]MOTDCommand, int) {
	if maxCommands == 0 {
		maxCommands = 5
	}

	// Try to get commands from the agent API
	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	resp, err := client.Get(fmt.Sprintf("http://localhost:%d/api/nix/config", DefaultAgentPort))
	if err != nil {
		return nil, 0
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, 0
	}

	var configResp struct {
		Devshell struct {
			CommandsSerializable map[string]struct {
				Name        string  `json:"name"`
				Description *string `json:"description"`
			} `json:"_commandsSerializable"`
		} `json:"devshell"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&configResp); err != nil {
		return nil, 0
	}

	commands := configResp.Devshell.CommandsSerializable
	if len(commands) == 0 {
		return nil, 0
	}

	// Sort commands: prioritize those with descriptions, then ungrouped, then alphabetical
	type cmdEntry struct {
		name string
		desc string
	}
	var entries []cmdEntry
	for name, cmd := range commands {
		desc := ""
		if cmd.Description != nil {
			desc = *cmd.Description
		}
		entries = append(entries, cmdEntry{name: name, desc: desc})
	}

	sort.Slice(entries, func(i, j int) bool {
		// Commands with descriptions first
		hasDescI := entries[i].desc != ""
		hasDescJ := entries[j].desc != ""
		if hasDescI != hasDescJ {
			return hasDescI
		}
		// Ungrouped commands (no colon) before grouped
		hasColonI := strings.Contains(entries[i].name, ":")
		hasColonJ := strings.Contains(entries[j].name, ":")
		if hasColonI != hasColonJ {
			return !hasColonI
		}
		// Alphabetical
		return entries[i].name < entries[j].name
	})

	// Take top N
	result := make([]MOTDCommand, 0, maxCommands)
	for i, e := range entries {
		if i >= maxCommands {
			break
		}
		result = append(result, MOTDCommand{
			Name:        e.name,
			Description: e.desc,
		})
	}

	return result, len(entries)
}

// GetHealthSummary retrieves health check summary from the agent
func GetHealthSummary() HealthSummary {
	summary := HealthSummary{
		Enabled: false,
	}

	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	resp, err := client.Get(fmt.Sprintf("http://localhost:%d/api/healthchecks?cached=true", DefaultAgentPort))
	if err != nil {
		return summary
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return summary
	}

	var healthResp struct {
		OverallStatus string `json:"overallStatus"`
		TotalHealthy  int    `json:"totalHealthy"`
		TotalChecks   int    `json:"totalChecks"`
		Modules       map[string]struct {
			HealthyCount int `json:"healthyCount"`
			TotalCount   int `json:"totalCount"`
		} `json:"modules"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&healthResp); err != nil {
		return summary
	}

	summary.Enabled = true
	summary.TotalChecks = healthResp.TotalChecks
	summary.PassingCount = healthResp.TotalHealthy
	summary.FailingCount = healthResp.TotalChecks - healthResp.TotalHealthy

	return summary
}

// CheckForUpdates checks if a newer version of stackpanel is available
func CheckForUpdates(currentVersion string) *UpdateInfo {
	// Skip if no version or development version
	if currentVersion == "" || currentVersion == "dev" || strings.HasPrefix(currentVersion, "0.0.0") {
		return nil
	}

	// Try to get latest version from GitHub releases API
	client := &http.Client{
		Timeout: 3 * time.Second,
	}

	resp, err := client.Get("https://api.github.com/repos/darkmatter/stackpanel/releases/latest")
	if err != nil {
		return nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil
	}

	var release struct {
		TagName string `json:"tag_name"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil
	}

	latestVersion := strings.TrimPrefix(release.TagName, "v")
	currentClean := strings.TrimPrefix(currentVersion, "v")

	// Simple version comparison (could be improved with semver library)
	if latestVersion != "" && latestVersion != currentClean {
		// Check if latest is actually newer (naive comparison)
		if latestVersion > currentClean {
			return &UpdateInfo{
				CurrentVersion: currentVersion,
				LatestVersion:  latestVersion,
				UpdateCommand:  "nix flake update",
			}
		}
	}

	return nil
}

// GetStudioURL returns the studio URL for the current project
func GetStudioURL(projectRoot string, port int) string {
	if port == 0 {
		port = 3000 // Default studio port
	}

	// Extract project name from path for the query param
	projectID := ""
	if projectRoot != "" {
		parts := strings.Split(projectRoot, "/")
		if len(parts) > 0 {
			projectID = parts[len(parts)-1]
		}
	}

	if projectID != "" {
		return fmt.Sprintf("http://localhost:%d/studio?project=%s", port, projectID)
	}
	return fmt.Sprintf("http://localhost:%d/studio", port)
}

// CheckShellFreshness checks if the current shell is fresh (matches config files)
// It compares STACKPANEL_SHELL_HASH (set at shell entry) with the current hash of config files
func CheckShellFreshness(projectRoot string) ShellFreshness {
	status := ShellFreshness{
		Checked:    false,
		Fresh:      true,                   // Assume fresh if we can't check
		FixCommand: "exit && direnv allow", // or: nix develop --impure
	}

	// Get the stored hash from when the shell was entered
	storedHash := os.Getenv("STACKPANEL_SHELL_HASH")
	if storedHash == "" {
		// Not in a stackpanel shell, or shell doesn't have hash support
		return status
	}
	status.StoredHash = storedHash
	status.Checked = true

	// Get shell entry time
	shellHashTimeStr := os.Getenv("STACKPANEL_SHELL_HASH_TIME")
	if shellHashTimeStr != "" {
		if shellTime, err := strconv.ParseInt(shellHashTimeStr, 10, 64); err == nil {
			status.ShellAge = time.Since(time.Unix(shellTime, 0))
		}
	}

	// Determine project root
	if projectRoot == "" {
		projectRoot = os.Getenv("STACKPANEL_ROOT")
	}
	if projectRoot == "" {
		// Can't compute hash without knowing project root
		return status
	}

	// Compute current hash of config files (same files as in Nix)
	currentHash := computeConfigHash(projectRoot)
	status.CurrentHash = currentHash

	// Compare hashes
	status.Fresh = (storedHash == currentHash)

	return status
}

// computeConfigHash computes an MD5 hash of the config files
// This must match the logic in nix/stackpanel/core/default.nix
func computeConfigHash(projectRoot string) string {
	configFiles := []string{
		filepath.Join(projectRoot, "flake.nix"),
		filepath.Join(projectRoot, "flake.lock"),
		filepath.Join(projectRoot, ".stackpanel", "config.nix"),
		filepath.Join(projectRoot, "devenv.nix"),
		filepath.Join(projectRoot, "devenv.yaml"),
	}

	h := md5.New()
	for _, filePath := range configFiles {
		f, err := os.Open(filePath)
		if err != nil {
			// File doesn't exist, skip it (same as Nix behavior)
			continue
		}
		_, err = io.Copy(h, f)
		f.Close()
		if err != nil {
			continue
		}
	}

	return hex.EncodeToString(h.Sum(nil))
}

// CollectIssues aggregates issues from various status checks
func CollectIssues(data *MOTDFullData) []Issue {
	var issues []Issue

	// Agent not running
	if !data.Agent.Running {
		issues = append(issues, Issue{
			Severity:   "error",
			Message:    "Agent not running",
			FixCommand: "stackpanel agent",
		})
	}

	// AWS issues
	if data.AWS.Enabled && !data.AWS.Valid {
		issues = append(issues, Issue{
			Severity:   "warning",
			Message:    "AWS " + data.AWS.Message,
			FixCommand: data.AWS.FixCommand,
		})
	}

	// Stale files
	if data.Files.Enabled && data.Files.StaleCount > 0 {
		msg := fmt.Sprintf("%d generated file(s) stale", data.Files.StaleCount)
		issues = append(issues, Issue{
			Severity:   "warning",
			Message:    msg,
			FixCommand: data.Files.FixCommand,
		})
	}

	// Health check failures
	if data.Health.Enabled && data.Health.FailingCount > 0 {
		msg := fmt.Sprintf("%d health check(s) failing", data.Health.FailingCount)
		issues = append(issues, Issue{
			Severity:   "warning",
			Message:    msg,
			FixCommand: "sp status",
		})
	}

	// Shell staleness
	if data.ShellFreshness.Checked && !data.ShellFreshness.Fresh {
		issues = append(issues, Issue{
			Severity:   "warning",
			Message:    "Shell is stale (config changed)",
			FixCommand: data.ShellFreshness.FixCommand,
		})
	}

	// Missing flake inputs
	for _, fi := range data.MissingFlakeInputs {
		msg := fmt.Sprintf("Module %q requires flake input %q", fi.RequiredBy, fi.Name)
		fixCmd := fmt.Sprintf("stackpanel flake add-input %s %s", fi.Name, fi.URL)
		issues = append(issues, Issue{
			Severity:   "warning",
			Message:    msg,
			FixCommand: fixCmd,
		})
	}

	return issues
}

// CollectMOTDData gathers all data needed for the MOTD
func CollectMOTDData(projectName, projectRoot, version string, agentPort int) *MOTDFullData {
	if agentPort == 0 {
		agentPort = DefaultAgentPort
	}

	data := &MOTDFullData{
		ProjectName:   projectName,
		ProjectRoot:   projectRoot,
		Version:       version,
		AgentPort:     agentPort,
		DocsURL:       DefaultDocsURL,
		ShortcutAlias: "x", // Default, could be read from config
	}

	// Collect status in parallel for better performance
	// For now, do it sequentially for simplicity

	// Agent status (fast, do first)
	data.Agent = CheckAgentStatus(agentPort)

	// Only check these if agent is running (they depend on agent API)
	if data.Agent.Running {
		data.Files = CheckFilesStatus(projectRoot)
		data.Health = GetHealthSummary()
		data.UserCommands, data.TotalCommands = GetUserCommands(5)
	}

	// These don't require the agent
	data.AWS = CheckAWSStatus()
	data.Environment = GetEnvironmentInfo()
	data.StudioURL = GetStudioURL(projectRoot, 3000)
	data.ShellFreshness = CheckShellFreshness(projectRoot)

	// Check for updates (can be slow, do last)
	data.UpdateAvailable = CheckForUpdates(version)

	// Default commands
	data.DefaultCommands = []MOTDCommand{
		{Name: "dev", Description: "Start all development services"},
		{Name: "dev stop", Description: "Stop all services"},
		{Name: "sp status", Description: "Open interactive dashboard"},
		{Name: "sp commands", Description: "List all available commands"},
	}

	// Collect issues based on all status checks
	data.Issues = CollectIssues(data)

	return data
}
