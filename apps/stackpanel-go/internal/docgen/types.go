package docgen

import (
	"encoding/json"
	"fmt"
)

// Declaration represents a Nix source file location where an option is defined.
// The URL field is only populated in the "transformed" JSON format produced by
// nixosOptionsDoc with declaration links enabled.
type Declaration struct {
	Name string  `json:"name"`
	URL  *string `json:"url"`
}

// Declarations handles both string[] and object[] formats from Nix option JSON.
// Raw nixosOptionsDoc emits declarations as plain path strings, while the
// transformed format uses {name, url} objects. This type transparently
// deserializes either representation.
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

// NixOption represents a single Nix option as exported by nixosOptionsDoc.
// The JSON structure mirrors nixpkgs' option documentation format.
type NixOption struct {
	Declarations Declarations `json:"declarations"`
	Default      *NixValue    `json:"default"`
	Description  string       `json:"description"`
	Example      *NixValue    `json:"example"`
	Loc          []string     `json:"loc"`       // Option path segments, e.g. ["stack", "apps", "<name>", "port"]
	ReadOnly     bool         `json:"readOnly"`
	Type         string       `json:"type"`      // Nix type string, e.g. "boolean", "list of string", "submodule"
}

// NixValue represents a Nix value (default or example) in option documentation.
// The Type field distinguishes literalExpression from literalMD in the Nix source,
// which affects how the value should be rendered (code block vs. prose).
type NixValue struct {
	Text string `json:"text"`
	Type string `json:"_type,omitempty"`
}

// OptionsJSON is the top-level structure of nixosOptionsDoc JSON output:
// a flat map from dotted option paths to their metadata.
type OptionsJSON map[string]NixOption

// DocSource represents a discovered documentation source (README.md or .nix header).
// Discovery walks the Nix modules directory looking for both formats; README.md
// files take precedence when both exist for the same module.
type DocSource struct {
	Path         string
	RelativePath string // Relative to the modules base directory, used for output path construction
	ModuleName   string
	IsNixFile    bool   // true if extracted from .nix file header comment block, false for README.md
}

// Frontmatter represents parsed YAML frontmatter from README/doc files.
// For Nix files, equivalent metadata is extracted from @docgen.* directives
// in the header comment block (see parseNixDocDirectives).
type Frontmatter struct {
	Title       string
	Description string
	Icon        string
	Output      string // Custom output path relative to the docs dir; overrides the default module-based path
	Skip        bool   // When true, this module's docs are excluded from generation
}

// ParsedDoc represents a parsed documentation source with its metadata
type ParsedDoc struct {
	Source      DocSource
	Frontmatter Frontmatter
	Content     string // Content after frontmatter
	OutputPath  string // Resolved output path
}

// CLICommand represents a Cobra command's metadata extracted for documentation.
// The tree structure mirrors Cobra's command hierarchy, allowing recursive
// generation of nested command pages.
type CLICommand struct {
	Name        string       // Command name (e.g., "services")
	FullPath    string       // Full command path (e.g., "stackpanel services start")
	Use         string       // Usage string from cobra (e.g., "start [service...]")
	Short       string       // Short description
	Long        string       // Long description
	Example     string       // Example usage
	Aliases     []string     // Command aliases
	Flags       []CLIFlag    // Command-specific flags
	GlobalFlags []CLIFlag    // Inherited/persistent flags
	Subcommands []CLICommand // Nested subcommands
	Deprecated  string       // Deprecation message if any
	Hidden      bool         // Whether command is hidden
}

// CLIFlag represents a single CLI flag extracted from a Cobra FlagSet.
type CLIFlag struct {
	Name        string // Long flag name (e.g., "verbose")
	Shorthand   string // Short flag (e.g., "v")
	Type        string // Flag type (e.g., "bool", "string", "int")
	Default     string // Default value
	Description string // Flag description
	Required    bool   // Whether flag is required
	Persistent  bool   // Whether flag is inherited by subcommands
}
