package docgen

import (
	"os"
	"path/filepath"
	"strings"
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

// extractNixDocHeader extracts the documentation header from a .nix file
// Returns the content if the file starts with a multi-line comment block (5+ lines)
func extractNixDocHeader(path string) string {
	content, err := os.ReadFile(path)
	if err != nil {
		return ""
	}

	lines := strings.Split(string(content), "\n")
	if len(lines) < 5 {
		return ""
	}

	// Check if file starts with # comment lines
	var docLines []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") {
			// Remove the # prefix and leading space
			docLine := strings.TrimPrefix(trimmed, "#")
			docLine = strings.TrimPrefix(docLine, " ")
			docLines = append(docLines, docLine)
		} else if trimmed == "" && len(docLines) > 0 {
			// Allow empty lines within the doc block
			docLines = append(docLines, "")
		} else {
			// Hit non-comment, non-empty line - end of doc block
			break
		}
	}

	// Require at least 5 lines to be considered a doc header
	if len(docLines) < 5 {
		return ""
	}

	return strings.TrimSpace(strings.Join(docLines, "\n"))
}
