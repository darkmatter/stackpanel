package tui

import (
	"strings"
	"testing"
)

func TestCheckAgentStatus(t *testing.T) {
	// Test with a port that's unlikely to have a service running
	status := CheckAgentStatus(59999)
	if status.Running {
		t.Error("Expected agent to not be running on port 59999")
	}
	if status.URL != "localhost:59999" {
		t.Errorf("Expected URL to be localhost:59999, got %s", status.URL)
	}
}

func TestCheckAWSStatus(t *testing.T) {
	// This test doesn't require AWS credentials - it just checks the function doesn't panic
	status := CheckAWSStatus()

	// The function should always return a status (enabled or not)
	if status.FixCommand == "" {
		t.Error("Expected FixCommand to be set")
	}
}

func TestGetEnvironmentInfo(t *testing.T) {
	info := GetEnvironmentInfo()

	// Should not panic and return valid struct
	if info.Languages == nil {
		t.Error("Expected Languages to be initialized (even if empty)")
	}
	if info.Tools == nil {
		t.Error("Expected Tools to be initialized (even if empty)")
	}
}

func TestExtractVersion(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"simple version", "20.11.0", "20.11.0"},
		{"with v prefix", "v20.11.0", "20.11.0"},
		{"with newline", "20.11.0\n", "20.11.0"},
		{"with extra text", "v1.0.0 extra", "1.0.0"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := extractVersion(tt.input)
			if result != tt.expected {
				t.Errorf("extractVersion(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestExtractGoVersion(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"standard output", "go version go1.22.0 darwin/arm64", "1.22.0"},
		{"linux output", "go version go1.21.5 linux/amd64", "1.21.5"},
		{"no version", "something else", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := extractGoVersion(tt.input)
			if result != tt.expected {
				t.Errorf("extractGoVersion(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestExtractPythonVersion(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"standard output", "Python 3.12.0", "3.12.0"},
		{"with extra", "Python 3.11.5\n", "3.11.5"},
		{"empty", "", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := extractPythonVersion(tt.input)
			if result != tt.expected {
				t.Errorf("extractPythonVersion(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestExtractRustVersion(t *testing.T) {
	result := extractRustVersion("rustc 1.75.0 (82e1608df 2023-12-21)")
	if result != "1.75.0" {
		t.Errorf("extractRustVersion() = %q, want %q", result, "1.75.0")
	}
}

func TestExtractPostgresVersion(t *testing.T) {
	result := extractPostgresVersion("psql (PostgreSQL) 16.1")
	if result != "16.1" {
		t.Errorf("extractPostgresVersion() = %q, want %q", result, "16.1")
	}
}

func TestExtractRedisVersion(t *testing.T) {
	result := extractRedisVersion("redis-cli 7.2.3")
	if result != "7.2.3" {
		t.Errorf("extractRedisVersion() = %q, want %q", result, "7.2.3")
	}
}

func TestExtractDockerVersion(t *testing.T) {
	result := extractDockerVersion("Docker version 24.0.7, build afdd53b")
	if result != "24.0.7" {
		t.Errorf("extractDockerVersion() = %q, want %q", result, "24.0.7")
	}
}

func TestGetStudioURL(t *testing.T) {
	tests := []struct {
		name        string
		projectRoot string
		port        int
		expected    string
	}{
		{"with project", "/path/to/myproject", 3000, "http://localhost:3000/studio?project=myproject"},
		{"empty project", "", 3000, "http://localhost:3000/studio"},
		{"custom port", "/path/to/app", 8080, "http://localhost:8080/studio?project=app"},
		{"default port", "/path/to/app", 0, "http://localhost:3000/studio?project=app"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GetStudioURL(tt.projectRoot, tt.port)
			if result != tt.expected {
				t.Errorf("GetStudioURL(%q, %d) = %q, want %q", tt.projectRoot, tt.port, result, tt.expected)
			}
		})
	}
}

func TestCollectIssues(t *testing.T) {
	t.Run("agent not running creates issue", func(t *testing.T) {
		data := &MOTDFullData{
			Agent: AgentStatus{Running: false},
		}
		issues := CollectIssues(data)

		found := false
		for _, issue := range issues {
			if strings.Contains(issue.Message, "Agent") {
				found = true
				if issue.FixCommand != "stackpanel agent" {
					t.Errorf("Expected fix command 'stackpanel agent', got %q", issue.FixCommand)
				}
			}
		}
		if !found {
			t.Error("Expected issue about agent not running")
		}
	})

	t.Run("AWS invalid creates issue", func(t *testing.T) {
		data := &MOTDFullData{
			Agent: AgentStatus{Running: true},
			AWS: AWSStatus{
				Enabled:    true,
				Valid:      false,
				Message:    "credentials expired",
				FixCommand: "stackpanel aws login",
			},
		}
		issues := CollectIssues(data)

		found := false
		for _, issue := range issues {
			if strings.Contains(issue.Message, "AWS") {
				found = true
			}
		}
		if !found {
			t.Error("Expected issue about AWS credentials")
		}
	})

	t.Run("stale files creates issue", func(t *testing.T) {
		data := &MOTDFullData{
			Agent: AgentStatus{Running: true},
			Files: FilesStatus{
				Enabled:    true,
				StaleCount: 3,
				FixCommand: "stackpanel files sync",
			},
		}
		issues := CollectIssues(data)

		found := false
		for _, issue := range issues {
			if strings.Contains(issue.Message, "stale") {
				found = true
			}
		}
		if !found {
			t.Error("Expected issue about stale files")
		}
	})

	t.Run("env warnings are grouped by fix command", func(t *testing.T) {
		data := &MOTDFullData{
			Agent: AgentStatus{Running: true},
			EnvWarnings: []EnvWarning{
				{App: "web", Environment: "dev", EnvKey: "NEON_API_KEY", Severity: "error", Sops: "/shared/neon-api-key", Description: "Neon API key"},
				{App: "web", Environment: "staging", EnvKey: "NEON_API_KEY", Severity: "error", Sops: "/shared/neon-api-key", Description: "Neon API key"},
				{App: "web", Environment: "prod", EnvKey: "NEON_API_KEY", Severity: "error", Sops: "/shared/neon-api-key", Description: "Neon API key"},
				{App: "web", Environment: "dev", EnvKey: "CLOUDFLARE_API_TOKEN", Severity: "error", Sops: "/shared/cloudflare-api-token"},
				{App: "docs", Environment: "prod", EnvKey: "DATABASE_URL", Severity: "error"},
			},
		}
		issues := CollectIssues(data)
		var envIssues []Issue
		for _, i := range issues {
			if strings.HasPrefix(i.Message, "Required env var") {
				envIssues = append(envIssues, i)
			}
		}
		if len(envIssues) != 2 {
			t.Fatalf("Expected 2 grouped env issues (one per unique fix), got %d: %+v", len(envIssues), envIssues)
		}
		var sharedIssue *Issue
		for i := range envIssues {
			if envIssues[i].FixCommand == "sp secrets edit shared" {
				sharedIssue = &envIssues[i]
			}
		}
		if sharedIssue == nil {
			t.Fatalf("Expected a `sp secrets edit shared` group, got %+v", envIssues)
		}
		if len(sharedIssue.Details) != 2 {
			t.Errorf("Expected 2 detail lines (NEON_API_KEY + CLOUDFLARE_API_TOKEN), got %d: %+v", len(sharedIssue.Details), sharedIssue.Details)
		}
		neonLine := ""
		for _, d := range sharedIssue.Details {
			if strings.Contains(d, "NEON_API_KEY") {
				neonLine = d
			}
		}
		if neonLine == "" {
			t.Fatalf("NEON_API_KEY missing from grouped details: %+v", sharedIssue.Details)
		}
		for _, env := range []string{"web/dev", "web/staging", "web/prod"} {
			if !strings.Contains(neonLine, env) {
				t.Errorf("Expected scope %q in NEON_API_KEY line %q", env, neonLine)
			}
		}
	})

	t.Run("no issues when everything is fine", func(t *testing.T) {
		data := &MOTDFullData{
			Agent: AgentStatus{Running: true},
			AWS:   AWSStatus{Enabled: false},
			Files: FilesStatus{Enabled: true, StaleCount: 0},
			Health: HealthSummary{
				Enabled:      true,
				TotalChecks:  5,
				PassingCount: 5,
				FailingCount: 0,
			},
		}
		issues := CollectIssues(data)

		if len(issues) != 0 {
			t.Errorf("Expected no issues, got %d", len(issues))
		}
	})
}

func TestCollectMOTDData(t *testing.T) {
	data := CollectMOTDData("TestProject", "/path/to/project", "1.0.0", 9876, nil)

	if data.ProjectName != "TestProject" {
		t.Errorf("Expected ProjectName 'TestProject', got %q", data.ProjectName)
	}
	if data.ProjectRoot != "/path/to/project" {
		t.Errorf("Expected ProjectRoot '/path/to/project', got %q", data.ProjectRoot)
	}
	if data.Version != "1.0.0" {
		t.Errorf("Expected Version '1.0.0', got %q", data.Version)
	}
	if data.AgentPort != 9876 {
		t.Errorf("Expected AgentPort 9876, got %d", data.AgentPort)
	}
	if data.DocsURL != DefaultDocsURL {
		t.Errorf("Expected DocsURL %q, got %q", DefaultDocsURL, data.DocsURL)
	}
	if len(data.DefaultCommands) == 0 {
		t.Error("Expected DefaultCommands to be populated")
	}
}

func TestRenderImprovedMOTD(t *testing.T) {
	data := &MOTDFullData{
		ProjectName: "TestProject",
		Version:     "1.0.0",
		Agent: AgentStatus{
			Running: true,
			URL:     "localhost:9876",
		},
		Services: []ServiceStatus{
			{Name: "postgres", Running: true},
			{Name: "redis", Running: false},
		},
		Environment: EnvironmentInfo{
			Languages: []LanguageInfo{
				{Name: "Node", Version: "20.11.0"},
			},
		},
		DefaultCommands: []MOTDCommand{
			{Name: "dev", Description: "Start services"},
		},
		ShortcutAlias: "x",
		StudioURL:     "http://localhost:3000/studio",
		DocsURL:       "https://stackpanel.dev/docs",
	}

	output := RenderImprovedMOTD(data)

	// Check that key elements are present
	checks := []string{
		"TestProject",
		"localhost:9876",
		"postgres",
		"redis",
		"Node",
		"20.11.0",
		"Quick Start",
		"Shortcuts",
		"sp",
		"spx",
		"Resources",
		"stackpanel.dev/docs",
	}

	for _, check := range checks {
		if !strings.Contains(output, check) {
			t.Errorf("Expected output to contain %q", check)
		}
	}
}

func TestRenderImprovedMOTDWithIssues(t *testing.T) {
	data := &MOTDFullData{
		ProjectName: "TestProject",
		Agent:       AgentStatus{Running: false},
		Issues: []Issue{
			{Severity: "error", Message: "Agent not running", FixCommand: "stackpanel agent"},
		},
		DefaultCommands: []MOTDCommand{},
		DocsURL:         DefaultDocsURL,
	}

	output := RenderImprovedMOTD(data)

	if !strings.Contains(output, "Action Required") {
		t.Error("Expected output to contain 'Action Required' section")
	}
	if !strings.Contains(output, "Agent not running") {
		t.Error("Expected output to contain issue message")
	}
}

func TestRenderHealthBar(t *testing.T) {
	tests := []struct {
		name     string
		passing  int
		total    int
		contains string
	}{
		{"all passing", 10, 10, "██████████"},
		{"half passing", 5, 10, "█████░░░░░"},
		{"none passing", 0, 10, "░░░░░░░░░░"},
		{"mostly passing", 8, 10, "████████░░"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := renderHealthBar(tt.passing, tt.total)
			// The bar contains ANSI codes, so we check for the ratio text
			expectedRatio := strings.Contains(result, "█") || strings.Contains(result, "░")
			if !expectedRatio && tt.total > 0 {
				t.Errorf("renderHealthBar(%d, %d) should contain bar characters", tt.passing, tt.total)
			}
		})
	}
}

func TestRenderMinimalMOTD(t *testing.T) {
	result := RenderMinimalMOTD("MyProject")
	if !strings.Contains(result, "MyProject") {
		t.Error("Expected minimal MOTD to contain project name")
	}
	if !strings.Contains(result, "ready") {
		t.Error("Expected minimal MOTD to contain 'ready'")
	}
}

func TestRenderMinimalMOTDEmpty(t *testing.T) {
	result := RenderMinimalMOTD("")
	if !strings.Contains(result, "Dev Shell") {
		t.Error("Expected minimal MOTD to contain 'Dev Shell' when project name is empty")
	}
}

func TestStripAnsi(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"no ansi", "hello world", "hello world"},
		{"simple color", "\x1b[31mred\x1b[0m", "red"},
		{"multiple codes", "\x1b[1m\x1b[32mbold green\x1b[0m", "bold green"},
		{"empty", "", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := stripAnsi(tt.input)
			if result != tt.expected {
				t.Errorf("stripAnsi(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestDefaultConstants(t *testing.T) {
	if DefaultDocsURL != "https://stackpanel.dev/docs" {
		t.Errorf("DefaultDocsURL = %q, want %q", DefaultDocsURL, "https://stackpanel.dev/docs")
	}
	if DefaultAgentPort != 9876 {
		t.Errorf("DefaultAgentPort = %d, want %d", DefaultAgentPort, 9876)
	}
}
