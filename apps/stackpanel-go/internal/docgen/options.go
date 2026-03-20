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

// generateCategoryMdx generates MDX for a single category
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
