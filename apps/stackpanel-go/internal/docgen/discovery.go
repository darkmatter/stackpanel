package docgen

import (
	"os"
	"path/filepath"
	"strings"

	tree_sitter_nix "github.com/darkmatter/stackpanel/stackpanel-go/internal/treesitter/nix"
	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// findReadmeFiles recursively finds README.md files in subdirectories of dir.
// Each directory containing a README becomes a documentation source. This is
// the first pass of the two-pass discovery strategy (README > Nix headers).
func findReadmeFiles(dir string, baseDir string) ([]DocSource, error) {
	var results []DocSource

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
			results = append(results, DocSource{
				Path:         readmePath,
				RelativePath: relativePath,
				ModuleName:   entry.Name(),
				IsNixFile:    false,
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

// findNixDocHeaders finds .nix files with documentation header comments.
// This is the second pass of discovery: directories that already have a README.md
// are skipped (README takes precedence). For directories without a README, we
// check default.nix for a header comment block. Standalone .nix files (not
// default.nix) are also checked.
func findNixDocHeaders(dir string, baseDir string) ([]DocSource, error) {
	var results []DocSource

	if _, err := os.Stat(dir); os.IsNotExist(err) {
		return results, nil
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	for _, entry := range entries {
		fullPath := filepath.Join(dir, entry.Name())

		if entry.IsDir() {
			// Skip directories that have a README.md — those are handled by findReadmeFiles
			readmePath := filepath.Join(fullPath, "README.md")
			if _, err := os.Stat(readmePath); err == nil {
				continue
			}

			// Check for default.nix with doc header in this directory
			defaultNixPath := filepath.Join(fullPath, "default.nix")
			if docHeader := extractNixDocHeader(defaultNixPath); docHeader != "" {
				relativePath, _ := filepath.Rel(baseDir, fullPath)
				results = append(results, DocSource{
					Path:         defaultNixPath,
					RelativePath: relativePath,
					ModuleName:   entry.Name(),
					IsNixFile:    true,
				})
			}

			// Recurse into subdirectories
			subResults, err := findNixDocHeaders(fullPath, baseDir)
			if err != nil {
				return nil, err
			}
			results = append(results, subResults...)
		} else if strings.HasSuffix(entry.Name(), ".nix") && entry.Name() != "default.nix" {
			// Check for standalone .nix files with doc headers
			if docHeader := extractNixDocHeader(fullPath); docHeader != "" {
				// Use filename without .nix as module name
				moduleName := strings.TrimSuffix(entry.Name(), ".nix")
				relativePath, _ := filepath.Rel(baseDir, dir)
				if relativePath == "." {
					relativePath = moduleName
				} else {
					relativePath = filepath.Join(relativePath, moduleName)
				}
				results = append(results, DocSource{
					Path:         fullPath,
					RelativePath: relativePath,
					ModuleName:   moduleName,
					IsNixFile:    true,
				})
			}
		}
	}

	return results, nil
}

// isSeparatorLine checks if a line is a decorative separator (e.g., "======",
// "------"). These are common in Nix file headers and should be stripped from
// extracted documentation content.
func isSeparatorLine(line string) bool {
	trimmed := strings.TrimSpace(line)
	if len(trimmed) < 3 {
		return false
	}
	// Check if the line is entirely composed of one repeated character
	for _, ch := range []byte{'=', '-', '*', '~', '#'} {
		if strings.Trim(trimmed, string(ch)) == "" {
			return true
		}
	}
	return false
}

// extractNixDocHeader extracts documentation from a .nix file's leading comment
// block using tree-sitter for accurate parsing. Returns the cleaned content if
// the file starts with a substantial comment block (5+ lines after stripping
// separators). The 5-line threshold filters out short copyright/license headers
// that aren't meaningful documentation.
//
// Tree-sitter is used instead of regex because Nix comments can be tricky to
// parse correctly (# prefix, nested expressions in comments, etc.).
func extractNixDocHeader(path string) string {
	source, err := os.ReadFile(path)
	if err != nil {
		return ""
	}

	parser := tree_sitter.NewParser()
	defer parser.Close()
	lang := tree_sitter.NewLanguage(tree_sitter_nix.Language())
	if err := parser.SetLanguage(lang); err != nil {
		return ""
	}

	tree := parser.Parse(source, nil)
	if tree == nil {
		return ""
	}
	defer tree.Close()

	root := tree.RootNode()

	// Collect consecutive comment nodes from the file's beginning.
	// We stop at the first non-comment node — the doc header must be at the
	// very top of the file with no intervening code.
	var docLines []string
	childCount := root.ChildCount()
	for i := uint(0); i < childCount; i++ {
		child := root.Child(i)
		if child == nil {
			break
		}
		if child.Kind() != "comment" {
			break
		}

		text := string(source[child.StartByte():child.EndByte()])
		// Strip the leading # prefix and optional single space
		text = strings.TrimPrefix(text, "#")
		text = strings.TrimPrefix(text, " ")

		// Skip separator lines (e.g., "==============")
		if isSeparatorLine(text) {
			continue
		}

		docLines = append(docLines, text)
	}

	// Require at least 5 lines to be considered a doc header
	if len(docLines) < 5 {
		return ""
	}

	return strings.TrimSpace(strings.Join(docLines, "\n"))
}
