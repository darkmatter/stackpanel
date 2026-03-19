package docgen

import (
	"bytes"
	"encoding/json"
	"fmt"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// moduleFromDeclaration extracts a module/group name from a Nix declaration
// file path. It understands two source layouts:
//
//   - nix/stackpanel/modules/<name>/...  → "<name>"   (per-module file)
//   - nix/stackpanel/core/options/<name>.nix → "<name>"  (core options file)
//
// Nix store paths (e.g. /nix/store/<hash>-source/nix/stackpanel/...) are
// handled transparently because we search for the anchor segments rather than
// matching from the root.
//
// Returns "" when the path does not match either pattern so the caller can
// fall back to key-prefix grouping.
func moduleFromDeclaration(declPath string) string {
	// Normalise separators so the logic works on all platforms.
	p := filepath.ToSlash(declPath)

	// Pattern 1: .../nix/stackpanel/modules/<name>/...
	if idx := strings.Index(p, "/nix/stackpanel/modules/"); idx != -1 {
		rest := p[idx+len("/nix/stackpanel/modules/"):]
		// rest is "<name>/something.nix" – take the first path segment.
		if slash := strings.Index(rest, "/"); slash > 0 {
			name := rest[:slash]
			if name != "" && !strings.HasPrefix(name, "_") {
				return name
			}
		}
	}

	// Pattern 2: .../nix/stackpanel/core/options/<name>.nix
	if idx := strings.Index(p, "/nix/stackpanel/core/options/"); idx != -1 {
		rest := p[idx+len("/nix/stackpanel/core/options/"):]
		// rest is "<name>.nix" – strip the extension.
		name := strings.TrimSuffix(rest, ".nix")
		// Reject sub-paths (e.g. "subdir/foo.nix") and hidden files.
		if name != "" && !strings.Contains(name, "/") && !strings.HasPrefix(name, "_") {
			return name
		}
	}

	return ""
}

// moduleForOption returns the declaring module name for a single option by
// checking its declaration paths. Returns "" when none can be resolved.
func moduleForOption(opt NixOption) string {
	for _, decl := range opt.Declarations {
		if name := moduleFromDeclaration(decl.Name); name != "" {
			return name
		}
	}
	return ""
}

// jsxStr JSON-encodes s and wraps it in {…} so it is safe as a JSX
// expression prop.  e.g. jsxStr(`apps.<name>.foo`) → {"apps.<name>.foo"}
//
// json.Marshal HTML-escapes < > & by default (→ \u003c etc.), which breaks
// readability and makes the generated MDX harder to read in source. We use
// json.Encoder with SetEscapeHTML(false) to produce clean output.
func jsxStr(s string) string {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(s); err != nil {
		return `{"` + strings.ReplaceAll(s, `"`, `\"`) + `"}`
	}
	// json.Encoder.Encode appends a trailing newline — strip it before wrapping.
	return "{" + strings.TrimRight(buf.String(), "\n") + "}"
}

// groupOptions groups options by the module that declared them.
//
// Primary strategy: inspect the first declaration path for each option and
// derive the owning module via moduleFromDeclaration. This means options from
// different source files (e.g. modules/deploy/module.nix vs
// core/options/apps.nix) end up on separate pages even when their config keys
// share the same prefix (e.g. apps.<name>.deploy vs apps.<name>.framework).
//
// Fallback: when no usable declaration is found, the first segment of the
// option's config key is used as before, preserving backward-compatibility for
// options that originate outside the known directory layout.
func groupOptions(options OptionsJSON) map[string]OptionsJSON {
	groups := make(map[string]OptionsJSON)
	// Match devenv shell prefix: perSystem.<system>.devenv.shells.<name>.
	regexDevenv := regexp.MustCompile(`^perSystem\.[^.]+\.devenv\.shells\.[^.]+\.`)

	for path, opt := range options {
		// Strip devenv shell prefix if present.
		// e.g. "perSystem.aarch64-darwin.devenv.shells.default.stackpanel.apps" -> "stackpanel.apps"
		cleanPath := regexDevenv.ReplaceAllString(path, "")
		cleanPath = strings.TrimPrefix(cleanPath, "stackpanel.")

		// --- Primary: group by declaring source file ---
		var category string
		for _, decl := range opt.Declarations {
			if name := moduleFromDeclaration(decl.Name); name != "" {
				category = name
				break
			}
		}

		// --- Fallback: group by first key segment ---
		if category == "" {
			parts := strings.Split(cleanPath, ".")
			if len(parts) > 0 && parts[0] != "" {
				category = parts[0]
			} else {
				category = "core"
			}
		}

		if groups[category] == nil {
			groups[category] = make(OptionsJSON)
		}

		// Store with cleaned path for display.
		groups[category][cleanPath] = opt
	}

	return groups
}

// getCategoryIcon returns an appropriate icon for a given category name.
// Icons are from the Lucide icon set used by Fumadocs.
// See: https://lucide.dev/icons
func getCategoryIcon(category string) string {
	iconMap := map[string]string{
		"apps":           "AppWindow",
		"appsComputed":   "Calculator",
		"aws":            "Cloud",
		"caddy":          "Server",
		"ci":             "GitBranch",
		"codegen":        "Code",
		"devenv":         "Terminal",
		"devshell":       "Terminal",
		"direnv":         "FolderCog",
		"dirs":           "Folder",
		"enable":         "ToggleRight",
		"files":          "FileText",
		"gitignore":      "GitBranch",
		"globalServices": "Network",
		"ide":            "MonitorSmartphone",
		"motd":           "MessageSquare",
		"network":        "Globe",
		"ports":          "Plug",
		"root":           "Home",
		"root-marker":    "Bookmark",
		"secrets":        "Lock",
	}

	if icon, ok := iconMap[category]; ok {
		return icon
	}
	return "Settings" // Default icon
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

// generateCategoryMdx generates MDX for a single category.
//
// Each option is rendered as a <NixOption> JSX component carrying structured
// metadata (type, default, readonly, declaring module) so the React component
// can display attribution badges and read-only indicators.
//
// When the page contains options from more than one declaring module (e.g. a
// fallback-grouped page), a section heading is injected before each new
// module's block so readers can visually distinguish the contributions.
func generateCategoryMdx(category string, options OptionsJSON) string {
	title := strings.ToUpper(category[:1]) + category[1:]
	icon := getCategoryIcon(category)

	// Sort options by path for deterministic output.
	paths := make([]string, 0, len(options))
	for path := range options {
		paths = append(paths, path)
	}
	sort.Strings(paths)

	var sb strings.Builder
	header, err := RenderCategoryHeader(title, category, icon)
	if err != nil {
		header = fmt.Sprintf("# %s Options\n\n", title)
	}
	sb.WriteString(header)

	// Annotate each entry with its declaring module so we can detect
	// multi-module pages and insert section dividers.
	type optEntry struct {
		path   string
		opt    NixOption
		module string
	}
	entries := make([]optEntry, 0, len(paths))
	for _, p := range paths {
		opt := options[p]
		entries = append(entries, optEntry{p, opt, moduleForOption(opt)})
	}

	modulesSeen := make(map[string]struct{})
	for _, e := range entries {
		key := e.module
		if key == "" {
			key = "<core>"
		}
		modulesSeen[key] = struct{}{}
	}
	multiModule := len(modulesSeen) > 1
	var lastModule string

	for _, e := range entries {
		// On multi-module pages emit a section heading whenever the declaring
		// module changes.
		if multiModule && e.module != lastModule {
			if lastModule != "" {
				sb.WriteString("\n")
			}
			label := e.module
			if label == "" {
				label = category
			}
			sectionTitle := strings.ToUpper(label[:1]) + label[1:]
			sb.WriteString(fmt.Sprintf("## %s\n\n", sectionTitle))
			lastModule = e.module
		}

		sb.WriteString(renderNixOption(e.path, e.opt, e.module))
	}

	return sb.String()
}

// renderNixOption emits a ## heading (for TOC visibility) followed by an
// inline <NixOptionMeta /> self-closing component that carries the structured
// metadata (type, default, readonly, module).  Description and multi-line
// code blocks are written as plain markdown after the component so the
// Fumadocs TOC scanner can index the heading normally.
//
// All string prop values are JSON-encoded and wrapped in {…} so that
// characters like < > { } in type strings and option paths are never
// misinterpreted by the MDX parser.
func renderNixOption(path string, opt NixOption, module string) string {
	var sb strings.Builder

	// ## heading — required for Fumadocs to include this option in the TOC.
	sb.WriteString(fmt.Sprintf("## `%s`\n\n", path))

	// Inline metadata row (self-closing — no children).
	sb.WriteString("<NixOptionMeta\n")
	sb.WriteString(fmt.Sprintf("  type=%s\n", jsxStr(opt.Type)))

	// Short defaults become an inline prop; multi-line defaults are written
	// as a fenced code block below so they don't bloat the component tag.
	if opt.Default != nil {
		text := strings.TrimSpace(opt.Default.Text)
		if !strings.Contains(text, "\n") && len(text) < 60 {
			sb.WriteString(fmt.Sprintf("  defaultValue=%s\n", jsxStr(text)))
		}
	}

	// Boolean prop — no value needed in JSX.
	if opt.ReadOnly {
		sb.WriteString("  readonly\n")
	}

	// Module attribution badge.
	if module != "" {
		sb.WriteString(fmt.Sprintf("  module=%s\n", jsxStr(module)))
	}

	sb.WriteString("/>\n\n")

	// Description as plain markdown so inline elements (code spans, links)
	// render naturally.
	desc := formatDescription(opt.Description)
	if desc != "" && desc != "_No description provided._" {
		sb.WriteString(desc + "\n\n")
	}

	// Multi-line default — written as a fenced code block.
	if opt.Default != nil {
		text := strings.TrimSpace(opt.Default.Text)
		if strings.Contains(text, "\n") || len(text) >= 60 {
			sb.WriteString("**Default:**\n\n")
			sb.WriteString("```nix\n" + text + "\n```\n\n")
		}
	}

	// Example — always written as a fenced code block when present.
	if opt.Example != nil {
		text := strings.TrimSpace(opt.Example.Text)
		if text != "" {
			sb.WriteString("**Example:**\n\n")
			if strings.Contains(text, "\n") {
				sb.WriteString("```nix\n" + text + "\n```\n\n")
			} else {
				sb.WriteString("`" + text + "`\n\n")
			}
		}
	}

	sb.WriteString("---\n\n")
	return sb.String()
}

// generateIndexMdx generates the index page for the options reference
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
