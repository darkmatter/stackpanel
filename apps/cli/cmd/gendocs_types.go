package cmd

import (
	"encoding/json"
	"fmt"
)

// Declaration represents a source file declaration
type Declaration struct {
	Name string  `json:"name"`
	URL  *string `json:"url"`
}

// Declarations handles both string[] and object[] formats
type Declarations []Declaration

// UnmarshalJSON handles both ["path"] and [{name,url}] formats
func (d *Declarations) UnmarshalJSON(data []byte) error {
	// Try as array of strings first (raw nixosOptionsDoc format)
	var strings []string
	if err := json.Unmarshal(data, &strings); err == nil {
		*d = make([]Declaration, len(strings))
		for i, s := range strings {
			(*d)[i] = Declaration{Name: s}
		}
		return nil
	}

	// Try as array of objects (transformed format)
	var objects []Declaration
	if err := json.Unmarshal(data, &objects); err == nil {
		*d = objects
		return nil
	}

	return fmt.Errorf("declarations must be array of strings or objects")
}

// NixOption represents a single Nix option from the JSON export
type NixOption struct {
	Declarations Declarations `json:"declarations"`
	Default      *NixValue    `json:"default"`
	Description  string       `json:"description"`
	Example      *NixValue    `json:"example"`
	Loc          []string     `json:"loc"`
	ReadOnly     bool         `json:"readOnly"`
	Type         string       `json:"type"`
}

// NixValue represents a Nix value (default or example)
type NixValue struct {
	Text string `json:"text"`
	Type string `json:"_type,omitempty"`
}

// OptionsJSON is the top-level structure of the Nix options JSON
type OptionsJSON map[string]NixOption

// DocSource represents a discovered documentation source (README.md or .nix header)
type DocSource struct {
	Path         string
	RelativePath string
	ModuleName   string
	IsNixFile    bool // true if extracted from .nix file header, false for README.md
}

// Frontmatter represents parsed YAML frontmatter from README/doc files
type Frontmatter struct {
	Title       string
	Description string
	Icon        string
	Output      string // Custom output path (relative to docs dir)
	Skip        bool   // Skip generating docs for this file
}

// ParsedDoc represents a parsed documentation source with its metadata
type ParsedDoc struct {
	Source      DocSource
	Frontmatter Frontmatter
	Content     string // Content after frontmatter
	OutputPath  string // Resolved output path
}
