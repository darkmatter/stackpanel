package docgen

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/spf13/cobra"
)

func TestModuleFromDeclaration(t *testing.T) {
	tests := []struct {
		name     string
		declPath string
		want     string
	}{
		{
			name:     "module file – direct path",
			declPath: "/home/user/stackpanel/nix/stackpanel/modules/deploy/module.nix",
			want:     "deploy",
		},
		{
			name:     "module file – nix store path",
			declPath: "/nix/store/abc123-source/nix/stackpanel/modules/framework/module.nix",
			want:     "framework",
		},
		{
			name:     "module file – nested file inside module dir",
			declPath: "/nix/stackpanel/modules/bun/options.nix",
			want:     "bun",
		},
		{
			name:     "core options file",
			declPath: "/home/user/stackpanel/nix/stackpanel/core/options/apps.nix",
			want:     "apps",
		},
		{
			name:     "core options file – nix store path",
			declPath: "/nix/store/xyz-source/nix/stackpanel/core/options/secrets.nix",
			want:     "secrets",
		},
		{
			name:     "core options file – default.nix treated as its own group",
			declPath: "/nix/stackpanel/core/options/default.nix",
			want:     "default",
		},
		{
			name:     "private module (underscore prefix) is ignored",
			declPath: "/nix/stackpanel/modules/_template/module.nix",
			want:     "",
		},
		{
			name:     "unrecognised path returns empty string",
			declPath: "/some/random/path/options.nix",
			want:     "",
		},
		{
			name:     "empty string returns empty string",
			declPath: "",
			want:     "",
		},
		{
			name:     "core options sub-path (contains slash after stem) is ignored",
			declPath: "/nix/stackpanel/core/options/subdir/apps.nix",
			want:     "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := moduleFromDeclaration(tc.declPath)
			if got != tc.want {
				t.Errorf("moduleFromDeclaration(%q) = %q, want %q", tc.declPath, got, tc.want)
			}
		})
	}
}

func TestGroupOptions(t *testing.T) {
	options := OptionsJSON{
		"stackpanel.enable":                  NixOption{Type: "boolean"},
		"stackpanel.ports.base":              NixOption{Type: "int"},
		"stackpanel.ports.projectName":       NixOption{Type: "string"},
		"stackpanel.secrets.enable":          NixOption{Type: "boolean"},
		"stackpanel.globalServices.postgres": NixOption{Type: "submodule"},
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

// TestGroupOptions_DeclarationProvenance verifies that options sharing the same
// key prefix (e.g. apps.<name>.*) are split onto separate pages when they come
// from different source files.
func TestGroupOptions_DeclarationProvenance(t *testing.T) {
	deployDecl := "/nix/stackpanel/modules/deploy/module.nix"
	frameworkDecl := "/nix/stackpanel/modules/framework/module.nix"
	coreAppsDecl := "/nix/stackpanel/core/options/apps.nix"

	options := OptionsJSON{
		// Both keys start with "apps" but come from different modules.
		"stackpanel.apps.<name>.deploy.enable": NixOption{
			Type:         "boolean",
			Declarations: Declarations{{Name: deployDecl}},
		},
		"stackpanel.apps.<name>.deploy.host": NixOption{
			Type:         "string",
			Declarations: Declarations{{Name: deployDecl}},
		},
		"stackpanel.apps.<name>.framework.enable": NixOption{
			Type:         "boolean",
			Declarations: Declarations{{Name: frameworkDecl}},
		},
		// A core apps option with no module declaration falls back to "apps".
		"stackpanel.apps.<name>.port": NixOption{
			Type:         "int",
			Declarations: Declarations{{Name: coreAppsDecl}},
		},
	}

	groups := groupOptions(options)

	// deploy and framework must be separate groups.
	if _, ok := groups["deploy"]; !ok {
		t.Error("expected 'deploy' group derived from declaration path")
	}
	if _, ok := groups["framework"]; !ok {
		t.Error("expected 'framework' group derived from declaration path")
	}
	if len(groups["deploy"]) != 2 {
		t.Errorf("expected 2 options in 'deploy' group, got %d", len(groups["deploy"]))
	}
	if len(groups["framework"]) != 1 {
		t.Errorf("expected 1 option in 'framework' group, got %d", len(groups["framework"]))
	}

	// The core apps option should land in the "apps" group.
	if _, ok := groups["apps"]; !ok {
		t.Error("expected 'apps' group for core/options/apps.nix declaration")
	}

	// deploy and framework must NOT bleed into each other.
	for k := range groups["deploy"] {
		if strings.Contains(k, "framework") {
			t.Errorf("'deploy' group unexpectedly contains framework key %q", k)
		}
	}
	for k := range groups["framework"] {
		if strings.Contains(k, "deploy") {
			t.Errorf("'framework' group unexpectedly contains deploy key %q", k)
		}
	}
}

// TestGroupOptions_FallbackToKeyPrefix ensures that options without a
// recognisable declaration path still group correctly by key prefix.
func TestGroupOptions_FallbackToKeyPrefix(t *testing.T) {
	options := OptionsJSON{
		"stackpanel.secrets.enable": NixOption{
			Type:         "boolean",
			Declarations: Declarations{{Name: "/some/unknown/path/secrets.nix"}},
		},
		"stackpanel.secrets.backend": NixOption{
			Type: "string",
			// No declarations at all – pure fallback.
		},
	}

	groups := groupOptions(options)

	if _, ok := groups["secrets"]; !ok {
		t.Error("expected fallback 'secrets' group from key prefix")
	}
	if len(groups["secrets"]) != 2 {
		t.Errorf("expected 2 options in fallback 'secrets' group, got %d", len(groups["secrets"]))
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
			ReadOnly:    true,
		},
	}

	result := generateCategoryMdx("ports", options)

	// Check frontmatter now emitted by template
	if !strings.Contains(result, "title: ports") {
		t.Error("expected lowercase category title in frontmatter")
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
	if !strings.Contains(result, "| **Read Only** | `true` |") {
		t.Error("expected read-only property row for read-only option")
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
	if !strings.Contains(result, fmt.Sprintf("[Ports](./%s/ports)", DirnameReference)) {
		t.Error("expected ports link")
	}
	if !strings.Contains(result, fmt.Sprintf("[Secrets](./%s/secrets)", DirnameReference)) {
		t.Error("expected secrets link")
	}
	if !strings.Contains(result, fmt.Sprintf("[Apps](./%s/apps)", DirnameReference)) {
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
		name          string
		content       string
		moduleName    string
		expectTitle   string
		expectDesc    string
		expectContent string
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
			expectDesc:    "description: Some content without title.",
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
	readmeFiles := []DocSource{
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

	// Check output files exist (generateModuleDocs writes directly to outputDir)
	secretsMdx := filepath.Join(outputDir, "secrets.mdx")
	if _, err := os.Stat(secretsMdx); os.IsNotExist(err) {
		t.Error("secrets.mdx not created")
	}

	indexMdx := filepath.Join(outputDir, "index.mdx")
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

func TestGenerateCLIDocs(t *testing.T) {
	outputDir := t.TempDir()

	// Create a mock cobra command tree
	rootCmd := &cobra.Command{
		Use:   "testcli",
		Short: "Test CLI application",
		Long:  "A test CLI application for documentation generation.",
	}
	rootCmd.PersistentFlags().BoolP("verbose", "v", false, "Enable verbose output")
	rootCmd.PersistentFlags().Bool("no-color", false, "Disable color output")

	servicesCmd := &cobra.Command{
		Use:     "services",
		Aliases: []string{"svc", "s"},
		Short:   "Manage development services",
		Long:    "Manage project-local development services (PostgreSQL, Redis, etc.)",
	}

	startCmd := &cobra.Command{
		Use:   "start [service...]",
		Short: "Start services",
		Long:  "Start development services. If no services are specified, starts all.",
		Example: `  testcli services start
  testcli services start postgres
  testcli services start postgres redis`,
	}
	startCmd.Flags().Bool("no-tui", false, "Disable interactive TUI")

	stopCmd := &cobra.Command{
		Use:   "stop [service...]",
		Short: "Stop services",
	}

	servicesCmd.AddCommand(startCmd)
	servicesCmd.AddCommand(stopCmd)
	rootCmd.AddCommand(servicesCmd)

	statusCmd := &cobra.Command{
		Use:   "status",
		Short: "Show status of all services",
	}
	statusCmd.Flags().Bool("static", false, "Use static output instead of TUI")
	rootCmd.AddCommand(statusCmd)

	// Generate docs
	err := GenerateCLIDocs(rootCmd, outputDir)
	if err != nil {
		t.Fatalf("GenerateCLIDocs failed: %v", err)
	}

	// Check index.mdx exists
	indexPath := filepath.Join(outputDir, "index.mdx")
	if _, err := os.Stat(indexPath); os.IsNotExist(err) {
		t.Error("index.mdx not created")
	}

	// Check index content
	indexContent, _ := os.ReadFile(indexPath)
	if !strings.Contains(string(indexContent), "title: CLI Reference") {
		t.Error("expected CLI Reference title in index")
	}
	if !strings.Contains(string(indexContent), "[`services`](./services)") {
		t.Error("expected services command link in index")
	}
	if !strings.Contains(string(indexContent), "[`status`](./status)") {
		t.Error("expected status command link in index")
	}

	// Check services directory and index (has subcommands)
	servicesIndexPath := filepath.Join(outputDir, "services", "index.mdx")
	if _, err := os.Stat(servicesIndexPath); os.IsNotExist(err) {
		t.Error("services/index.mdx not created")
	}

	servicesContent, _ := os.ReadFile(servicesIndexPath)
	if !strings.Contains(string(servicesContent), "Manage development services") {
		t.Error("expected services description in content")
	}
	if !strings.Contains(string(servicesContent), "**Aliases:**") {
		t.Error("expected aliases section")
	}
	if !strings.Contains(string(servicesContent), "`svc`") {
		t.Error("expected svc alias")
	}
	if !strings.Contains(string(servicesContent), "[`start`](./start)") {
		t.Error("expected start subcommand link")
	}

	// Check start subcommand doc
	startPath := filepath.Join(outputDir, "services", "start.mdx")
	if _, err := os.Stat(startPath); os.IsNotExist(err) {
		t.Error("services/start.mdx not created")
	}

	startContent, _ := os.ReadFile(startPath)
	if !strings.Contains(string(startContent), "## Examples") {
		t.Error("expected examples section")
	}
	if !strings.Contains(string(startContent), "--no-tui") {
		t.Error("expected --no-tui flag documented")
	}

	// Check status.mdx (leaf command, no subcommands)
	statusPath := filepath.Join(outputDir, "status.mdx")
	if _, err := os.Stat(statusPath); os.IsNotExist(err) {
		t.Error("status.mdx not created")
	}

	statusContent, _ := os.ReadFile(statusPath)
	if !strings.Contains(string(statusContent), "--static") {
		t.Error("expected --static flag documented")
	}
}

func TestExtractFlags(t *testing.T) {
	cmd := &cobra.Command{Use: "test"}
	cmd.Flags().StringP("config", "c", "/etc/app.conf", "Path to config file")
	cmd.Flags().BoolP("verbose", "v", false, "Enable verbose output")
	cmd.Flags().Int("port", 8080, "Server port")

	flags := extractFlags(cmd.Flags())

	if len(flags) != 3 {
		t.Errorf("expected 3 flags, got %d", len(flags))
	}

	// Check flags are sorted by name
	expectedOrder := []string{"config", "port", "verbose"}
	for i, f := range flags {
		if f.Name != expectedOrder[i] {
			t.Errorf("expected flag %d to be %s, got %s", i, expectedOrder[i], f.Name)
		}
	}

	// Check config flag
	configFlag := flags[0]
	if configFlag.Shorthand != "c" {
		t.Errorf("expected shorthand 'c', got %s", configFlag.Shorthand)
	}
	if configFlag.Default != "/etc/app.conf" {
		t.Errorf("expected default '/etc/app.conf', got %s", configFlag.Default)
	}
	if configFlag.FlagSyntax != "--config, -c" {
		t.Errorf("expected flag syntax '--config, -c', got %s", configFlag.FlagSyntax)
	}
}

func TestEscapeMDX(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "angle brackets outside code are escaped",
			input:    "Use <token> in your request",
			expected: "Use \\<token\\> in your request",
		},
		{
			name:     "angle brackets inside fenced code block are preserved",
			input:    "```bash\ncurl -H \"X-Token: <token>\" http://localhost\n```",
			expected: "```bash\ncurl -H \"X-Token: <token>\" http://localhost\n```",
		},
		{
			name:     "angle brackets inside inline code are preserved",
			input:    "Use `<token>` in the header",
			expected: "Use `<token>` in the header",
		},
		{
			name:     "curly braces outside code are escaped",
			input:    "Object {key: value}",
			expected: "Object \\{key: value\\}",
		},
		{
			name:     "curly braces inside fenced code block are preserved",
			input:    "```js\nconst x = {a: 1}\n```",
			expected: "```js\nconst x = {a: 1}\n```",
		},
		{
			name:     "curly braces inside inline code are preserved",
			input:    "Returns `{ok: true}` on success",
			expected: "Returns `{ok: true}` on success",
		},
		{
			name:     "mixed content with code blocks and plain text",
			input:    "Send <data> here\n\n```bash\ncurl <url>\n```\n\nThen check <result>",
			expected: "Send \\<data\\> here\n\n```bash\ncurl <url>\n```\n\nThen check \\<result\\>",
		},
		{
			name:     "multiple inline code spans on one line",
			input:    "Use `<a>` and `<b>` but not <c>",
			expected: "Use `<a>` and `<b>` but not \\<c\\>",
		},
		{
			name:     "already escaped angle brackets are not double-escaped",
			input:    `Use \<token\> in the header`,
			expected: `Use \<token\> in the header`,
		},
		{
			name:     "already escaped braces are not double-escaped",
			input:    `Object \{key: value\}`,
			expected: `Object \{key: value\}`,
		},
		{
			name:     "no special characters passes through unchanged",
			input:    "This is plain text with no special chars.",
			expected: "This is plain text with no special chars.",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := escapeMDX(tt.input)
			if result != tt.expected {
				t.Errorf("escapeMDX(%q)\n  got:  %q\n  want: %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestGenerateCLIDocsEscapesAngleBrackets(t *testing.T) {
	outputDir := t.TempDir()

	rootCmd := &cobra.Command{
		Use:   "testcli",
		Short: "Test CLI",
	}

	tokenCmd := &cobra.Command{
		Use:   "test-token",
		Short: "Generate a test token",
		Long: `Generate a test pairing token.

Example:
  curl -H "X-Token: <token>" http://localhost:9876/api/...`,
	}
	rootCmd.AddCommand(tokenCmd)

	err := GenerateCLIDocs(rootCmd, outputDir)
	if err != nil {
		t.Fatalf("GenerateCLIDocs failed: %v", err)
	}

	content, err := os.ReadFile(filepath.Join(outputDir, "test-token.mdx"))
	if err != nil {
		t.Fatalf("failed to read test-token.mdx: %v", err)
	}

	s := string(content)

	// The <token> in the long description (outside code block) must be escaped
	if strings.Contains(s, "X-Token: <token>") {
		t.Error("expected <token> outside code block to be escaped, but it was not")
	}
	if !strings.Contains(s, `X-Token: \<token\>`) {
		t.Error("expected <token> to be escaped as \\<token\\> in description text")
	}
}

func TestIsSeparatorLine(t *testing.T) {
	tests := []struct {
		input    string
		expected bool
	}{
		{"==============================================================================", true},
		{"===", true},
		{"---", true},
		{"***", true},
		{"~~~", true},
		{"###", true},
		{"== ", false},  // trailing space means not purely separator chars
		{" === ", true}, // with surrounding space (trimmed)
		{"==", false},   // too short (< 3)
		{"=", false},
		{"", false},
		{"hello", false},
		{"module.nix - My Module", false},
		{"=-=", false}, // mixed characters
		{"a===", false},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result := isSeparatorLine(tt.input)
			if result != tt.expected {
				t.Errorf("isSeparatorLine(%q) = %v, want %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestExtractNixDocHeader_SkipsSeparators(t *testing.T) {
	tmpDir := t.TempDir()
	nixFile := filepath.Join(tmpDir, "module.nix")

	content := `# ==============================================================================
# module.nix - Bun Module Implementation
#
# Provides Bun/TypeScript application support.
#
# Features:
#   - Automatic bun2nix CLI in devshell
#   - Generated package.json with postinstall script
# ==============================================================================
{
  config = {};
}
`
	os.WriteFile(nixFile, []byte(content), 0644)

	header := extractNixDocHeader(nixFile)

	// Should not contain separator lines
	if strings.Contains(header, "====") {
		t.Errorf("expected separator lines to be stripped, got:\n%s", header)
	}

	// Should contain the actual title line
	if !strings.Contains(header, "module.nix - Bun Module Implementation") {
		t.Errorf("expected title line preserved, got:\n%s", header)
	}
}

func TestConvertNixHeaderToMdx_SanitizedTitle(t *testing.T) {
	// Simulate what extractNixDocHeader produces after separator stripping
	header := "module.nix - Bun Module Implementation\n\nProvides Bun/TypeScript application support.\n\nFeatures:\n  - Automatic bun2nix CLI in devshell\n  - Generated package.json"

	result := convertNixHeaderToMdx(header, "bun")

	// Title should NOT be "======" and should strip "module.nix - " prefix
	if strings.Contains(result, `title: "=="`) {
		t.Errorf("title should not be separator line, got:\n%s", result)
	}
	if strings.Contains(result, "module.nix") {
		t.Errorf("title should strip filename prefix, got:\n%s", result)
	}
	if !strings.Contains(result, "Bun Module Implementation") {
		t.Errorf("expected clean title 'Bun Module Implementation', got:\n%s", result)
	}
}

func TestConvertNixHeaderToMdx_PlainTitle(t *testing.T) {
	// Some headers don't have the "filename.nix - " prefix
	header := "Deployment Module\n\nAggregates all deployment provider modules.\n\nSupported hosts:\n  - cloudflare\n  - fly"

	result := convertNixHeaderToMdx(header, "deployment")

	if !strings.Contains(result, "title: Deployment Module") {
		t.Errorf("expected plain title 'Deployment Module', got:\n%s", result)
	}
}

func TestBuildUsageString(t *testing.T) {
	rootCmd := &cobra.Command{Use: "app"}
	subCmd := &cobra.Command{Use: "sub"}
	leafCmd := &cobra.Command{Use: "leaf [args...]"}

	rootCmd.AddCommand(subCmd)
	subCmd.AddCommand(leafCmd)

	usage := buildUsageString(leafCmd)
	expected := "app sub leaf [args...]"
	if usage != expected {
		t.Errorf("expected %q, got %q", expected, usage)
	}
}
