package docgen

import (
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

// groupOptions groups options by the module that declared them.
//
// Primary strategy: inspect the first declaration file path for each option and
// derive the owning module via moduleFromDeclaration. This groups by source file
// location rather than config key prefix, so options defined in different modules
// (e.g. modules/deploy/ vs core/options/apps.nix) land on separate pages even
// when their config keys share a prefix like "apps.<name>".
//
// Fallback: when no declaration maps to a known module directory, the first
// segment of the option's dotted config key is used as the category name.
func groupOptions(options OptionsJSON) map[string]OptionsJSON {
	groups := make(map[string]OptionsJSON)
	// devenv wraps options under a system-specific prefix that we strip to get
	// the canonical option path. Example:
	//   "perSystem.aarch64-darwin.devenv.shells.default.stackpanel.apps" -> "apps"
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

// getCategoryIcon maps category names to Lucide icon names for Fumadocs.
// Returns "Settings" as the default for unrecognized categories.
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
		"secrets":        "Lock",
	}

	if icon, ok := iconMap[category]; ok {
		return icon
	}
	return "Settings" // Default icon
}

// formatValueInline formats a Nix value for display in a markdown table cell.
// Short values get inline code formatting; long/multi-line values show a
// placeholder since tables can't contain code blocks.
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

// formatValueBlock formats a Nix value as a fenced code block for display
// below the options table. Returns empty string for short values that already
// fit inline.
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

// generateCategoryMdx generates a complete MDX page for one option category.
// Each option gets an H2 section with a property table, optional code blocks
// for long defaults/examples, and a horizontal rule separator.
func generateCategoryMdx(category string, options OptionsJSON) string {
	title := strings.ToUpper(category[:1]) + category[1:]
	icon := getCategoryIcon(category)

	// Sort options by path
	paths := make([]string, 0, len(options))
	for path := range options {
		paths = append(paths, path)
	}
	sort.Strings(paths)

	var sb strings.Builder
	header, err := RenderCategoryHeader(title, category, icon)
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

// generateIndexMdx generates the options reference landing page with links
// to all category pages.
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
