package cmd

import "strings"

// parseFrontmatter parses YAML frontmatter from documentation content.
// Returns the parsed Frontmatter and the remaining content (without frontmatter).
func parseFrontmatter(content string) (Frontmatter, string) {
	fm := Frontmatter{}
	lines := strings.Split(content, "\n")

	// Check if file starts with frontmatter delimiter
	if len(lines) == 0 || strings.TrimSpace(lines[0]) != "---" {
		return fm, content
	}

	// Find closing delimiter
	endIdx := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimSpace(lines[i]) == "---" {
			endIdx = i
			break
		}
	}

	if endIdx == -1 {
		return fm, content
	}

	// Parse frontmatter fields (simple YAML parsing)
	for i := 1; i < endIdx; i++ {
		line := lines[i]
		if colonIdx := strings.Index(line, ":"); colonIdx > 0 {
			key := strings.TrimSpace(line[:colonIdx])
			value := strings.TrimSpace(line[colonIdx+1:])
			// Remove quotes if present
			value = strings.Trim(value, `"'`)

			switch strings.ToLower(key) {
			case "title":
				fm.Title = value
			case "description":
				fm.Description = value
			case "icon":
				fm.Icon = value
			case "output":
				fm.Output = value
			case "skip":
				fm.Skip = value == "true" || value == "yes" || value == "1" || value == ""
			}
		}
	}

	// Return remaining content (after frontmatter)
	remaining := strings.Join(lines[endIdx+1:], "\n")
	return fm, strings.TrimSpace(remaining)
}

// parseNixDocDirectives extracts @docgen.* directives from nix comment content.
// Supported directives:
//   - @docgen.skip - Skip generating docs for this file
//   - @docgen.icon IconName - Set the icon for this doc
//   - @docgen.output /path/to/file.mdx - Set custom output path
//
// Returns the Frontmatter with extracted values and content with directives removed.
func parseNixDocDirectives(content string) (Frontmatter, string) {
	fm := Frontmatter{}
	lines := strings.Split(content, "\n")
	var cleanedLines []string

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)

		if trimmed == "@docgen.skip" {
			fm.Skip = true
			continue
		}

		if strings.HasPrefix(trimmed, "@docgen.icon ") {
			fm.Icon = strings.TrimSpace(strings.TrimPrefix(trimmed, "@docgen.icon "))
			continue
		}

		if strings.HasPrefix(trimmed, "@docgen.output ") {
			fm.Output = strings.TrimSpace(strings.TrimPrefix(trimmed, "@docgen.output "))
			continue
		}

		cleanedLines = append(cleanedLines, line)
	}

	return fm, strings.TrimSpace(strings.Join(cleanedLines, "\n"))
}
