// config_generate_example.go
//
// Normal usage of this command is extremely simple:
//
//	stack config generate [--no-comments] [--output PATH]
//
// It writes one of the two checked-in starter configs that live in:
//
//	nix/flake/templates/default/.stack/config.nix
//	nix/flake/templates/minimal/.stack/config.nix
//
// Those files were produced by evaluating the option schema (once) and shaping
// it into a useful starter. The shaping step is what "generate-template-configs"
// drives. After that, the files are just files — checked into the tree so that
// `nix flake init -t` and `stackpanel init` work and the drift test passes.
//
// This command (in its default mode) does not evaluate Nix, does not read
// options.json, and does not inject comments at runtime. It embeds the already-
// generated text at build time and copies the right variant out.
//
// The large amount of code you see later in this file (buildConfigTree,
// generateAnnotatedConfig, jsonValueToNix, etc.) is ONLY used by the
// --template-config code path, which is the *upstream generator* that
// maintainers run (via generate-template-configs) to refresh the checked-in
// templates when the option schema changes.
//
// If you only care about "what does a user running `stack config generate` get?":
// look at runConfigGenerate (the non-templateConfig branch) and
// readEmbeddedTemplate. Everything else is regeneration machinery.
package cmd

import (
	"embed"
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

//go:embed template_configs/default.nix template_configs/minimal.nix
var templateConfigsFS embed.FS

var configGenerateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate a starter config.nix.example from the baked template",
	Long: `Generate a config.nix.example for discovering options and documentation.

This writes a starter configuration drawn from the checked-in templates that
ship with stackpanel. The content matches what you get from 'nix flake init -t'
or 'stack init'.

By default it writes to .stack/config.nix.example (with the .example suffix so
it does not overwrite your active config.nix). Use --no-comments for a compact
version without the inline option docs.

This command does not re-evaluate the option schema at runtime — it serves the
pre-generated starter that was baked when the stackpanel release was built.

Examples:
  stack config generate
  stack config generate --no-comments
  stack config generate --output my-starter.nix

Stackpanel maintainers: to refresh the starters from the current option schema,
run 'generate-template-configs' inside the stackpanel repository devshell.`,
	RunE: runConfigGenerate,
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
	configCmd.AddCommand(configGenerateCmd)
	configGenerateCmd.Flags().
		String("options-json", "", "Path to options.json from nixosOptionsDoc (required with --template-config; internal)")
	_ = configGenerateCmd.Flags().MarkHidden("options-json")
	configGenerateCmd.Flags().
		String("current-config", "", "Path to current config.nix (optional, used as reference)")
	configGenerateCmd.Flags().
		String("output", "", "Output path (default: .stack/config.nix.example for normal use)")
	configGenerateCmd.Flags().
		Bool("no-comments", false, "Emit the minimal template (no inline documentation)")
	configGenerateCmd.Flags().
		Bool("template-config", false, "Regenerate the canonical template files from options.json (maintainers only)")
	_ = configGenerateCmd.Flags().MarkHidden("template-config")
	// Note: we do not MarkFlagRequired("output") here.
	// For normal user-facing generate we default to .stack/config.nix.example.
	// The --template-config path (used by generate-template-configs) always
	// supplies an explicit --output.
}

func runConfigGenerate(cmd *cobra.Command, args []string) error {
	optionsFile, _ := cmd.Flags().GetString("options-json")
	currentConfig, _ := cmd.Flags().GetString("current-config")
	outputFile, _ := cmd.Flags().GetString("output")
	noComments, _ := cmd.Flags().GetBool("no-comments")
	templateConfig, _ := cmd.Flags().GetBool("template-config")

	// Template mode (--template-config) is only for regenerating the checked-in
	// starters inside the stackpanel repo. It requires the raw options.json.
	if templateConfig && optionsFile == "" {
		return fmt.Errorf(
			"--options-json is required when --template-config is set",
		)
	}

	// For normal user-facing use, default to writing a .example next to the
	// project's config so we never clobber an active config.nix.
	if outputFile == "" && !templateConfig {
		outputFile = ".stack/config.nix.example"
	}
	if outputFile == "" {
		return fmt.Errorf("--output is required when --template-config is set")
	}

	var configContent string
	if templateConfig {
		// --template-config: full regeneration path used by generate-template-configs.
		// Writes the canonical files under nix/flake/templates (and embed copies).
		rendered, err := renderTemplateConfig(optionsFile, currentConfig, !noComments)
		if err != nil {
			return err
		}
		configContent = rendered
	} else {
		// User path: emit the pre-baked starter. This is what existing projects
		// run via `stack config generate` to discover options / see docs.
		embedded, err := readEmbeddedTemplate(noComments)
		if err != nil {
			return err
		}
		configContent = embedded
	}

	// Write output
	if err := os.MkdirAll(filepath.Dir(outputFile), 0o755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	if err := os.WriteFile(outputFile, []byte(configContent), 0o644); err != nil {
		return fmt.Errorf("failed to write output file: %w", err)
	}

	output.Success(fmt.Sprintf("Generated: %s", outputFile))

	// Only regeneration claims to have pulled descriptions at this moment.
	if templateConfig && !noComments {
		output.Info("Config includes inline documentation from option descriptions")
	}

	return nil
}

// readEmbeddedTemplate returns the checked-in template config that ships with
// the flake templates, baked into the binary at build time. `minimal` selects
// the minimal template; otherwise the annotated default template is used.
func readEmbeddedTemplate(minimal bool) (string, error) {
	name := "template_configs/default.nix"
	if minimal {
		name = "template_configs/minimal.nix"
	}
	data, err := templateConfigsFS.ReadFile(name)
	if err != nil {
		return "", fmt.Errorf("failed to read embedded template config %s: %w", name, err)
	}
	return string(data), nil
}

// =============================================================================
// REGENERATION PATH (only used with --template-config)
//
// Everything from here down exists so that "generate-template-configs" can take
// a fresh options.json (produced by mkOptionsDoc + nixosOptionsDoc) and turn it
// into a shaped, filtered, nicely-commented config.nix that gets checked into
// the template tree.
//
// Normal `stack config generate` (and the internal devshell wrapper
// generate-config-example) never call any of this. They just read the embed.
//
// If you are modifying how starters look, you probably want to change the
// skipping/filtering rules, the tree builder, or the Nix pretty-printing below,
// then run `generate-template-configs` and commit the result.
// =============================================================================

// renderTemplateConfig runs the upstream generator that rebuilds the checked-in
// template config.nix from the options JSON. Only used by the
// generate-template-configs devshell script inside the Stackpanel repo.
func renderTemplateConfig(
	optionsFile string,
	currentConfig string,
	includeComments bool,
) (string, error) {
	data, err := os.ReadFile(optionsFile)
	if err != nil {
		return "", fmt.Errorf("failed to read options JSON: %w", err)
	}

	var options map[string]OptionInfo
	if err := json.Unmarshal(data, &options); err != nil {
		return "", fmt.Errorf("failed to parse options JSON: %w", err)
	}

	// Filter out internal and read-only options; template mode never uses
	// example values (they're stripped so only defaults drive the output).
	filteredOptions := make(map[string]OptionInfo)
	for path, info := range options {
		if !info.Internal && !info.ReadOnly {
			info.Example = nil
			filteredOptions[path] = info
		}
	}

	return generateAnnotatedConfig(filteredOptions, currentConfig, includeComments, true), nil
}

// generateAnnotatedConfig (and everything it calls) implements the non-trivial
// transformation from a flat nixosOptionsDoc map into a nested, filtered,
// commented Nix expression. This is the "evaluate options and write a good
// starter" logic — but it is only invoked for regeneration.
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
		// This header goes into the canonical starter files under
		// nix/flake/templates. Those files are:
		//   - copied into new projects by nix flake init / stack init
		//   - served to existing projects by `stack config generate`
		//
		// Keep the tone appropriate for end users. The "how to refresh the
		// starters themselves" instructions live in the stackpanel repo's
		// internal generator script, not in user-visible output.
		sb.WriteString("# config.nix\n")
		sb.WriteString("#\n")
		sb.WriteString(
			"# Stackpanel project configuration (starter).\n",
		)
		sb.WriteString(
			"# Generated from the current option schema.\n",
		)
		sb.WriteString("#\n")
		sb.WriteString(
			"# To see the latest options and examples (after upgrading stackpanel):\n",
		)
		sb.WriteString(
			"#   stack config generate --output .stack/config.nix.example\n",
		)
		sb.WriteString(
			"#\n",
		)
		sb.WriteString(
			"# Review the generated .example and copy/merge sections you need.\n",
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
				"# This file is produced from the baked starter templates.\n",
			)
			sb.WriteString("# Copy sections you need to your config.nix and customize.\n")
			sb.WriteString("#\n")
			sb.WriteString(
				"# To refresh: stack config generate [--no-comments]\n",
			)
		} else {
			sb.WriteString("#\n")
			sb.WriteString(
				"# Minimal starter without inline documentation.\n",
			)
			sb.WriteString(
				"# Run 'stack config generate' for the annotated version.\n",
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
