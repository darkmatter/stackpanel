package docgen

import (
	"bytes"
	"fmt"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/text"
)

// convertReadmeToMdx converts README.md content to MDX with frontmatter
func convertReadmeToMdx(readmeContent string, moduleName string) string {
	return convertDocToMdx(readmeContent, moduleName, false)
}

// convertNixHeaderToMdx converts a .nix doc header to MDX with frontmatter
func convertNixHeaderToMdx(docHeader string, moduleName string) string {
	return convertDocToMdx(docHeader, moduleName, true)
}

// mdParse parses markdown source into a goldmark AST.
func mdParse(source []byte) ast.Node {
	md := goldmark.New()
	reader := text.NewReader(source)
	return md.Parser().Parse(reader)
}

// mdNodeText extracts the plain-text content of an AST node (concatenating
// all inline text / code-span children). This replaces manual tag stripping.
func mdNodeText(n ast.Node, source []byte) string {
	var buf bytes.Buffer
	for c := n.FirstChild(); c != nil; c = c.NextSibling() {
		switch v := c.(type) {
		case *ast.Text:
			buf.Write(v.Segment.Value(source))
			if v.SoftLineBreak() {
				buf.WriteByte(' ')
			}
		case *ast.CodeSpan:
			// Recurse into the code span's text segments.
			for sc := v.FirstChild(); sc != nil; sc = sc.NextSibling() {
				if t, ok := sc.(*ast.Text); ok {
					buf.Write(t.Segment.Value(source))
				}
			}
		default:
			// Recurse for other inline nodes (emphasis, strong, links, etc.)
			buf.WriteString(mdNodeText(c, source))
		}
	}
	return buf.String()
}

// mdExtractTitle walks the AST looking for the first H1 heading and returns
// its text content plus the byte offset where the heading ends so the caller
// can slice the remaining content.  Returns ("", -1) when no H1 is found.
func mdExtractTitle(doc ast.Node, source []byte) (title string, endByte int) {
	for n := doc.FirstChild(); n != nil; n = n.NextSibling() {
		h, ok := n.(*ast.Heading)
		if !ok || h.Level != 1 {
			continue
		}
		title = strings.TrimSpace(mdNodeText(h, source))
		// The heading node's lines tell us where it ends in the source.
		if h.Lines().Len() > 0 {
			last := h.Lines().At(h.Lines().Len() - 1)
			endByte = int(last.Stop)
		}
		return title, endByte
	}
	return "", -1
}

// mdExtractFirstParagraph walks the AST looking for the first Paragraph node
// that appears after startByte in the source. Returns its text content.
func mdExtractFirstParagraph(doc ast.Node, source []byte, startByte int) string {
	for n := doc.FirstChild(); n != nil; n = n.NextSibling() {
		p, ok := n.(*ast.Paragraph)
		if !ok {
			continue
		}
		// Only consider paragraphs that start after the heading.
		if p.Lines().Len() > 0 && int(p.Lines().At(0).Start) < startByte {
			continue
		}
		text := strings.TrimSpace(mdNodeText(p, source))
		if text != "" && !strings.HasPrefix(text, "#") {
			return text
		}
	}
	return ""
}

// mdStripLeadingH1 removes the first H1 heading (and any preceding blank
// lines) from markdown source, returning the remainder. If no H1 is found
// the source is returned unchanged.
func mdStripLeadingH1(source []byte) []byte {
	doc := mdParse(source)
	for n := doc.FirstChild(); n != nil; n = n.NextSibling() {
		h, ok := n.(*ast.Heading)
		if !ok || h.Level != 1 {
			continue
		}
		if h.Lines().Len() > 0 {
			last := h.Lines().At(h.Lines().Len() - 1)
			rest := bytes.TrimLeft(source[last.Stop:], "\r\n")
			return rest
		}
		break
	}
	return source
}

// convertDocToMdx converts documentation content to MDX with frontmatter.
//
// For README.md files the title is taken from YAML frontmatter if present,
// otherwise from the first H1 heading. For Nix doc headers the first non-
// empty, non-separator line is the title.
//
// The description is taken from frontmatter if present, otherwise from the
// first paragraph after the title heading.
func convertDocToMdx(content string, moduleName string, isNixHeader bool) string {
	defaultTitle := strings.ToUpper(moduleName[:1]) + moduleName[1:]
	title := defaultTitle
	description := fmt.Sprintf("Documentation for the %s module", moduleName)
	icon := ""
	contentBody := content

	// ── README path: try frontmatter first, then goldmark AST ──────────
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

		src := []byte(contentBody)
		doc := mdParse(src)

		// Extract H1 as title when frontmatter didn't provide one.
		h1Text, h1End := mdExtractTitle(doc, src)
		if h1Text != "" {
			if title == defaultTitle {
				title = strings.TrimSuffix(h1Text, "/")
			}
			// Strip the H1 from the body.
			contentBody = strings.TrimSpace(string(src[h1End:]))
		}

		// Extract first paragraph as description when frontmatter didn't
		// provide one.
		if description == fmt.Sprintf("Documentation for the %s module", moduleName) {
			startAt := 0
			if h1End > 0 {
				startAt = h1End
			}
			if para := mdExtractFirstParagraph(doc, src, startAt); para != "" {
				description = para
			}
		}
	} else {
		// ── Nix header path ────────────────────────────────────────────
		lines := strings.Split(contentBody, "\n")
		contentStartIndex := 0

		for i, line := range lines {
			if i >= 5 {
				break
			}
			trimmed := strings.TrimSpace(line)
			if trimmed == "" {
				continue
			}
			if strings.HasPrefix(trimmed, "-") || strings.Trim(trimmed, "=-*~#") == "" {
				continue
			}

			extracted := trimmed
			// Strip "filename.nix - " prefix
			if idx := strings.Index(extracted, ".nix - "); idx != -1 {
				extracted = extracted[idx+len(".nix - "):]
			}
			title = strings.TrimSpace(strings.TrimSuffix(extracted, "/"))
			contentStartIndex = i + 1

			// First paragraph after title → description
			for j := i + 1; j < len(lines) && j < i+5; j++ {
				next := strings.TrimSpace(lines[j])
				if next != "" && !strings.HasPrefix(next, "#") && !strings.HasPrefix(next, "-") {
					description = next
					break
				}
			}
			break
		}

		if contentStartIndex < len(lines) {
			contentBody = formatNixDocContent(lines[contentStartIndex:])
		} else {
			contentBody = ""
		}
	}

	result, err := RenderModule(title, description, icon, contentBody)
	if err != nil {
		return fmt.Sprintf("# %s\n\n%s", title, contentBody)
	}
	return result
}

// convertDocToMdxWithFrontmatter converts content to MDX using pre-parsed frontmatter.
// The first H1 heading is extracted with goldmark to avoid duplicating it in
// the body (the title lives in the MDX frontmatter instead).
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

	src := []byte(content)
	doc := mdParse(src)

	h1Text, h1End := mdExtractTitle(doc, src)
	if h1Text != "" {
		if fm.Title == "" {
			title = h1Text
		}
		content = strings.TrimSpace(string(src[h1End:]))
	}

	result, err := RenderModule(title, description, icon, content)
	if err != nil {
		return fmt.Sprintf("# %s\n\n%s", title, content)
	}
	return result
}

// concatenateDocsToMdx merges multiple docs targeting the same output path.
// Leading H1 headings are stripped with goldmark so the combined page can use
// a single title from frontmatter.
func concatenateDocsToMdx(docs []ParsedDoc) string {
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

	if title == "" {
		title = strings.ToUpper(docs[0].Source.ModuleName[:1]) + docs[0].Source.ModuleName[1:]
	}
	if description == "" {
		description = fmt.Sprintf("Documentation for %s", title)
	}

	var contentParts []string
	for _, doc := range docs {
		stripped := mdStripLeadingH1([]byte(doc.Content))
		trimmed := strings.TrimSpace(string(stripped))
		if trimmed != "" {
			contentParts = append(contentParts, trimmed)
		}
	}

	finalContent := strings.Join(contentParts, "\n\n---\n\n")

	result, err := RenderModule(title, description, icon, finalContent)
	if err != nil {
		return fmt.Sprintf("# %s\n\n%s", title, finalContent)
	}
	return result
}

// escapeYAMLString ensures a string is safe for YAML frontmatter.
// Quotes strings containing special characters like colons, brackets, etc.
func escapeYAMLString(s string) string {
	needsQuotes := strings.ContainsAny(s, `:{}[]&*#?|-<>=!%@\'"`)
	if needsQuotes {
		escaped := strings.ReplaceAll(s, `"`, `\"`)
		return `"` + escaped + `"`
	}
	return s
}

// formatDescription cleans an option description that may contain docbook/XML
// remnants.  Instead of manual < > scanning, the text is parsed as markdown
// and the plain text content is extracted via the goldmark AST, which
// transparently drops any inline HTML tags.
func formatDescription(desc string) string {
	if desc == "" {
		return "_No description provided._"
	}

	src := []byte(desc)
	doc := mdParse(src)

	var parts []string
	for n := doc.FirstChild(); n != nil; n = n.NextSibling() {
		switch n.Kind() {
		case ast.KindParagraph:
			parts = append(parts, strings.TrimSpace(mdNodeText(n, src)))
		case ast.KindFencedCodeBlock, ast.KindCodeBlock:
			// Preserve code blocks verbatim from the source.
			var cb bytes.Buffer
			lines := n.Lines()
			for i := 0; i < lines.Len(); i++ {
				seg := lines.At(i)
				cb.Write(seg.Value(src))
			}
			parts = append(parts, strings.TrimRight(cb.String(), "\n"))
		default:
			// For other block nodes (lists, blockquotes, etc.) fall back
			// to the raw source segment so we don't lose structure.
			if n.Lines().Len() > 0 {
				first := n.Lines().At(0)
				last := n.Lines().At(n.Lines().Len() - 1)
				raw := string(src[first.Start:last.Stop])
				parts = append(parts, strings.TrimSpace(raw))
			}
		}
	}

	result := strings.Join(parts, "\n\n")
	if strings.TrimSpace(result) == "" {
		return "_No description provided._"
	}
	return strings.TrimSpace(result)
}

// formatNixDocContent formats nix doc header content, converting indented
// blocks to fenced code blocks. This handles the structured comment format
// used in Nix module headers (e.g. "Usage:" sections with indented examples).
func formatNixDocContent(lines []string) string {
	var result strings.Builder
	var inCodeBlock bool
	var codeBlockLines []string
	var lastSectionHeader string

	for i, line := range lines {
		trimmed := strings.TrimSpace(line)

		// Check for section headers like "Usage:", "Example:", "Access:"
		if strings.HasSuffix(trimmed, ":") && !strings.Contains(trimmed, " ") && len(trimmed) > 1 {
			if inCodeBlock && len(codeBlockLines) > 0 {
				result.WriteString(formatCodeBlock(codeBlockLines, lastSectionHeader))
				codeBlockLines = nil
				inCodeBlock = false
			}
			lastSectionHeader = strings.TrimSuffix(trimmed, ":")
			result.WriteString("## " + lastSectionHeader + "\n\n")
			continue
		}

		isIndented := len(line) > 0 && (line[0] == ' ' || line[0] == '\t')

		if isIndented && trimmed != "" {
			if !inCodeBlock {
				inCodeBlock = true
				codeBlockLines = nil
			}
			codeLine := line
			if strings.HasPrefix(line, "  ") {
				codeLine = line[2:]
			}
			codeBlockLines = append(codeBlockLines, codeLine)
		} else {
			if inCodeBlock && len(codeBlockLines) > 0 {
				result.WriteString(formatCodeBlock(codeBlockLines, lastSectionHeader))
				codeBlockLines = nil
				inCodeBlock = false
			}

			if trimmed != "" {
				result.WriteString(trimmed + "\n")
			} else if i > 0 && i < len(lines)-1 {
				result.WriteString("\n")
			}
		}
	}

	if inCodeBlock && len(codeBlockLines) > 0 {
		result.WriteString(formatCodeBlock(codeBlockLines, lastSectionHeader))
	}

	return strings.TrimSpace(result.String())
}

// formatCodeBlock formats lines as a fenced markdown code block.
func formatCodeBlock(lines []string, sectionHeader string) string {
	lang := "nix"
	content := strings.Join(lines, "\n")

	if strings.Contains(content, "$") && !strings.Contains(content, "=") && !strings.Contains(content, "{") {
		lang = "bash"
	}

	return fmt.Sprintf("```%s\n%s\n```\n\n", lang, content)
}
