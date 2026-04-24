package nixdata

import (
	"os"
	"path/filepath"
	"strings"
)

// Paths resolves filesystem locations for Nix data files relative to a
// project root directory. Handles the .stackpanel -> .stack rename
// transparently: probes for .stack first and falls back to .stackpanel
// so existing projects continue to work without migration.
type Paths struct {
	ProjectRoot string
}

// TreeDirName is the name of the optional "tree layout" config directory
// under the project's stackpanel folder (e.g. .stack/config/). Its presence
// is what opts a project (or a single map entity inside it) into the tree
// layout — no schema flag is required because the layout is implied by
// what's on disk.
const TreeDirName = "config"

// configDir probes the filesystem to determine which config directory name
// to use. Prefers .stack (current convention), falls back to .stackpanel
// (legacy). This probe runs on every call — it's cheap (single stat) and
// means a project can be migrated by simply renaming the directory.
func (p *Paths) configDir() string {
	stackDir := filepath.Join(p.ProjectRoot, ".stack")
	if info, err := os.Stat(stackDir); err == nil && info.IsDir() {
		return ".stack"
	}
	return ".stackpanel"
}

// NewPaths creates a Paths resolver for the given project root.
func NewPaths(projectRoot string) *Paths {
	return &Paths{ProjectRoot: projectRoot}
}

// Dir returns the absolute path to the config directory (.stack or
// .stackpanel) inside the project root.
func (p *Paths) Dir() string {
	return filepath.Join(p.ProjectRoot, p.configDir())
}

// ConfigDirName returns just the directory name (".stack" or ".stackpanel")
// without the full path. Useful for display and gitignore patterns.
func ConfigDirName(projectRoot string) string {
	return (&Paths{ProjectRoot: projectRoot}).configDir()
}

// ConfigFilePath returns the path to the consolidated config.nix file.
// This is the single source of truth for project configuration — new
// entities are always written here rather than to individual data files.
func (p *Paths) ConfigFilePath() string {
	return filepath.Join(p.Dir(), "config.nix")
}

// ConfigAppsFilePath returns the path to the optional split apps config file.
// Some projects keep app definitions in config.apps.nix and import that from
// config.nix, so readers that need raw app source should check this file too.
func (p *Paths) ConfigAppsFilePath() string {
	return filepath.Join(p.Dir(), "config.apps.nix")
}

// LegacyDataDir returns the path to the legacy data/ directory where
// individual per-entity .nix files were stored before the migration to
// consolidated config.nix. Still checked for backward compatibility.
func (p *Paths) LegacyDataDir() string {
	return filepath.Join(p.Dir(), "data")
}

// ExternalDataDir returns the path to the data/ directory for external
// (read-only) entity files like github-collaborators.nix. Note: this
// returns the same path as LegacyDataDir — external files were merged
// into data/ during the directory consolidation.
func (p *Paths) ExternalDataDir() string {
	return filepath.Join(p.Dir(), "data")
}

// EntityPath returns the filesystem path for a given entity name.
//
// Resolution order (first match wins):
//  1. Entities that prefer consolidated config → config.nix (always)
//  2. Legacy .stack/data/<entity>.nix exists on disk → that file
//  3. Otherwise → config.nix (entity is a top-level key within it)
//
// This means newly created entities go into config.nix, while old
// per-file entities keep working until explicitly migrated.
// For external entities (names starting with "external-"), use
// ExternalEntityPath instead.
func (p *Paths) EntityPath(entity string) string {
	if PrefersConsolidatedConfig(entity) {
		return p.ConfigFilePath()
	}
	legacyPath := filepath.Join(p.LegacyDataDir(), entity+".nix")
	if _, err := os.Stat(legacyPath); err == nil {
		return legacyPath
	}
	return p.ConfigFilePath()
}

// ExternalEntityPath returns the path for a read-only external entity.
// The "external-" prefix is stripped to form the filename:
//
//	"external-github-collaborators" → .stack/data/github-collaborators.nix
func (p *Paths) ExternalEntityPath(entity string) string {
	name := strings.TrimPrefix(entity, "external-")
	return filepath.Join(p.Dir(), "data", name+".nix")
}

// IsUsingConsolidatedConfig returns true if the given entity is stored in
// the consolidated config.nix rather than a legacy individual file. True
// when the entity either prefers consolidated config or has no legacy file.
func (p *Paths) IsUsingConsolidatedConfig(entity string) bool {
	if PrefersConsolidatedConfig(entity) {
		return true
	}
	legacyPath := filepath.Join(p.LegacyDataDir(), entity+".nix")
	_, err := os.Stat(legacyPath)
	return os.IsNotExist(err)
}

// EnsureDir creates the .stack (or .stackpanel) directory and any parent
// directories if they do not already exist.
func (p *Paths) EnsureDir() error {
	return os.MkdirAll(p.Dir(), 0o755)
}

// ---------------------------------------------------------------------------
// Tree layout
// ---------------------------------------------------------------------------

// TreeRoot returns the absolute path to the optional tree-layout config
// directory (.stack/config/). Always returns the path, even when the
// directory does not exist on disk — callers should pair this with
// HasTreeLayout/TreeEntityDirExists to decide whether to use it.
func (p *Paths) TreeRoot() string {
	return filepath.Join(p.Dir(), TreeDirName)
}

// HasTreeLayout returns true when the optional tree-layout directory
// (.stack/config/) exists on disk. A project can use the tree layout
// alongside a regular config.nix; the two are merged at evaluation time
// (tree wins for overlapping top-level keys).
func (p *Paths) HasTreeLayout() bool {
	info, err := os.Stat(p.TreeRoot())
	return err == nil && info.IsDir()
}

// TreeEntityDir returns the directory under .stack/config/ that holds
// per-entry files for a map entity (e.g. .stack/config/apps/). Always
// returns a path; the caller should check existence when deciding
// whether to route writes here.
func (p *Paths) TreeEntityDir(entity string) string {
	return filepath.Join(p.TreeRoot(), entity)
}

// TreeEntityDirExists reports whether the per-entity tree directory
// exists. When true, that entity is in tree layout and individual
// entries live in <treeDir>/<entity>/<encoded-key>.nix files.
func (p *Paths) TreeEntityDirExists(entity string) bool {
	info, err := os.Stat(p.TreeEntityDir(entity))
	return err == nil && info.IsDir()
}

// TreeEntityKeyFilePath returns the path to a single map-entry file
// inside the tree layout (e.g. .stack/config/apps/web.nix). The key is
// encoded so that characters illegal in filenames are escaped.
func (p *Paths) TreeEntityKeyFilePath(entity, key string) string {
	return filepath.Join(p.TreeEntityDir(entity), EncodeTreeFileKey(key)+".nix")
}

// EnsureTreeEntityDir creates <treeDir>/<entity>/ if it does not already
// exist. Used by writers that need to materialise a per-entity directory
// the first time it sees a key for that entity in tree mode.
func (p *Paths) EnsureTreeEntityDir(entity string) error {
	return os.MkdirAll(p.TreeEntityDir(entity), 0o755)
}

// EncodeTreeFileKey converts a map-entry key into a filename-safe form
// for the tree layout. Currently encodes:
//
//	"/" -> "--"   (variables keyed by paths like "/dev/postgres-url"
//	               become "--dev--postgres-url.nix")
//
// "--" is chosen over "__" because haumea reserves single-underscore
// and double-underscore filename prefixes for visibility scoping
// (single-underscore = private to parent dir, double-underscore =
// private to same dir). Encoding "/dev/database-url" with "__" would
// produce "__dev__database-url.nix", which haumea would silently hide
// from the loaded attrset.
//
// "--" is filename-safe across macOS, Linux, and Windows, doesn't
// conflict with any haumea convention, and can't appear in a Nix
// attribute name (so the decode is unambiguous).
//
// SYNC: Must stay in sync with `decodeKey` in nix/flake/load-config.nix
// and the agent's tree loader in pkg/nixdata/store.go.
func EncodeTreeFileKey(key string) string {
	return strings.ReplaceAll(key, "/", "--")
}

// DecodeTreeFileKey is the inverse of EncodeTreeFileKey: it decodes a
// filename (without the .nix suffix) back into the original Nix
// attribute key.
func DecodeTreeFileKey(name string) string {
	return strings.ReplaceAll(name, "--", "/")
}

// ---------------------------------------------------------------------------
// Consolidated config.nix constants
// ---------------------------------------------------------------------------

// ConfigNixHeader is the file header prepended to config.nix when the
// agent or CLI writes the file.
const ConfigNixHeader = `# ==============================================================================
# config.nix
#
# Stackpanel project configuration.
# Both human-editable and machine-editable (single source of truth).
#
# Machine writes will sort keys alphabetically and format with nixfmt.
# For config that needs pkgs/lib (computed values, custom packages),
# use .stack/nix/ (or .stackpanel/nix/) which has full NixOS module context.
# ==============================================================================
`

// SectionHeaders returns display names for top-level config.nix keys.
// These are rendered as comment banners (e.g. "# --- Apps ---") by
// SerializeWithSections to make the file human-scannable.
func SectionHeaders() map[string]string {
	return map[string]string{
		"apps":           "Apps",
		"aws":            "AWS",
		"binary-cache":   "Binary Cache",
		"caddy":          "Caddy",
		"cli":            "CLI",
		"containers":     "Containers",
		"debug":          "Debug",
		"deployment":     "Deployment",
		"devshell":       "Devshell",
		"enable":         "Project",
		"git-hooks":      "Git Hooks",
		"github":         "GitHub",
		"globalServices": "Global Services",
		"ide":            "IDE",
		"motd":           "MOTD",
		"name":           "Name",
		"packages":       "Packages",
		"ports":          "Ports",
		"secrets":        "Secrets",
		"sst":            "SST",
		"step-ca":        "Step CA",
		"tasks":          "Tasks",
		"theme":          "Theme",
		"users":          "Users",
		"variables":      "Variables",
	}
}

// ParseConfigPath strips a leading "stackpanel." prefix from a dotted
// config path. The UI sometimes sends fully-qualified paths; this
// normalizes them for use within config.nix where the prefix is implicit.
//
//	"stackpanel.deployment.fly.organization" → "deployment.fly.organization"
//	"deployment.fly.organization"            → "deployment.fly.organization"
func ParseConfigPath(configPath string) string {
	return strings.TrimPrefix(configPath, "stackpanel.")
}

// EscapeConfigPathSegment escapes a single path segment so literal dots
// and backslashes aren't interpreted as separators by SplitConfigPath.
// Essential for user-defined keys that contain dots (e.g. "app.port"):
//
//	EscapeConfigPathSegment("app.port") → "app\.port"
func EscapeConfigPathSegment(segment string) string {
	segment = strings.ReplaceAll(segment, "\\", "\\\\")
	segment = strings.ReplaceAll(segment, ".", "\\.")
	return segment
}

// SplitConfigPath splits a dotted config path on unescaped dots and
// unescapes each segment. The escape convention uses backslash:
//
//	"apps.my\.app.port" → ["apps", "my.app", "port"]
//
// Empty segments are silently dropped. A trailing backslash is kept
// literally (no error) to be lenient with user input.
func SplitConfigPath(path string) []string {
	if path == "" {
		return nil
	}

	parts := make([]string, 0, 8)
	var current strings.Builder
	escaped := false

	for _, r := range path {
		switch {
		case escaped:
			current.WriteRune(r)
			escaped = false
		case r == '\\':
			escaped = true
		case r == '.':
			parts = append(parts, current.String())
			current.Reset()
		default:
			current.WriteRune(r)
		}
	}

	if escaped {
		current.WriteRune('\\')
	}
	parts = append(parts, current.String())

	filtered := parts[:0]
	for _, part := range parts {
		if part == "" {
			continue
		}
		filtered = append(filtered, part)
	}
	return filtered
}
