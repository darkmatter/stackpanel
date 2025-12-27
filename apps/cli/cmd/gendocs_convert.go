package cmd

import (
	"fmt"
	"strings"
)

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
	// Default metadata
	title := strings.ToUpper(moduleName[:1]) + moduleName[1:]
	description := fmt.Sprintf("Documentation for the %s module", moduleName)
	icon := ""
	contentBody := content

	// Parse frontmatter if present (for README.md files)
	if !isNixHeader {
		fm, remaining := parseFrontmatter(content)
		if fm.Title != "" {
			title = fm.Title
		}
		if fm.Description != "" {
			description = fm.Description
		}
		if fm.Icon != "" {
			icon = fm.Icon
		}
		contentBody = remaining
	}

	lines := strings.Split(contentBody, "\n")
	contentStartIndex := 0

	// Look for title in first few lines (if not already found in frontmatter)
	// For .nix headers, the first non-empty line is often the title (without #)
	// For README.md without frontmatter, look for # heading
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
			// For README.md, look for # heading (only if title not in frontmatter)
			if strings.HasPrefix(line, "# ") && title == strings.ToUpper(moduleName[:1])+moduleName[1:] {
				extractedTitle = strings.TrimPrefix(line, "# ")
				foundTitle = true
			} else if strings.HasPrefix(line, "# ") {
				// Skip the heading if we already have title from frontmatter
				contentStartIndex = i + 1
				continue
			}
		}

		if foundTitle {
			// Clean up title
			title = strings.TrimSuffix(extractedTitle, "/")
			title = strings.TrimSpace(title)
			contentStartIndex = i + 1

			// Look for description in the next non-empty line (only if not in frontmatter)
			if description == fmt.Sprintf("Documentation for the %s module", moduleName) {
				for j := i + 1; j < len(lines) && j < i+5; j++ {
					nextLine := strings.TrimSpace(lines[j])
					if nextLine != "" && !strings.HasPrefix(nextLine, "#") && !strings.HasPrefix(nextLine, "-") {
						description = nextLine
						break
					}
				}
			}
			break
		}
	}

	// Get content after the title and format it
	var finalContent string
	if contentStartIndex < len(lines) {
		if isNixHeader {
			finalContent = formatNixDocContent(lines[contentStartIndex:])
		} else {
			finalContent = strings.TrimSpace(strings.Join(lines[contentStartIndex:], "\n"))
		}
	}

	result, err := RenderModule(title, description, icon, finalContent)
	if err != nil {
		// Fallback on error
		return fmt.Sprintf("# %s\n\n%s", title, finalContent)
	}
	return result
}

// convertDocToMdxWithFrontmatter converts content to MDX using pre-parsed frontmatter
func convertDocToMdxWithFrontmatter(fm Frontmatter, content string, moduleName string) string {
	title := fm.Title
	if title == "" {
		title = strings.ToUpper(moduleName[:1]) + moduleName[1:]
	}

	description := fm.Description
	if description == "" {
		description = fmt.Sprintf("Documentation for the %s module", moduleName)
	}

	icon := fm.Icon

	// Process content to extract title if not in frontmatter
	lines := strings.Split(content, "\n")
	contentStartIndex := 0

	for i := 0; i < len(lines) && i < 5; i++ {
		line := lines[i]
		if strings.HasPrefix(line, "# ") {
			if fm.Title == "" {
				title = strings.TrimPrefix(line, "# ")
			}
			contentStartIndex = i + 1
			break
		}
	}

	var finalContent string
	if contentStartIndex < len(lines) {
		finalContent = strings.TrimSpace(strings.Join(lines[contentStartIndex:], "\n"))
	}

	result, err := RenderModule(title, description, icon, finalContent)
	if err != nil {
		return fmt.Sprintf("# %s\n\n%s", title, finalContent)
	}
	return result
}

// concatenateDocsToMdx merges multiple docs targeting the same output path
func concatenateDocsToMdx(docs []ParsedDoc) string {
	// Use frontmatter from first doc that has it
	var title, description, icon string
	for _, doc := range docs {
		if title == "" && doc.Frontmatter.Title != "" {
			title = doc.Frontmatter.Title
		}
		if description == "" && doc.Frontmatter.Description != "" {
			description = doc.Frontmatter.Description
		}
		if icon == "" && doc.Frontmatter.Icon != "" {
			icon = doc.Frontmatter.Icon
		}
	}

	// Default title from first module name
	if title == "" {
		title = strings.ToUpper(docs[0].Source.ModuleName[:1]) + docs[0].Source.ModuleName[1:]
	}
	if description == "" {
		description = fmt.Sprintf("Documentation for %s", title)
	}

	// Concatenate content from all docs
	var contentParts []string
	for _, doc := range docs {
		content := doc.Content

		// Strip leading # heading if present (we'll use frontmatter title)
		lines := strings.Split(content, "\n")
		startIdx := 0
		for i, line := range lines {
			if strings.TrimSpace(line) == "" {
				continue
			}
			if strings.HasPrefix(line, "# ") {
				startIdx = i + 1
			}
			break
		}

		if startIdx < len(lines) {
			contentParts = append(contentParts, strings.TrimSpace(strings.Join(lines[startIdx:], "\n")))
		}
	}

	finalContent := strings.Join(contentParts, "\n\n---\n\n")

	result, err := RenderModule(title, description, icon, finalContent)
	if err != nil {
		return fmt.Sprintf("# %s\n\n%s", title, finalContent)
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
