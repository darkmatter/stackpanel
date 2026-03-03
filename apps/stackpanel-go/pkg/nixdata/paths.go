package nixdata

import (
	"os"
	"path/filepath"
	"strings"
)

// Paths resolves filesystem locations for Nix data files relative to a
// project root directory. Prefers .stack with .stackpanel fallback for
// backward compatibility.
type Paths struct {
	ProjectRoot string
}

// configDir returns the config directory name: ".stack" if it exists, else ".stackpanel".
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

// Dir returns the config directory (.stack or .stackpanel) inside the project root.
func (p *Paths) Dir() string {
	return filepath.Join(p.ProjectRoot, p.configDir())
}

// ConfigDirName returns the config directory name (".stack" or ".stackpanel") for the given project root.
func ConfigDirName(projectRoot string) string {
	return (&Paths{ProjectRoot: projectRoot}).configDir()
}

// ConfigFilePath returns the path to the single consolidated config.nix
// file. This is the preferred single source of truth for all Stackpanel
// project configuration.
func (p *Paths) ConfigFilePath() string {
	return filepath.Join(p.Dir(), "config.nix")
}

// LegacyDataDir returns the path to the legacy data/ directory where
// individual per-entity .nix files were stored before the migration to
// consolidated config.nix.
func (p *Paths) LegacyDataDir() string {
	return filepath.Join(p.Dir(), "data")
}

// ExternalDataDir returns the path to the data/ directory where
// external/collaborator data is stored (e.g. github-collaborators.nix).
// Merged from legacy external/ into data/.
func (p *Paths) ExternalDataDir() string {
	return filepath.Join(p.Dir(), "data")
}

// EntityPath returns the filesystem path for a given entity name.
//
// If a legacy per-entity file exists at .stackpanel/data/<entity>.nix it
// is returned for backwards compatibility. Otherwise the consolidated
// config.nix path is returned (the entity is expected to be a top-level
// key within that file).
//
// For external entities (names starting with "external-"), use
// ExternalEntityPath instead.
func (p *Paths) EntityPath(entity string) string {
	legacyPath := filepath.Join(p.LegacyDataDir(), entity+".nix")
	if _, err := os.Stat(legacyPath); err == nil {
		return legacyPath
	}
	return p.ConfigFilePath()
}

// ExternalEntityPath returns the path for a read-only external entity.
// The "external-" prefix is stripped. Prefers data/ then legacy external/:
//
//	"external-github-collaborators" → .stack/data/github-collaborators.nix (or .stackpanel/external/...)
func (p *Paths) ExternalEntityPath(entity string) string {
	name := strings.TrimPrefix(entity, "external-")
	dataPath := filepath.Join(p.Dir(), "data", name+".nix")
	if _, err := os.Stat(dataPath); err == nil {
		return dataPath
	}
	return filepath.Join(p.Dir(), "external", name+".nix")
}

// IsUsingConsolidatedConfig returns true if the given entity is stored in
// the consolidated config.nix rather than a legacy individual file.
func (p *Paths) IsUsingConsolidatedConfig(entity string) bool {
	legacyPath := filepath.Join(p.LegacyDataDir(), entity+".nix")
	_, err := os.Stat(legacyPath)
	return os.IsNotExist(err)
}

// EnsureDir creates the .stackpanel directory (and parents) if it does not
// already exist.
func (p *Paths) EnsureDir() error {
	return os.MkdirAll(p.Dir(), 0o755)
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
# use .stackpanel/modules/ which has full NixOS module context.
# ==============================================================================
`

// SectionHeaders returns display names for top-level config.nix keys. These
// are used by SerializeWithSections (in pkg/nix) to insert readable comment
// banners when writing the consolidated config file.
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
// config path so it can be used to navigate within config.nix.
//
//	"stackpanel.deployment.fly.organization" → "deployment.fly.organization"
//	"deployment.fly.organization"            → "deployment.fly.organization"
func ParseConfigPath(configPath string) string {
	return strings.TrimPrefix(configPath, "stackpanel.")
}
