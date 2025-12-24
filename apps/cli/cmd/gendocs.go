package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/spf13/cobra"
)

// NixOption represents a single Nix option from the JSON export
type NixOption struct {
	Declarations []struct {
		Name string  `json:"name"`
		URL  *string `json:"url"`
	} `json:"declarations"`
	Default     *NixValue `json:"default"`
	Description string    `json:"description"`
	Example     *NixValue `json:"example"`
	Loc         []string  `json:"loc"`
	ReadOnly    bool      `json:"readOnly"`
	Type        string    `json:"type"`
}

// NixValue represents a Nix value (default or example)
type NixValue struct {
	Text  string `json:"text"`
	Type  string `json:"_type,omitempty"`
}

// OptionsJSON is the top-level structure of the Nix options JSON
type OptionsJSON map[string]NixOption

// DocSource represents a discovered documentation source (README.md or .nix header)
type DocSource struct {
	Path         string
	RelativePath string
	ModuleName   string
	IsNixFile    bool // true if extracted from .nix file header, false for README.md
}

const (
	DirnameReference = "reference"
	DirnameModules   = "modules"
	DirnameDevenv		= "devenv"
)

var gendocsCmd = &cobra.Command{
	Use:   "gendocs <options.json> <output-dir> [modules-dir]",
	Short: "Generate MDX documentation from Nix options JSON",
	Long: `Generate MDX documentation from Nix options JSON and module README files.

This command reads the Nix options JSON file and generates MDX documentation
files suitable for use with documentation frameworks like Fumadocs.

If a modules directory is provided, it will also scan for README.md files
in subdirectories and generate corresponding MDX documentation pages.`,
	Args: cobra.RangeArgs(2, 3),
	RunE: runGenDocs,
}

func init() {
	rootCmd.AddCommand(gendocsCmd)
}

func runGenDocs(cmd *cobra.Command, args []string) error {
	optionsPath := args[0]
	docsDir := args[1]
	var nixModulesDir string
	if len(args) > 2 {
		nixModulesDir = args[2]
	}

	outputDir := fmt.Sprintf("%s/%s", docsDir, DirnameReference)
	modulesOutputDir := fmt.Sprintf("%s/%s", docsDir, DirnameModules)
	devenvDir := fmt.Sprintf("%s/%s", docsDir, DirnameDevenv)

	// Clean up old generated files to prevent stale content
	for _, dir := range []string{outputDir, modulesOutputDir, devenvDir} {
		if err := os.RemoveAll(dir); err != nil {
			fmt.Printf("Warning: failed to clean %s: %v\n", dir, err)
		}
	}

	// Read and parse options JSON
	fmt.Printf("Reading options from: %s\n", optionsPath)
	optionsData, err := os.ReadFile(optionsPath)
	if err != nil {
		return fmt.Errorf("failed to read options file: %w", err)
	}

	var options OptionsJSON
	if err := json.Unmarshal(optionsData, &options); err != nil {
		return fmt.Errorf("failed to parse options JSON: %w", err)
	}

	fmt.Printf("Found %d options\n", len(options))

	// Group options by category
	groups := groupOptions(options)
	categories := make([]string, 0, len(groups))
	for cat := range groups {
		categories = append(categories, cat)
	}
	sort.Strings(categories)

	fmt.Printf("Categories: %s\n", strings.Join(categories, ", "))

	// Ensure output directories exist
	dirs := []string{outputDir, modulesOutputDir, devenvDir}
	if err := mkDirs(dirs...); err != nil {
		return fmt.Errorf("failed to create output directories: %w", err)
	}

	// Generate index
	indexPath := filepath.Join(outputDir, "index.mdx")
	if err := os.WriteFile(indexPath, []byte(generateIndexMdx(categories)), 0644); err != nil {
		return fmt.Errorf("failed to write index: %w", err)
	}
	fmt.Printf("  ✓ %s\n", indexPath)
	// devenvPath := filepath.Join(devenvDir, "index.mdx")
	// if err := os.WriteFile(devenvPath, []byte(generateIndexMdx(categories)), 0644); err != nil {
	// 	return fmt.Errorf("failed to write index: %w", err)
	// }
	// fmt.Printf("  ✓ %s\n", devenvPath)

	// Generate category pages
	for category, opts := range groups {
		categoryPath := filepath.Join(outputDir, category+".mdx")
		if err := os.WriteFile(categoryPath, []byte(generateCategoryMdx(category, opts)), 0644); err != nil {
			return fmt.Errorf("failed to write category %s: %w", category, err)
		}
		fmt.Printf("  ✓ %s (%d options)\n", categoryPath, len(opts))
	}

	fmt.Printf("\nGenerated %d reference files\n", len(categories)+1)

	// Generate module documentation from README files and .nix headers
	if nixModulesDir != "" {
		generatedModules, err := generateModuleDocs(nixModulesDir, modulesOutputDir)
		if err != nil {
			return fmt.Errorf("failed to generate module docs: %w", err)
		}
		if len(generatedModules) > 0 {
			fmt.Printf("\nGenerated %d module doc(s)\n", len(generatedModules))
		}
	}

	return nil
}

func mkDirs(paths ...string) error {
	for _, p := range paths {
		if err := os.MkdirAll(p, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", p, err)
		}
	}
	return nil
}

// groupOptions groups options by their top-level category
func groupOptions(options OptionsJSON) map[string]OptionsJSON {
	groups := make(map[string]OptionsJSON)
	// Match devenv shell prefix: perSystem.<system>.devenv.shells.<name>.
	regexDevenv := regexp.MustCompile(`^perSystem\.[^.]+\.devenv\.shells\.[^.]+\.`)

	for path, opt := range options {
		var category string

		// Strip devenv shell prefix if present
		// e.g., "perSystem.aarch64-darwin.devenv.shells.default.stackpanel.apps" -> "stackpanel.apps"
		cleanPath := regexDevenv.ReplaceAllString(path, "")

		// Remove 'stackpanel.' prefix if present
		cleanPath = strings.TrimPrefix(cleanPath, "stackpanel.")

		// Get first segment as category
		parts := strings.Split(cleanPath, ".")
		if len(parts) > 0 && parts[0] != "" {
			category = parts[0]
		} else {
			category = "core"
		}

		if groups[category] == nil {
			groups[category] = make(OptionsJSON)
		}

		// Store with cleaned path for display
		groups[category][cleanPath] = opt
	}

	return groups
}

// formatValueInline formats a Nix value for display in a table cell
func formatValueInline(val *NixValue) string {
	if val == nil {
		return "_none_"
	}
	text := strings.TrimSpace(val.Text)
	// For simple single-line values, use inline code
	if !strings.Contains(text, "\n") && len(text) < 60 {
		return "`" + text + "`"
	}
	// For multi-line or long values, indicate there's a default
	return "_see below_"
}

// formatValueBlock formats a Nix value as a code block
func formatValueBlock(val *NixValue) string {
	if val == nil {
		return ""
	}
	text := strings.TrimSpace(val.Text)
	// Only return a block if it's multi-line or long
	if strings.Contains(text, "\n") || len(text) >= 60 {
		return "```nix\n" + text + "\n```"
	}
	return ""
}

// formatDescription converts option description (may contain markdown)
func formatDescription(desc string) string {
	if desc == "" {
		return "_No description provided._"
	}
	// Clean up any docbook/xml remnants
	result := desc
	// Simple tag removal (could be more sophisticated)
	for strings.Contains(result, "<") && strings.Contains(result, ">") {
		start := strings.Index(result, "<")
		end := strings.Index(result, ">")
		if start < end {
			result = result[:start] + result[end+1:]
		} else {
			break
		}
	}
	return strings.TrimSpace(result)
}

// generateCategoryMdx generates MDX for a single category
func generateCategoryMdx(category string, options OptionsJSON) string {
	title := strings.ToUpper(category[:1]) + category[1:]

	// Sort options by path
	paths := make([]string, 0, len(options))
	for path := range options {
		paths = append(paths, path)
	}
	sort.Strings(paths)

	var sb strings.Builder
	header, err := RenderCategoryHeader(title, category)
	if err != nil {
		// Fallback to simple header on error
		header = fmt.Sprintf("# %s Options\n\n", title)
	}
	sb.WriteString(header)

	for _, path := range paths {
		opt := options[path]
		defaultBlock := formatValueBlock(opt.Default)
		exampleBlock := formatValueBlock(opt.Example)

		sb.WriteString(fmt.Sprintf("## `%s`\n\n", path))
		sb.WriteString(formatDescription(opt.Description) + "\n\n")
		sb.WriteString("| Property | Value |\n")
		sb.WriteString("|----------|-------|\n")
		sb.WriteString(fmt.Sprintf("| **Type** | `%s` |\n", opt.Type))
		sb.WriteString(fmt.Sprintf("| **Default** | %s |\n", formatValueInline(opt.Default)))
		if opt.ReadOnly {
			sb.WriteString("| **Read Only** | `true` |\n")
		}

		// Show default as a code block if it's multi-line
		if defaultBlock != "" {
			sb.WriteString("\n**Default:**\n\n")
			sb.WriteString(defaultBlock + "\n\n")
		}

		if opt.Example != nil {
			sb.WriteString("\n**Example:**\n\n")
			if exampleBlock != "" {
				sb.WriteString(exampleBlock + "\n\n")
			} else {
				sb.WriteString("`" + opt.Example.Text + "`\n\n")
			}
		}

		sb.WriteString("\n---\n\n")
	}

	return sb.String()
}

// generateIndexMdx generates the index page
func generateIndexMdx(categories []string) string {
	var categoryLinks strings.Builder
	for _, cat := range categories {
		title := strings.ToUpper(cat[:1]) + cat[1:]
		categoryLinks.WriteString(fmt.Sprintf("  - [%s](./%s/%s)\n", title, DirnameReference, cat))
	}

	result, err := RenderIndex(categoryLinks.String())
	if err != nil {
		// Fallback on error
		return "# Options Reference\n\n" + categoryLinks.String()
	}
	return result
}

// findReadmeFiles recursively finds README.md files in subdirectories
func findReadmeFiles(dir string, baseDir string) ([]DocSource, error) {
	var results []DocSource

	if _, err := os.Stat(dir); os.IsNotExist(err) {
		return results, nil
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		fullPath := filepath.Join(dir, entry.Name())
		readmePath := filepath.Join(fullPath, "README.md")

		// Check for README.md in this directory
		if _, err := os.Stat(readmePath); err == nil {
			relativePath, _ := filepath.Rel(baseDir, fullPath)
			results = append(results, DocSource{
				Path:         readmePath,
				RelativePath: relativePath,
				ModuleName:   entry.Name(),
				IsNixFile:    false,
			})
		}

		// Recurse into subdirectories
		subResults, err := findReadmeFiles(fullPath, baseDir)
		if err != nil {
			return nil, err
		}
		results = append(results, subResults...)
	}

	return results, nil
}

// findNixDocHeaders finds .nix files with documentation headers (multi-line comments at the start)
func findNixDocHeaders(dir string, baseDir string) ([]DocSource, error) {
	var results []DocSource

	if _, err := os.Stat(dir); os.IsNotExist(err) {
		return results, nil
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	for _, entry := range entries {
		fullPath := filepath.Join(dir, entry.Name())

		if entry.IsDir() {
			// Skip directories that have a README.md (those are handled separately)
			readmePath := filepath.Join(fullPath, "README.md")
			if _, err := os.Stat(readmePath); err == nil {
				continue
			}

			// Check for default.nix with doc header in this directory
			defaultNixPath := filepath.Join(fullPath, "default.nix")
			if docHeader := extractNixDocHeader(defaultNixPath); docHeader != "" {
				relativePath, _ := filepath.Rel(baseDir, fullPath)
				results = append(results, DocSource{
					Path:         defaultNixPath,
					RelativePath: relativePath,
					ModuleName:   entry.Name(),
					IsNixFile:    true,
				})
			}

			// Recurse into subdirectories
			subResults, err := findNixDocHeaders(fullPath, baseDir)
			if err != nil {
				return nil, err
			}
			results = append(results, subResults...)
		} else if strings.HasSuffix(entry.Name(), ".nix") && entry.Name() != "default.nix" {
			// Check for standalone .nix files with doc headers
			if docHeader := extractNixDocHeader(fullPath); docHeader != "" {
				// Use filename without .nix as module name
				moduleName := strings.TrimSuffix(entry.Name(), ".nix")
				relativePath, _ := filepath.Rel(baseDir, dir)
				if relativePath == "." {
					relativePath = moduleName
				} else {
					relativePath = filepath.Join(relativePath, moduleName)
				}
				results = append(results, DocSource{
					Path:         fullPath,
					RelativePath: relativePath,
					ModuleName:   moduleName,
					IsNixFile:    true,
				})
			}
		}
	}

	return results, nil
}

// extractNixDocHeader extracts the documentation header from a .nix file
// Returns the content if the file starts with a multi-line comment block (5+ lines)
func extractNixDocHeader(path string) string {
	content, err := os.ReadFile(path)
	if err != nil {
		return ""
	}

	lines := strings.Split(string(content), "\n")
	if len(lines) < 5 {
		return ""
	}

	// Check if file starts with # comment lines
	var docLines []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") {
			// Remove the # prefix and leading space
			docLine := strings.TrimPrefix(trimmed, "#")
			docLine = strings.TrimPrefix(docLine, " ")
			docLines = append(docLines, docLine)
		} else if trimmed == "" && len(docLines) > 0 {
			// Allow empty lines within the doc block
			docLines = append(docLines, "")
		} else {
			// Hit non-comment, non-empty line - end of doc block
			break
		}
	}

	// Require at least 5 lines to be considered a doc header
	if len(docLines) < 5 {
		return ""
	}

	return strings.TrimSpace(strings.Join(docLines, "\n"))
}

// convertReadmeToMdx converts README.md content to MDX with frontmatter
func convertReadmeToMdx(readmeContent string, moduleName string) string {
	return convertDocToMdx(readmeContent, moduleName, false)
}

// convertNixHeaderToMdx converts a .nix doc header to MDX with frontmatter
func convertNixHeaderToMdx(docHeader string, moduleName string) string {
	return convertDocToMdx(docHeader, moduleName, true)
}

// convertDocToMdx converts documentation content to MDX with frontmatter
func convertDocToMdx(content string, moduleName string, isNixHeader bool) string {
	lines := strings.Split(content, "\n")

	// Default title and description
	title := strings.ToUpper(moduleName[:1]) + moduleName[1:]
	description := fmt.Sprintf("Documentation for the %s module", moduleName)
	contentStartIndex := 0

	// Look for title in first few lines
	// For .nix headers, the first non-empty line is often the title (without #)
	// For README.md, look for # heading
	maxLines := 5
	if len(lines) < maxLines {
		maxLines = len(lines)
	}

	for i := 0; i < maxLines; i++ {
		line := lines[i]
		trimmedLine := strings.TrimSpace(line)

		// Skip empty lines at the start
		if trimmedLine == "" && contentStartIndex == 0 {
			continue
		}

		var foundTitle bool
		var extractedTitle string

		if isNixHeader {
			// For .nix headers, first non-empty line is the title
			if trimmedLine != "" && !strings.HasPrefix(trimmedLine, "-") {
				extractedTitle = trimmedLine
				foundTitle = true
			}
		} else {
			// For README.md, look for # heading
			if strings.HasPrefix(line, "# ") {
				extractedTitle = strings.TrimPrefix(line, "# ")
				foundTitle = true
			}
		}

		if foundTitle {
			// Clean up title
			title = strings.TrimSuffix(extractedTitle, "/")
			title = strings.TrimSpace(title)
			contentStartIndex = i + 1

			// Look for description in the next non-empty line
			for j := i + 1; j < len(lines) && j < i+5; j++ {
				nextLine := strings.TrimSpace(lines[j])
				if nextLine != "" && !strings.HasPrefix(nextLine, "#") && !strings.HasPrefix(nextLine, "-") {
					description = nextLine
					break
				}
			}
			break
		}
	}

	// Get content after the title and format it
	var contentBody string
	if contentStartIndex < len(lines) {
		if isNixHeader {
			contentBody = formatNixDocContent(lines[contentStartIndex:])
		} else {
			contentBody = strings.TrimSpace(strings.Join(lines[contentStartIndex:], "\n"))
		}
	}

	result, err := RenderModule(title, description, contentBody)
	if err != nil {
		// Fallback on error
		return fmt.Sprintf("# %s\n\n%s", title, contentBody)
	}
	return result
}

// escapeYAMLString ensures a string is safe for YAML frontmatter
// Quotes strings containing special characters like colons, brackets, etc.
func escapeYAMLString(s string) string {
	// Characters that need quoting in YAML
	needsQuotes := strings.ContainsAny(s, `:{}[]&*#?|-<>=!%@\'"`)
	if needsQuotes {
		// Escape any existing double quotes and wrap in quotes
		escaped := strings.ReplaceAll(s, `"`, `\"`)
		return `"` + escaped + `"`
	}
	return s
}

// formatNixDocContent formats nix doc header content, converting indented blocks to code blocks
func formatNixDocContent(lines []string) string {
	var result strings.Builder
	var inCodeBlock bool
	var codeBlockLines []string
	var lastSectionHeader string

	for i, line := range lines {
		trimmed := strings.TrimSpace(line)

		// Check for section headers like "Usage:", "Example:", "Access:"
		if strings.HasSuffix(trimmed, ":") && !strings.Contains(trimmed, " ") && len(trimmed) > 1 {
			// Flush any pending code block
			if inCodeBlock && len(codeBlockLines) > 0 {
				result.WriteString(formatCodeBlock(codeBlockLines, lastSectionHeader))
				codeBlockLines = nil
				inCodeBlock = false
			}
			lastSectionHeader = strings.TrimSuffix(trimmed, ":")
			result.WriteString("## " + lastSectionHeader + "\n\n")
			continue
		}

		// Detect if this line is indented (starts with spaces after the comment prefix was removed)
		isIndented := len(line) > 0 && (line[0] == ' ' || line[0] == '\t')

		if isIndented && trimmed != "" {
			// Start or continue code block
			if !inCodeBlock {
				inCodeBlock = true
				codeBlockLines = nil
			}
			// Remove common indentation (usually 2 spaces)
			codeLine := line
			if strings.HasPrefix(line, "  ") {
				codeLine = line[2:]
			}
			codeBlockLines = append(codeBlockLines, codeLine)
		} else {
			// Flush any pending code block
			if inCodeBlock && len(codeBlockLines) > 0 {
				result.WriteString(formatCodeBlock(codeBlockLines, lastSectionHeader))
				codeBlockLines = nil
				inCodeBlock = false
			}

			// Regular text line
			if trimmed != "" {
				result.WriteString(trimmed + "\n")
			} else if i > 0 && i < len(lines)-1 {
				// Preserve paragraph breaks
				result.WriteString("\n")
			}
		}
	}

	// Flush final code block if any
	if inCodeBlock && len(codeBlockLines) > 0 {
		result.WriteString(formatCodeBlock(codeBlockLines, lastSectionHeader))
	}

	return strings.TrimSpace(result.String())
}

// formatCodeBlock formats lines as a markdown code block
func formatCodeBlock(lines []string, sectionHeader string) string {
	// Determine language hint based on content or section header
	lang := "nix"
	content := strings.Join(lines, "\n")

	// Check for bash-like content
	if strings.Contains(content, "$") && !strings.Contains(content, "=") && !strings.Contains(content, "{") {
		lang = "bash"
	}

	return fmt.Sprintf("```%s\n%s\n```\n\n", lang, content)
}

// generateModuleDocs generates MDX docs from README files and .nix headers in module directories
func generateModuleDocs(modulesDir string, outputDir string) ([]string, error) {
	// Find README.md files
	readmeFiles, err := findReadmeFiles(modulesDir, modulesDir)
	if err != nil {
		return nil, err
	}

	// Find .nix files with doc headers
	nixDocFiles, err := findNixDocHeaders(modulesDir, modulesDir)
	if err != nil {
		return nil, err
	}

	// Combine and deduplicate (README takes precedence)
	seenModules := make(map[string]bool)
	var allDocs []DocSource

	for _, rf := range readmeFiles {
		seenModules[rf.RelativePath] = true
		allDocs = append(allDocs, rf)
	}

	for _, nf := range nixDocFiles {
		if !seenModules[nf.RelativePath] {
			allDocs = append(allDocs, nf)
		}
	}

	var generatedModules []string

	if len(allDocs) == 0 {
		fmt.Println("No documentation sources found in modules directory")
		return generatedModules, nil
	}

	// Create modules output directory
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return nil, err
	}

	fmt.Println("\n📖 Generating module documentation...")

	for _, doc := range allDocs {
		content, err := os.ReadFile(doc.Path)
		if err != nil {
			return nil, fmt.Errorf("failed to read %s: %w", doc.Path, err)
		}

		var mdxContent string
		if doc.IsNixFile {
			// Extract and convert nix doc header
			docHeader := extractNixDocHeader(doc.Path)
			mdxContent = convertNixHeaderToMdx(docHeader, doc.ModuleName)
		} else {
			mdxContent = convertReadmeToMdx(string(content), doc.ModuleName)
		}

		// Create subdirectory structure if needed
		outputPath := filepath.Join(outputDir, doc.RelativePath+".mdx")
		outputDirForFile := filepath.Dir(outputPath)
		if err := os.MkdirAll(outputDirForFile, 0755); err != nil {
			return nil, err
		}

		if err := os.WriteFile(outputPath, []byte(mdxContent), 0644); err != nil {
			return nil, fmt.Errorf("failed to write %s: %w", outputPath, err)
		}

		sourceType := "README"
		if doc.IsNixFile {
			sourceType = "nix"
		}
		fmt.Printf("  ✓ %s (%s)\n", outputPath, sourceType)
		generatedModules = append(generatedModules, doc.ModuleName)
	}

	// Generate modules index
	modulesIndexPath := filepath.Join(outputDir, "index.mdx")
	modulesIndex := generateModulesIndexMdx(allDocs)
	if err := os.WriteFile(modulesIndexPath, []byte(modulesIndex), 0644); err != nil {
		return nil, err
	}
	fmt.Printf("  ✓ %s\n", modulesIndexPath)

	return generatedModules, nil
}

// generateModulesIndexMdx generates the index page for modules
func generateModulesIndexMdx(docSources []DocSource) string {
	// Sort by module name
	sort.Slice(docSources, func(i, j int) bool {
		return docSources[i].ModuleName < docSources[j].ModuleName
	})

	var moduleLinks strings.Builder
	for _, ds := range docSources {
		title := strings.ToUpper(ds.ModuleName[:1]) + ds.ModuleName[1:]
		moduleLinks.WriteString(fmt.Sprintf("  - [%s](./%s)\n", title, ds.RelativePath))
	}

	result, err := RenderModulesIndex(moduleLinks.String())
	if err != nil {
		// Fallback on error
		return "# Module Documentation\n\n" + moduleLinks.String()
	}
	return result
}
