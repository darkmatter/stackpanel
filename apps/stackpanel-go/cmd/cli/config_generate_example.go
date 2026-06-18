// config_generate_example.go produces an annotated config.nix.example from
// the Nix options JSON exported by nixosOptionsDoc.
//
// The generated file serves as a self-documenting template: each option gets
// inline comments from its Nix description, and values are populated from
// examples or defaults. Internal and read-only options are filtered out since
// they can't be set by users.
package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
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
	Description  string              `json:"description"`
	Type         json.RawMessage     `json:"type"`
	Default      json.RawMessage     `json:"default"`
	Example      json.RawMessage     `json:"example"`
	Declarations []map[string]string `json:"declarations"`
	ReadOnly     bool                `json:"readOnly"`
	Internal     bool                `json:"internal"`
}

func init() {
	configCmd.AddCommand(configGenerateExampleCmd)
	configGenerateExampleCmd.Flags().
		String("options-json", "", "Path to options.json from nixosOptionsDoc")
	configGenerateExampleCmd.Flags().
		String("current-config", "", "Path to current config.nix (optional, used as reference)")
	configGenerateExampleCmd.Flags().
		String("output", "", "Output path for generated config.nix.example")
	configGenerateExampleCmd.Flags().
		Bool("no-comments", false, "Skip inline documentation comments")
	configGenerateExampleCmd.Flags().
		Bool("template-config", false, "Generate active template config.nix from option defaults")
	configGenerateExampleCmd.MarkFlagRequired("options-json")
	configGenerateExampleCmd.MarkFlagRequired("output")
}

func runConfigGenerateExample(cmd *cobra.Command, args []string) error {
	optionsFile, _ := cmd.Flags().GetString("options-json")
	currentConfig, _ := cmd.Flags().GetString("current-config")
	outputFile, _ := cmd.Flags().GetString("output")
	noComments, _ := cmd.Flags().GetBool("no-comments")
	templateConfig, _ := cmd.Flags().GetBool("template-config")

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
			if templateConfig {
				info.Example = nil
			}
			filteredOptions[path] = info
		}
	}

	// Generate annotated config
	configContent := generateAnnotatedConfig(
		filteredOptions,
		currentConfig,
		!noComments,
		templateConfig,
	)

	// Write output
	if err := os.MkdirAll(filepath.Dir(outputFile), 0o755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	if err := os.WriteFile(outputFile, []byte(configContent), 0o644); err != nil {
		return fmt.Errorf("failed to write output file: %w", err)
	}

	output.Success(fmt.Sprintf("Generated: %s", outputFile))
	if !noComments {
		output.Info("Config includes inline documentation from option descriptions")
	}

	return nil
}

func generateAnnotatedConfig(
	options map[string]OptionInfo,
	currentConfigPath string,
	includeComments bool,
	templateConfig bool,
) string {
	var sb strings.Builder

	// Header
	writeLine(&sb, "# ", strings.Repeat("=", 78))
	if templateConfig {
		sb.WriteString("# config.nix\n")
		sb.WriteString("#\n")
		sb.WriteString(
			"# Stackpanel template configuration generated from option metadata.\n",
		)
		sb.WriteString(
			"# To regenerate: run 'generate-template-configs' in the Stackpanel repo.\n",
		)
	} else {
		sb.WriteString("# config.nix.example\n")
		sb.WriteString("#\n")
		sb.WriteString(
			"# Stackpanel project configuration example with inline documentation.\n",
		)

		if includeComments {
			sb.WriteString("#\n")
			sb.WriteString(
				"# This file is auto-generated from option descriptions. Copy sections you need\n",
			)
			sb.WriteString("# to your config.nix and customize as needed.\n")
			sb.WriteString("#\n")
			sb.WriteString(
				"# To regenerate: run 'generate-config-example' in your devshell\n",
			)
			sb.WriteString(
				"# For minimal version: run 'generate-config-example --no-comments'\n",
			)
		} else {
			sb.WriteString("#\n")
			sb.WriteString(
				"# Minimal configuration example without inline documentation.\n",
			)
			sb.WriteString(
				"# Run 'generate-config-example' (without --no-comments) for annotated version.\n",
			)
		}
	}

	writeLine(&sb, "# ", strings.Repeat("=", 78))
	sb.WriteString("{\n")

	tree := buildConfigTree(options, templateConfig)
	keys := sortedChildKeys(tree)

	for i, key := range keys {
		if i > 0 {
			sb.WriteString("\n")
		}

		if includeComments {
			writeLine(&sb, "  # ", strings.Repeat("-", 76))
			writeLine(&sb, "  # ", strings.ToUpper(key[:1]), key[1:])
			writeLine(&sb, "  # ", strings.Repeat("-", 76))
		}

		renderConfigNode(&sb, key, tree.Children[key], includeComments, 1)
	}

	sb.WriteString("}\n")
	return sb.String()
}

type configNode struct {
	Children map[string]*configNode
	Option   *OptionInfo
}

func newConfigNode() *configNode {
	return &configNode{Children: make(map[string]*configNode)}
}

func buildConfigTree(options map[string]OptionInfo, templateConfig bool) *configNode {
	root := newConfigNode()
	for path, info := range options {
		if shouldSkipOption(path, templateConfig) {
			continue
		}

		segments := optionPathSegments(path)
		if len(segments) == 0 || containsPlaceholderSegment(segments) {
			continue
		}

		current := root
		for _, segment := range segments {
			if current.Children[segment] == nil {
				current.Children[segment] = newConfigNode()
			}
			current = current.Children[segment]
		}
		optionCopy := info
		current.Option = &optionCopy
	}
	return root
}

func optionPathSegments(path string) []string {
	path = strings.TrimPrefix(path, "stackpanel.")
	if path == "" {
		return nil
	}
	return strings.Split(path, ".")
}

func shouldSkipOption(path string, templateConfig bool) bool {
	trimmed := strings.TrimPrefix(path, "stackpanel.")
	if strings.HasPrefix(trimmed, "_") || strings.Contains(trimmed, "._") {
		return true
	}
	if trimmed == "dirs.config" {
		return true
	}
	if templateConfig && shouldSkipTemplateOption(trimmed) {
		return true
	}
	if strings.HasSuffix(trimmed, "Modules") ||
		strings.HasSuffix(trimmed, "ModulesComputed") {
		return true
	}
	if strings.HasSuffix(trimmed, "Computed") ||
		strings.Contains(trimmed, "Computed.") {
		return true
	}
	return false
}

func shouldSkipTemplateOption(path string) bool {
	if path == "root" || path == "debug" || path == "github" {
		return true
	}
	if path == "packages" || strings.HasPrefix(path, "packages.") {
		return true
	}
	if path == "checks" || strings.HasPrefix(path, "checks.") {
		return true
	}
	if path == "outputs" || strings.HasPrefix(path, "outputs.") {
		return true
	}
	if path == "healthchecks" || strings.HasPrefix(path, "healthchecks.") {
		return true
	}
	if path == "moduleChecks" || strings.HasPrefix(path, "moduleChecks.") {
		return true
	}
	if path == "apps" || strings.HasPrefix(path, "apps.") {
		return true
	}
	if path == "project.owner" || path == "project.repo" {
		return true
	}
	return false
}

func containsPlaceholderSegment(segments []string) bool {
	for _, segment := range segments {
		if segment == "*" ||
			strings.HasPrefix(segment, "<") && strings.HasSuffix(segment, ">") {
			return true
		}
	}
	return false
}

func sortedChildKeys(node *configNode) []string {
	keys := make([]string, 0, len(node.Children))
	for key := range node.Children {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func renderConfigNode(
	sb *strings.Builder,
	key string,
	node *configNode,
	includeComments bool,
	indent int,
) {
	indentStr := strings.Repeat("  ", indent)
	if node.Option != nil && includeComments && node.Option.Description != "" {
		for _, line := range wrapText(node.Option.Description, 76) {
			writeLine(sb, indentStr, "# ", line)
		}
	}

	childKeys := sortedChildKeys(node)
	if len(childKeys) == 0 {
		if node.Option == nil {
			return
		}
		sb.WriteString(indentStr)
		sb.WriteString(key)
		sb.WriteString(" = ")
		sb.WriteString(getExampleValue(*node.Option))
		sb.WriteString(";\n")
		return
	}

	sb.WriteString(indentStr)
	sb.WriteString(key)
	sb.WriteString(" = {")
	if node.Option == nil || isEmptyAttrsetValue(getExampleValue(*node.Option)) {
		sb.WriteString("\n")
	} else {
		sb.WriteString(" # default: ")
		sb.WriteString(getExampleValue(*node.Option))
		sb.WriteString("\n")
	}

	for i, childKey := range childKeys {
		if i > 0 && includeComments {
			sb.WriteString("\n")
		}
		renderConfigNode(
			sb,
			childKey,
			node.Children[childKey],
			includeComments,
			indent+1,
		)
	}

	sb.WriteString(indentStr)
	sb.WriteString("};\n")
}

func writeLine(sb *strings.Builder, parts ...string) {
	for _, part := range parts {
		sb.WriteString(part)
	}
	sb.WriteString("\n")
}

func isEmptyAttrsetValue(value string) bool {
	return strings.TrimSpace(value) == "{ }"
}

func getExampleValue(opt OptionInfo) string {
	// Priority: example > default > type-based placeholder
	if len(opt.Example) > 0 && string(opt.Example) != "null" &&
		string(opt.Example) != "\"\"" {
		value := extractNixValue(opt.Example)
		if isUsableNixValue(value) {
			return value
		}
	}

	if len(opt.Default) > 0 && string(opt.Default) != "null" {
		value := extractNixValue(opt.Default)
		if isUsableNixValue(value) {
			return value
		}
	}

	return placeholderForType(optionTypeString(opt.Type))
}

func isUsableNixValue(value string) bool {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" || strings.Contains(trimmed, "...") {
		return false
	}
	return !strings.Contains(trimmed, "optionsDoc.") &&
		!strings.Contains(trimmed, "pkgs.")
}

func optionTypeString(raw json.RawMessage) string {
	var typeString string
	if err := json.Unmarshal(raw, &typeString); err == nil {
		return typeString
	}
	return string(raw)
}

// extractNixValue unwraps the nixosOptionsDoc JSON encoding. Nix literal
// expressions are wrapped as {"_type": "literalExpression", "text": "..."}
// — we extract the text so the example file contains valid Nix syntax,
// not JSON artefacts.
func extractNixValue(raw json.RawMessage) string {
	// Try to parse as literalExpression wrapper
	var literal struct {
		Type string `json:"_type"`
		Text string `json:"text"`
	}
	if err := json.Unmarshal(
		raw,
		&literal,
	); err == nil &&
		literal.Type == "literalExpression" {
		return literal.Text
	}

	return jsonValueToNix(raw)
}

func jsonValueToNix(raw json.RawMessage) string {
	var value any
	if err := json.Unmarshal(raw, &value); err != nil {
		return string(raw)
	}
	return anyToNix(value, 0)
}

func anyToNix(value any, indent int) string {
	switch v := value.(type) {
	case nil:
		return "null"
	case bool:
		if v {
			return "true"
		}
		return "false"
	case string:
		return strconv.Quote(v)
	case float64:
		return strconv.FormatFloat(v, 'f', -1, 64)
	case []any:
		if len(v) == 0 {
			return "[ ]"
		}
		items := make([]string, 0, len(v))
		for _, item := range v {
			items = append(items, anyToNix(item, indent+1))
		}
		return "[ " + strings.Join(items, " ") + " ]"
	case map[string]any:
		if len(v) == 0 {
			return "{ }"
		}
		keys := make([]string, 0, len(v))
		for key := range v {
			keys = append(keys, key)
		}
		sort.Strings(keys)

		indentStr := strings.Repeat("  ", indent)
		childIndent := strings.Repeat("  ", indent+1)
		var sb strings.Builder
		sb.WriteString("{\n")
		for _, key := range keys {
			sb.WriteString(childIndent)
			sb.WriteString(nixAttrName(key))
			sb.WriteString(" = ")
			sb.WriteString(anyToNix(v[key], indent+1))
			sb.WriteString(";\n")
		}
		sb.WriteString(indentStr)
		sb.WriteString("}")
		return sb.String()
	default:
		return strconv.Quote(fmt.Sprint(v))
	}
}

func nixAttrName(key string) string {
	if isSimpleNixIdentifier(key) {
		return key
	}
	return strconv.Quote(key)
}

func isSimpleNixIdentifier(key string) bool {
	if key == "" {
		return false
	}
	for i, r := range key {
		isAllowed := r == '_' || r == '-' || r == '\'' || r >= 'A' && r <= 'Z' ||
			r >= 'a' && r <= 'z' ||
			i > 0 && r >= '0' && r <= '9'
		if !isAllowed {
			return false
		}
	}
	return true
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
	if strings.Contains(typeStr, "list") || strings.Contains(typeStr, "array") ||
		strings.Contains(typeStr, "[]") {
		return "[ ]"
	}
	if strings.Contains(typeStr, "attrs") || strings.Contains(typeStr, "set") ||
		strings.Contains(typeStr, "{}") {
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
