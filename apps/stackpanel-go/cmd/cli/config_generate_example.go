package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/spf13/cobra"
)

var configGenerateExampleCmd = &cobra.Command{
	Use:   "generate-example",
	Short: "Generate annotated config.nix.example with option descriptions",
	Long: `Generate an annotated config.nix.example file with inline documentation from option descriptions.

This command reads the stackpanel options JSON (from nixosOptionsDoc) and generates
a comprehensive example configuration file with inline comments explaining each option.

Examples:
  stackpanel config generate-example --options-json options.json --output config.nix.example
  stackpanel config generate-example --options-json options.json --output config.nix.example --no-comments
  stackpanel config generate-example --options-json options.json --current-config config.nix --output example.nix`,
	RunE: runConfigGenerateExample,
}

type OptionInfo struct {
	Description  string                 `json:"description"`
	Type         json.RawMessage        `json:"type"`
	Default      json.RawMessage        `json:"default"`
	Example      json.RawMessage        `json:"example"`
	Declarations []map[string]string    `json:"declarations"`
	ReadOnly     bool                   `json:"readOnly"`
	Internal     bool                   `json:"internal"`
}

func init() {
	configCmd.AddCommand(configGenerateExampleCmd)
	configGenerateExampleCmd.Flags().String("options-json", "", "Path to options.json from nixosOptionsDoc")
	configGenerateExampleCmd.Flags().String("current-config", "", "Path to current config.nix (optional, used as reference)")
	configGenerateExampleCmd.Flags().String("output", "", "Output path for generated config.nix.example")
	configGenerateExampleCmd.Flags().Bool("no-comments", false, "Skip inline documentation comments")
	configGenerateExampleCmd.MarkFlagRequired("options-json")
	configGenerateExampleCmd.MarkFlagRequired("output")
}

func runConfigGenerateExample(cmd *cobra.Command, args []string) error {
	optionsFile, _ := cmd.Flags().GetString("options-json")
	currentConfig, _ := cmd.Flags().GetString("current-config")
	outputFile, _ := cmd.Flags().GetString("output")
	noComments, _ := cmd.Flags().GetBool("no-comments")

	// Read options JSON
	data, err := os.ReadFile(optionsFile)
	if err != nil {
		return fmt.Errorf("failed to read options JSON: %w", err)
	}

	var options map[string]OptionInfo
	if err := json.Unmarshal(data, &options); err != nil {
		return fmt.Errorf("failed to parse options JSON: %w", err)
	}

	// Filter out internal and read-only options
	filteredOptions := make(map[string]OptionInfo)
	for path, info := range options {
		if !info.Internal && !info.ReadOnly {
			filteredOptions[path] = info
		}
	}

	// Generate annotated config
	configContent := generateAnnotatedConfig(filteredOptions, currentConfig, !noComments)

	// Write output
	if err := os.MkdirAll(filepath.Dir(outputFile), 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	if err := os.WriteFile(outputFile, []byte(configContent), 0644); err != nil {
		return fmt.Errorf("failed to write output file: %w", err)
	}

	output.Success(fmt.Sprintf("Generated: %s", outputFile))
	if !noComments {
		output.Info("Config includes inline documentation from option descriptions")
	}

	return nil
}

func generateAnnotatedConfig(options map[string]OptionInfo, currentConfigPath string, includeComments bool) string {
	var sb strings.Builder

	// Header
	sb.WriteString("# " + strings.Repeat("=", 78) + "\n")
	sb.WriteString("# config.nix.example\n")
	sb.WriteString("#\n")
	sb.WriteString("# Stackpanel project configuration example with inline documentation.\n")

	if includeComments {
		sb.WriteString("#\n")
		sb.WriteString("# This file is auto-generated from option descriptions. Copy sections you need\n")
		sb.WriteString("# to your config.nix and customize as needed.\n")
		sb.WriteString("#\n")
		sb.WriteString("# To regenerate: run 'generate-config-example' in your devshell\n")
		sb.WriteString("# For minimal version: run 'generate-config-example --no-comments'\n")
	} else {
		sb.WriteString("#\n")
		sb.WriteString("# Minimal configuration example without inline documentation.\n")
		sb.WriteString("# Run 'generate-config-example' (without --no-comments) for annotated version.\n")
	}

	sb.WriteString("# " + strings.Repeat("=", 78) + "\n")
	sb.WriteString("{\n")

	// Group options by top-level key
	grouped := groupOptions(options)
	keys := make([]string, 0, len(grouped))
	for k := range grouped {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	// Render each top-level section
	for i, key := range keys {
		if i > 0 {
			sb.WriteString("\n")
		}

		if includeComments {
			sb.WriteString("  # " + strings.Repeat("-", 76) + "\n")
			sb.WriteString("  # " + strings.ToUpper(key[:1]) + key[1:] + "\n")
			sb.WriteString("  # " + strings.Repeat("-", 76) + "\n")
		}

		renderOptionGroup(&sb, key, grouped[key], includeComments, 1)
	}

	sb.WriteString("}\n")
	return sb.String()
}

func groupOptions(options map[string]OptionInfo) map[string]map[string]OptionInfo {
	grouped := make(map[string]map[string]OptionInfo)

	for path, info := range options {
		// Remove "stackpanel." prefix if present
		path = strings.TrimPrefix(path, "stackpanel.")

		parts := strings.Split(path, ".")
		if len(parts) == 0 {
			continue
		}

		topLevel := parts[0]
		if grouped[topLevel] == nil {
			grouped[topLevel] = make(map[string]OptionInfo)
		}

		remainingPath := strings.Join(parts[1:], ".")
		if remainingPath != "" {
			grouped[topLevel][remainingPath] = info
		} else {
			// This is the root option for this top-level key
			grouped[topLevel][""] = info
		}
	}

	return grouped
}

func renderOptionGroup(sb *strings.Builder, key string, opts map[string]OptionInfo, includeComments bool, indent int) {
	indentStr := strings.Repeat("  ", indent)

	// Check if this is a simple leaf option
	if rootOpt, hasRoot := opts[""]; hasRoot && len(opts) == 1 {
		if includeComments && rootOpt.Description != "" {
			for _, line := range wrapText(rootOpt.Description, 76) {
				sb.WriteString(indentStr + "# " + line + "\n")
			}
		}

		sb.WriteString(indentStr + key + " = ")
		sb.WriteString(getExampleValue(rootOpt))
		sb.WriteString(";\n")
		return
	}

	// Complex nested structure
	sb.WriteString(indentStr + key + " = {\n")

	// Sort sub-keys for consistent output
	subKeys := make([]string, 0, len(opts))
	for k := range opts {
		if k != "" { // Skip root option in nested context
			subKeys = append(subKeys, k)
		}
	}
	sort.Strings(subKeys)

	for j, subKey := range subKeys {
		if j > 0 && includeComments {
			sb.WriteString("\n")
		}

		opt := opts[subKey]

		if includeComments && opt.Description != "" {
			for _, line := range wrapText(opt.Description, 74) {
				sb.WriteString(indentStr + "  # " + line + "\n")
			}
		}

		// Determine if this should be expanded or rendered as simple
		if strings.Contains(subKey, ".") {
			// Multi-level path - expand it
			parts := strings.Split(subKey, ".")
			renderNestedOption(sb, parts, opt, includeComments, indent+1)
		} else {
			// Simple option
			sb.WriteString(indentStr + "  " + subKey + " = ")
			sb.WriteString(getExampleValue(opt))
			sb.WriteString(";\n")
		}
	}

	sb.WriteString(indentStr + "};\n")
}

func renderNestedOption(sb *strings.Builder, parts []string, opt OptionInfo, includeComments bool, indent int) {
	indentStr := strings.Repeat("  ", indent)

	if len(parts) == 1 {
		sb.WriteString(indentStr + parts[0] + " = ")
		sb.WriteString(getExampleValue(opt))
		sb.WriteString(";\n")
		return
	}

	// Render nested structure
	sb.WriteString(indentStr + parts[0] + " = {\n")
	renderNestedOption(sb, parts[1:], opt, includeComments, indent+1)
	sb.WriteString(indentStr + "};\n")
}

func getExampleValue(opt OptionInfo) string {
	// Priority: example > default > type-based placeholder
	if len(opt.Example) > 0 && string(opt.Example) != "null" && string(opt.Example) != "\"\"" {
		return extractNixValue(opt.Example)
	}

	if len(opt.Default) > 0 && string(opt.Default) != "null" {
		return extractNixValue(opt.Default)
	}

	return placeholderForType(string(opt.Type))
}

// extractNixValue extracts the actual Nix value from the JSON representation.
// nixosOptionsDoc wraps literal expressions in {"_type": "literalExpression", "text": "..."}
func extractNixValue(raw json.RawMessage) string {
	// Try to parse as literalExpression wrapper
	var literal struct {
		Type string `json:"_type"`
		Text string `json:"text"`
	}
	if err := json.Unmarshal(raw, &literal); err == nil && literal.Type == "literalExpression" {
		return literal.Text
	}

	// Otherwise return as-is
	return string(raw)
}

func placeholderForType(typeStr string) string {
	typeStr = strings.ToLower(typeStr)

	// Match common type patterns
	if strings.Contains(typeStr, "bool") {
		return "false"
	}
	if strings.Contains(typeStr, "int") || strings.Contains(typeStr, "number") {
		return "0"
	}
	if strings.Contains(typeStr, "string") || strings.Contains(typeStr, "str") {
		return `""`
	}
	if strings.Contains(typeStr, "list") || strings.Contains(typeStr, "array") || strings.Contains(typeStr, "[]") {
		return "[ ]"
	}
	if strings.Contains(typeStr, "attrs") || strings.Contains(typeStr, "set") || strings.Contains(typeStr, "{}") {
		return "{ }"
	}
	if strings.Contains(typeStr, "path") {
		return `"./path"`
	}
	if strings.Contains(typeStr, "package") {
		return "pkgs.package-name"
	}

	return "null"
}

func wrapText(text string, width int) []string {
	// Clean up text
	text = strings.TrimSpace(text)
	text = strings.ReplaceAll(text, "\n", " ")

	words := strings.Fields(text)
	var lines []string
	var current string

	for _, word := range words {
		if current == "" {
			current = word
		} else if len(current)+1+len(word) <= width {
			current += " " + word
		} else {
			lines = append(lines, current)
			current = word
		}
	}

	if current != "" {
		lines = append(lines, current)
	}

	return lines
}
