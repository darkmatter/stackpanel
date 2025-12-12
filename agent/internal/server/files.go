package server

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// readFile reads a file from the project, with path safety checks
func (s *Server) readFile(path string) (*FileContent, error) {
	// Resolve to absolute path
	absPath := path
	if !filepath.IsAbs(path) {
		absPath = filepath.Join(s.config.ProjectRoot, path)
	}

	// Security: ensure path is within project root
	absPath = filepath.Clean(absPath)
	if !strings.HasPrefix(absPath, s.config.ProjectRoot) {
		return nil, fmt.Errorf("path outside project root: %s", path)
	}

	content, err := os.ReadFile(absPath)
	if err != nil {
		if os.IsNotExist(err) {
			return &FileContent{
				Path:   path,
				Exists: false,
			}, nil
		}
		return nil, err
	}

	return &FileContent{
		Path:    path,
		Content: string(content),
		Exists:  true,
	}, nil
}

// writeFile writes content to a file within the project
func (s *Server) writeFile(path, content string) error {
	// Resolve to absolute path
	absPath := path
	if !filepath.IsAbs(path) {
		absPath = filepath.Join(s.config.ProjectRoot, path)
	}

	// Security: ensure path is within project root
	absPath = filepath.Clean(absPath)
	if !strings.HasPrefix(absPath, s.config.ProjectRoot) {
		return fmt.Errorf("path outside project root: %s", path)
	}

	// Create parent directories if needed
	dir := filepath.Dir(absPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create directory: %w", err)
	}

	return os.WriteFile(absPath, []byte(content), 0644)
}
