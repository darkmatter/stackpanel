package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGroupOptions(t *testing.T) {
	options := OptionsJSON{
		"stackpanel.enable":                    NixOption{Type: "boolean"},
		"stackpanel.ports.base":                NixOption{Type: "int"},
		"stackpanel.ports.projectName":         NixOption{Type: "string"},
		"stackpanel.secrets.enable":            NixOption{Type: "boolean"},
		"stackpanel.globalServices.postgres":   NixOption{Type: "submodule"},
	}

	groups := groupOptions(options)

	if len(groups) != 4 {
		t.Errorf("expected 4 groups, got %d", len(groups))
	}

	if _, ok := groups["enable"]; !ok {
		t.Error("expected 'enable' group")
	}
	if _, ok := groups["ports"]; !ok {
		t.Error("expected 'ports' group")
	}
	if len(groups["ports"]) != 2 {
		t.Errorf("expected 2 options in ports group, got %d", len(groups["ports"]))
	}
	if _, ok := groups["secrets"]; !ok {
		t.Error("expected 'secrets' group")
	}
	if _, ok := groups["globalServices"]; !ok {
		t.Error("expected 'globalServices' group")
	}
}

func TestFormatValueInline(t *testing.T) {
	tests := []struct {
		name     string
		input    *NixValue
		expected string
	}{
		{
			name:     "nil value",
			input:    nil,
			expected: "_none_",
		},
		{
			name:     "simple value",
			input:    &NixValue{Text: "true"},
			expected: "`true`",
		},
		{
			name:     "short string",
			input:    &NixValue{Text: "hello world"},
			expected: "`hello world`",
		},
		{
			name:     "multiline value",
			input:    &NixValue{Text: "line1\nline2"},
			expected: "_see below_",
		},
		{
			name:     "long value",
			input:    &NixValue{Text: strings.Repeat("a", 70)},
			expected: "_see below_",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := formatValueInline(tt.input)
			if result != tt.expected {
				t.Errorf("expected %q, got %q", tt.expected, result)
			}
		})
	}
}

func TestFormatValueBlock(t *testing.T) {
	tests := []struct {
		name        string
		input       *NixValue
		expectEmpty bool
		expectNix   bool
	}{
		{
			name:        "nil value",
			input:       nil,
			expectEmpty: true,
		},
		{
			name:        "simple value - no block",
			input:       &NixValue{Text: "true"},
			expectEmpty: true,
		},
		{
			name:        "multiline value - returns block",
			input:       &NixValue{Text: "{\n  foo = bar;\n}"},
			expectEmpty: false,
			expectNix:   true,
		},
		{
			name:        "long value - returns block",
			input:       &NixValue{Text: strings.Repeat("a", 70)},
			expectEmpty: false,
			expectNix:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := formatValueBlock(tt.input)
			if tt.expectEmpty && result != "" {
				t.Errorf("expected empty string, got %q", result)
			}
			if !tt.expectEmpty && result == "" {
				t.Error("expected non-empty string")
			}
			if tt.expectNix && !strings.Contains(result, "```nix") {
				t.Errorf("expected nix code block, got %q", result)
			}
		})
	}
}

func TestFormatDescription(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "empty",
			input:    "",
			expected: "_No description provided._",
		},
		{
			name:     "plain text",
			input:    "Enable the service",
			expected: "Enable the service",
		},
		{
			name:     "with xml tags",
			input:    "Enable <literal>foo</literal> service",
			expected: "Enable foo service",
		},
		{
			name:     "with whitespace",
			input:    "  some text  ",
			expected: "some text",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := formatDescription(tt.input)
			if result != tt.expected {
				t.Errorf("expected %q, got %q", tt.expected, result)
			}
		})
	}
}

func TestGenerateCategoryMdx(t *testing.T) {
	options := OptionsJSON{
		"stackpanel.ports.base": NixOption{
			Type:        "int",
			Description: "Base port number",
			Default:     &NixValue{Text: "6400"},
		},
		"stackpanel.ports.projectName": NixOption{
			Type:        "string",
			Description: "Project name for port calculation",
		},
	}

	result := generateCategoryMdx("ports", options)

	// Check frontmatter
	if !strings.Contains(result, "title: Ports Options") {
		t.Error("expected title in frontmatter")
	}
	if !strings.Contains(result, "description: Configuration options for stackpanel.ports") {
		t.Error("expected description in frontmatter")
	}

	// Check options are included
	if !strings.Contains(result, "## `stackpanel.ports.base`") {
		t.Error("expected ports.base option")
	}
	if !strings.Contains(result, "## `stackpanel.ports.projectName`") {
		t.Error("expected ports.projectName option")
	}

	// Check table structure
	if !strings.Contains(result, "| **Type** | `int` |") {
		t.Error("expected type in table")
	}
	if !strings.Contains(result, "| **Default** | `6400` |") {
		t.Error("expected default in table")
	}
}

func TestGenerateIndexMdx(t *testing.T) {
	categories := []string{"ports", "secrets", "apps"}

	result := generateIndexMdx(categories)

	// Check frontmatter
	if !strings.Contains(result, "title: Options Reference") {
		t.Error("expected title in frontmatter")
	}

	// Check category links
	if !strings.Contains(result, "[Ports](./ports)") {
		t.Error("expected ports link")
	}
	if !strings.Contains(result, "[Secrets](./secrets)") {
		t.Error("expected secrets link")
	}
	if !strings.Contains(result, "[Apps](./apps)") {
		t.Error("expected apps link")
	}

	// Check quick start example
	if !strings.Contains(result, "```nix") {
		t.Error("expected nix code block in quick start")
	}
}

func TestFindReadmeFiles(t *testing.T) {
	// Create temp directory structure
	tmpDir := t.TempDir()

	// Create module directories with READMEs
	secretsDir := filepath.Join(tmpDir, "secrets")
	os.MkdirAll(secretsDir, 0755)
	os.WriteFile(filepath.Join(secretsDir, "README.md"), []byte("# Secrets\nSecrets management"), 0644)

	portsDir := filepath.Join(tmpDir, "ports")
	os.MkdirAll(portsDir, 0755)
	os.WriteFile(filepath.Join(portsDir, "README.md"), []byte("# Ports\nPort management"), 0644)

	// Create a directory without README
	emptyDir := filepath.Join(tmpDir, "empty")
	os.MkdirAll(emptyDir, 0755)

	// Create nested directory with README
	nestedDir := filepath.Join(tmpDir, "services", "postgres")
	os.MkdirAll(nestedDir, 0755)
	os.WriteFile(filepath.Join(nestedDir, "README.md"), []byte("# Postgres\nPostgres service"), 0644)

	readmes, err := findReadmeFiles(tmpDir, tmpDir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(readmes) != 3 {
		t.Errorf("expected 3 README files, got %d", len(readmes))
	}

	// Check that module names are correct
	moduleNames := make(map[string]bool)
	for _, r := range readmes {
		moduleNames[r.ModuleName] = true
	}

	if !moduleNames["secrets"] {
		t.Error("expected secrets module")
	}
	if !moduleNames["ports"] {
		t.Error("expected ports module")
	}
	if !moduleNames["postgres"] {
		t.Error("expected postgres module")
	}
}

func TestFindReadmeFiles_NonExistentDir(t *testing.T) {
	readmes, err := findReadmeFiles("/nonexistent/path", "/nonexistent/path")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(readmes) != 0 {
		t.Errorf("expected 0 README files, got %d", len(readmes))
	}
}

func TestConvertReadmeToMdx(t *testing.T) {
	tests := []struct {
		name           string
		content        string
		moduleName     string
		expectTitle    string
		expectDesc     string
		expectContent  string
	}{
		{
			name:          "with h1 title",
			content:       "# My Module\n\nThis is the description.\n\n## Usage\n\nSome usage info.",
			moduleName:    "mymodule",
			expectTitle:   "title: My Module",
			expectDesc:    "description: This is the description.",
			expectContent: "## Usage",
		},
		{
			name:          "title with trailing slash",
			content:       "# secrets/\n\nSecrets management module.",
			moduleName:    "secrets",
			expectTitle:   "title: secrets",
			expectDesc:    "description: Secrets management module.",
			expectContent: "",
		},
		{
			name:          "no h1 title",
			content:       "Some content without title.\n\n## Section",
			moduleName:    "noheader",
			expectTitle:   "title: Noheader",
			expectDesc:    "description: Documentation for the noheader module",
			expectContent: "Some content",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := convertReadmeToMdx(tt.content, tt.moduleName)

			if !strings.Contains(result, tt.expectTitle) {
				t.Errorf("expected title %q in result:\n%s", tt.expectTitle, result)
			}
			if !strings.Contains(result, tt.expectDesc) {
				t.Errorf("expected description %q in result:\n%s", tt.expectDesc, result)
			}
			if tt.expectContent != "" && !strings.Contains(result, tt.expectContent) {
				t.Errorf("expected content %q in result:\n%s", tt.expectContent, result)
			}
			// Should have frontmatter
			if !strings.HasPrefix(result, "---\n") {
				t.Error("expected frontmatter at start")
			}
		})
	}
}

func TestGenerateModulesIndexMdx(t *testing.T) {
	readmeFiles := []ReadmeFile{
		{ModuleName: "secrets", RelativePath: "secrets"},
		{ModuleName: "ports", RelativePath: "ports"},
		{ModuleName: "postgres", RelativePath: "services/postgres"},
	}

	result := generateModulesIndexMdx(readmeFiles)

	// Check frontmatter
	if !strings.Contains(result, "title: Module Documentation") {
		t.Error("expected title in frontmatter")
	}

	// Check module links (should be sorted)
	if !strings.Contains(result, "[Ports](./ports)") {
		t.Error("expected ports link")
	}
	if !strings.Contains(result, "[Postgres](./services/postgres)") {
		t.Error("expected postgres link")
	}
	if !strings.Contains(result, "[Secrets](./secrets)") {
		t.Error("expected secrets link")
	}
}

func TestGenerateModuleDocs(t *testing.T) {
	// Create temp directories
	modulesDir := t.TempDir()
	outputDir := t.TempDir()

	// Create a module with README
	secretsDir := filepath.Join(modulesDir, "secrets")
	os.MkdirAll(secretsDir, 0755)
	os.WriteFile(filepath.Join(secretsDir, "README.md"), []byte("# Secrets\n\nSecrets management module.\n\n## Usage\n\nConfigure secrets."), 0644)

	generatedModules, err := generateModuleDocs(modulesDir, outputDir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(generatedModules) != 1 {
		t.Errorf("expected 1 generated module, got %d", len(generatedModules))
	}

	// Check output files exist
	modulesOutputDir := filepath.Join(outputDir, "modules")
	if _, err := os.Stat(modulesOutputDir); os.IsNotExist(err) {
		t.Error("modules output directory not created")
	}

	secretsMdx := filepath.Join(modulesOutputDir, "secrets.mdx")
	if _, err := os.Stat(secretsMdx); os.IsNotExist(err) {
		t.Error("secrets.mdx not created")
	}

	indexMdx := filepath.Join(modulesOutputDir, "index.mdx")
	if _, err := os.Stat(indexMdx); os.IsNotExist(err) {
		t.Error("index.mdx not created")
	}

	// Check content of generated file
	content, _ := os.ReadFile(secretsMdx)
	if !strings.Contains(string(content), "title: Secrets") {
		t.Error("expected title in generated mdx")
	}
	if !strings.Contains(string(content), "## Usage") {
		t.Error("expected content preserved in generated mdx")
	}
}

func TestGenerateModuleDocs_EmptyDir(t *testing.T) {
	modulesDir := t.TempDir()
	outputDir := t.TempDir()

	generatedModules, err := generateModuleDocs(modulesDir, outputDir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(generatedModules) != 0 {
		t.Errorf("expected 0 generated modules, got %d", len(generatedModules))
	}
}
