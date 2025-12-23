package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
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

// ReadmeFile represents a discovered README.md file
type ReadmeFile struct {
	Path         string
	RelativePath string
	ModuleName   string
}

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
	outputDir := args[1]
	var modulesDir string
	if len(args) > 2 {
		modulesDir = args[2]
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

	// Ensure output directory exists
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	// Generate index
	indexPath := filepath.Join(outputDir, "index.mdx")
	if err := os.WriteFile(indexPath, []byte(generateIndexMdx(categories)), 0644); err != nil {
		return fmt.Errorf("failed to write index: %w", err)
	}
	fmt.Printf("  ✓ %s\n", indexPath)

	// Generate category pages
	for category, opts := range groups {
		categoryPath := filepath.Join(outputDir, category+".mdx")
		if err := os.WriteFile(categoryPath, []byte(generateCategoryMdx(category, opts)), 0644); err != nil {
			return fmt.Errorf("failed to write category %s: %w", category, err)
		}
		fmt.Printf("  ✓ %s (%d options)\n", categoryPath, len(opts))
	}

	fmt.Printf("\nGenerated %d reference files\n", len(categories)+1)

	// Generate module documentation from README files if modules dir provided
	if modulesDir != "" {
		parentOutputDir := filepath.Dir(outputDir)
		generatedModules, err := generateModuleDocs(modulesDir, parentOutputDir)
		if err != nil {
			return fmt.Errorf("failed to generate module docs: %w", err)
		}
		if len(generatedModules) > 0 {
			fmt.Printf("\nGenerated %d module doc(s)\n", len(generatedModules))
		}
	}

	return nil
}

// groupOptions groups options by their top-level category
func groupOptions(options OptionsJSON) map[string]OptionsJSON {
	groups := make(map[string]OptionsJSON)

	for path, opt := range options {
		// Remove 'stackpanel.' prefix and get first segment
		withoutPrefix := strings.TrimPrefix(path, "stackpanel.")
		parts := strings.Split(withoutPrefix, ".")
		category := parts[0]
		if category == "" {
			category = "core"
		}

		if groups[category] == nil {
			groups[category] = make(OptionsJSON)
		}
		groups[category][path] = opt
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
	sb.WriteString(fmt.Sprintf(`---
title: %s Options
description: Configuration options for stackpanel.%s
---

# %s Options

`, title, category, title))

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
		categoryLinks.WriteString(fmt.Sprintf("  - [%s](./%s)\n", title, cat))
	}

	return fmt.Sprintf(`---
title: Options Reference
description: Complete reference for all stackpanel configuration options
---

# Options Reference

This section documents all available configuration options for stackpanel.

## Categories

%s
## Quick Start

`+"```nix\n"+`# In your devenv.nix
{
  stackpanel = {
    enable = true;

    # Port management
    ports.projectName = "myproject";

    # Services
    globalServices.postgres.enable = true;
    globalServices.redis.enable = true;

    # Theme
    theme.enable = true;
  };
}
`+"```\n", categoryLinks.String())
}

// findReadmeFiles recursively finds README.md files in subdirectories
func findReadmeFiles(dir string, baseDir string) ([]ReadmeFile, error) {
	var results []ReadmeFile

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
			results = append(results, ReadmeFile{
				Path:         readmePath,
				RelativePath: relativePath,
				ModuleName:   entry.Name(),
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

// convertReadmeToMdx converts README.md content to MDX with frontmatter
func convertReadmeToMdx(readmeContent string, moduleName string) string {
	lines := strings.Split(readmeContent, "\n")

	// Default title and description
	title := strings.ToUpper(moduleName[:1]) + moduleName[1:]
	description := fmt.Sprintf("Documentation for the %s module", moduleName)
	contentStartIndex := 0

	// Look for h1 title in first few lines
	maxLines := 5
	if len(lines) < maxLines {
		maxLines = len(lines)
	}

	for i := 0; i < maxLines; i++ {
		line := lines[i]
		if strings.HasPrefix(line, "# ") {
			// Clean up title (remove trailing / or other artifacts)
			title = strings.TrimSuffix(strings.TrimPrefix(line, "# "), "/")
			title = strings.TrimSpace(title)
			contentStartIndex = i + 1

			// Look for description in the next non-empty line
			for j := i + 1; j < len(lines) && j < i+5; j++ {
				nextLine := strings.TrimSpace(lines[j])
				if nextLine != "" && !strings.HasPrefix(nextLine, "#") {
					description = nextLine
					break
				}
			}
			break
		}
	}

	// Get content after the title
	var content string
	if contentStartIndex < len(lines) {
		content = strings.TrimSpace(strings.Join(lines[contentStartIndex:], "\n"))
	}

	return fmt.Sprintf(`---
title: %s
description: %s
---

%s
`, title, description, content)
}

// generateModuleDocs generates MDX docs from README files in module directories
func generateModuleDocs(modulesDir string, outputDir string) ([]string, error) {
	readmeFiles, err := findReadmeFiles(modulesDir, modulesDir)
	if err != nil {
		return nil, err
	}

	var generatedModules []string

	if len(readmeFiles) == 0 {
		fmt.Println("No README.md files found in modules directory")
		return generatedModules, nil
	}

	// Create modules output directory
	modulesOutputDir := filepath.Join(outputDir, "modules")
	if err := os.MkdirAll(modulesOutputDir, 0755); err != nil {
		return nil, err
	}

	fmt.Println("\n📖 Generating module documentation...")

	for _, rf := range readmeFiles {
		readmeContent, err := os.ReadFile(rf.Path)
		if err != nil {
			return nil, fmt.Errorf("failed to read %s: %w", rf.Path, err)
		}

		mdxContent := convertReadmeToMdx(string(readmeContent), rf.ModuleName)

		// Create subdirectory structure if needed
		outputPath := filepath.Join(modulesOutputDir, rf.RelativePath+".mdx")
		outputDirForFile := filepath.Dir(outputPath)
		if err := os.MkdirAll(outputDirForFile, 0755); err != nil {
			return nil, err
		}

		if err := os.WriteFile(outputPath, []byte(mdxContent), 0644); err != nil {
			return nil, fmt.Errorf("failed to write %s: %w", outputPath, err)
		}
		fmt.Printf("  ✓ %s\n", outputPath)
		generatedModules = append(generatedModules, rf.ModuleName)
	}

	// Generate modules index
	modulesIndexPath := filepath.Join(modulesOutputDir, "index.mdx")
	modulesIndex := generateModulesIndexMdx(readmeFiles)
	if err := os.WriteFile(modulesIndexPath, []byte(modulesIndex), 0644); err != nil {
		return nil, err
	}
	fmt.Printf("  ✓ %s\n", modulesIndexPath)

	return generatedModules, nil
}

// generateModulesIndexMdx generates the index page for modules
func generateModulesIndexMdx(readmeFiles []ReadmeFile) string {
	// Sort by module name
	sort.Slice(readmeFiles, func(i, j int) bool {
		return readmeFiles[i].ModuleName < readmeFiles[j].ModuleName
	})

	var moduleLinks strings.Builder
	for _, rf := range readmeFiles {
		title := strings.ToUpper(rf.ModuleName[:1]) + rf.ModuleName[1:]
		moduleLinks.WriteString(fmt.Sprintf("  - [%s](./%s)\n", title, rf.RelativePath))
	}

	return fmt.Sprintf(`---
title: Module Documentation
description: In-depth documentation for stackpanel modules
---

# Module Documentation

This section contains detailed documentation for individual stackpanel modules.

## Modules

%s`, moduleLinks.String())
}
