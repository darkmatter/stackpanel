package docgen

import (
	"os"
	"path/filepath"
	"strings"

	tree_sitter_nix "github.com/darkmatter/stackpanel/stackpanel-go/internal/treesitter/nix"
	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// findReadmeFiles recursively finds README.md files in subdirectories
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

// findNixDocHeaders finds .nix files with documentation headers (multi-line comments at the start)
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
			// Skip directories that have a README.md (those are handled separately)
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

// isSeparatorLine checks if a line consists entirely of repeated separator characters
// (e.g., "======", "------", "******", or similar decorative lines)
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

// extractNixDocHeader extracts the documentation header from a .nix file
// using tree-sitter-nix to parse comment nodes at the start of the file.
// Returns the content if the file starts with a multi-line comment block (5+ lines).
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

	// Walk root's children, collecting consecutive comment nodes from the beginning.
	// Stop at the first non-comment child node.
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
