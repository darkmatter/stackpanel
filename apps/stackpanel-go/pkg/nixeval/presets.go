package nixeval

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

// Config presets are flake installables, not ad hoc imports relying on
// builtins.getEnv or an unlocked builtins.getFlake inside --expr.
const (
	StackpanelSerializablePreset = ".#stackpanelConfig"
	StackpanelConfigPreset       = StackpanelSerializablePreset
	ActiveConfigPreset           = StackpanelSerializablePreset
)

// EvalExprResult holds the raw JSON result of a Nix expression evaluation
type EvalExprResult struct {
	Raw json.RawMessage
}

// Unmarshal decodes the result into the provided type
func (r *EvalExprResult) Unmarshal(v interface{}) error {
	return json.Unmarshal(r.Raw, v)
}

// findNixBin locates the nix binary, checking PATH first then common locations
func findNixBin() (string, error) {
	// Check PATH first
	if path, err := exec.LookPath("nix"); err == nil {
		return path, nil
	}

	// Check common locations
	commonPaths := []string{
		"/nix/var/nix/profiles/default/bin/nix",
		"/run/current-system/sw/bin/nix",
		"/etc/profiles/per-user/root/bin/nix",
	}

	for _, p := range commonPaths {
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}

	return "", fmt.Errorf("nix not found in PATH or common locations")
}

// EvalExpr evaluates an arbitrary Nix expression and returns the JSON result.
// Expressions use pure evaluation; use a flake installable for project state.
//
// Example:
//
//	result, err := EvalExpr(ctx, nixeval.StackpanelConfigPreset)
//	if err != nil { ... }
//	var config map[string]interface{}
//	result.Unmarshal(&config)
func EvalExpr(ctx context.Context, nixExpr string) (*EvalExprResult, error) {
	return EvalExprWithTimeout(ctx, nixExpr, 10*time.Second)
}

// EvalExprWithTimeout is like EvalExpr but with a custom timeout
func EvalExprWithTimeout(
	ctx context.Context,
	nixExpr string,
	timeout time.Duration,
) (*EvalExprResult, error) {
	data, err := EvalOnce(ctx, EvalOnceParams{Expression: nixExpr, Timeout: timeout})
	if err != nil {
		return nil, err
	}
	return &EvalExprResult{Raw: data}, nil
}

// GetInitFilesFromFlakeTemplate evaluates a template's initFiles from a
// stackpanel flake reference.
// This is the portable way to get scaffold templates - works from any directory.
//
// The flakeRef can be:
//   - "github:darkmatter/stackpanel" (from GitHub)
//   - "path:/local/path/to/stackpanel" (for local development)
//   - Any valid Nix flake reference
//
// Example:
//
//	files, err := GetInitFilesFromFlakeTemplate(ctx, "github:darkmatter/stackpanel", "default")
//	// files[".stack/config.nix"] = "..."
func GetInitFilesFromFlakeTemplate(
	ctx context.Context,
	flakeRef string,
	template string,
) (map[string]string, error) {
	flakeAttr, err := InitFilesFlakeAttr(flakeRef, template)
	if err != nil {
		return nil, err
	}
	result, err := EvalFlakeAttrWithTimeout(ctx, flakeAttr, 2*time.Minute)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate %s: %w", flakeAttr, err)
	}

	var files map[string]string
	if err := result.Unmarshal(&files); err != nil {
		return nil, fmt.Errorf("failed to parse initFiles: %w", err)
	}

	return files, nil
}

// AddonChoice is one option of a select/multiselect addon question.
type AddonChoice struct {
	Value  string         `json:"value"`
	Label  string         `json:"label"`
	Config map[string]any `json:"config,omitempty"`
}

// AddonQuestion is the prompt presented for an addon during `stack setup`.
// Type is one of "bool", "select", or "multiselect". Default is a bool for
// "bool", a choice value (string) for "select", and a list of choice values for
// "multiselect".
type AddonQuestion struct {
	Type        string        `json:"type"`
	Label       string        `json:"label"`
	Description string        `json:"description,omitempty"`
	Default     any           `json:"default,omitempty"`
	Order       int           `json:"order,omitempty"`
	Choices     []AddonChoice `json:"choices,omitempty"`
}

// AddonSpec is a single adoption offer: metadata, a question, a revision and a
// config mutation. It comes from `lib.initAddons` (flake-level, for a fresh
// repo) or from `stackpanel.addons` in the evaluated project config (flake-level
// plus module-contributed offers).
//   - Config is merged into .stack/config.nix when the addon is accepted.
//   - Revision is author-declared; the ledger re-offers a declined addon only
//     when it is bumped.
//   - Module names the contributing module, if any.
//
// There is deliberately no files payload: anything worth shipping is a module.
type AddonSpec struct {
	ID       string         `json:"id"`
	Revision int            `json:"revision,omitempty"`
	Module   string         `json:"module,omitempty"`
	Question AddonQuestion  `json:"question"`
	Config   map[string]any `json:"config,omitempty"`
}

// InitAddonsFlakeAttr returns the flake attribute that exposes the addon
// manifest for a stackpanel flake reference.
func InitAddonsFlakeAttr(flakeRef string) string {
	return flakeRef + "#lib.initAddons"
}

// GetInitAddonsFromFlake evaluates `lib.initAddons` and returns the addons
// sorted by (Order, ID) for a stable prompt sequence. Returns an empty slice
// when the flake exposes no addons.
func GetInitAddonsFromFlake(
	ctx context.Context,
	flakeRef string,
) ([]AddonSpec, error) {
	attr := InitAddonsFlakeAttr(flakeRef)
	result, err := EvalFlakeAttrWithTimeout(ctx, attr, 2*time.Minute)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate %s: %w", attr, err)
	}

	var raw map[string]AddonSpec
	if err := result.Unmarshal(&raw); err != nil {
		return nil, fmt.Errorf("failed to parse initAddons: %w", err)
	}

	addons := make([]AddonSpec, 0, len(raw))
	for id, spec := range raw {
		if spec.ID == "" {
			spec.ID = id
		}
		if spec.Revision == 0 {
			spec.Revision = 1
		}
		addons = append(addons, spec)
	}
	sort.Slice(addons, func(i, j int) bool {
		if addons[i].Question.Order != addons[j].Question.Order {
			return addons[i].Question.Order < addons[j].Question.Order
		}
		return addons[i].ID < addons[j].ID
	})
	return addons, nil
}

func InitFilesFlakeAttr(flakeRef string, template string) (string, error) {
	if template == "" {
		template = "default"
	}
	if err := validateInitTemplateName(template); err != nil {
		return "", err
	}
	return flakeRef + "#lib.initTemplates." + template, nil
}

func validateInitTemplateName(template string) error {
	for _, r := range template {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' ||
			r == '-' ||
			r == '_' {
			continue
		}
		return fmt.Errorf("invalid template name %q", template)
	}
	return nil
}

// EvalFlakeAttrWithTimeout evaluates a flake attribute with a custom timeout.
func EvalFlakeAttrWithTimeout(
	ctx context.Context,
	flakeAttr string,
	timeout time.Duration,
) (*EvalExprResult, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	// Do not apply a consumer's local overrides to an unrelated remote flake.
	if strings.HasPrefix(flakeAttr, ".#") {
		return EvalExprWithTimeout(ctx, flakeAttr, timeout)
	}
	data, err := runEval(
		ctx,
		"",
		[]string{"eval", "--json", "--no-write-lock-file", flakeAttr},
	)
	if err != nil {
		return nil, err
	}
	return &EvalExprResult{Raw: data}, nil
}

// InstalledPackage represents a package installed in the stackpanel config
type InstalledPackage struct {
	Name     string `json:"name"`
	Version  string `json:"version"`
	AttrPath string `json:"attrPath"`
	Source   string `json:"source,omitempty"` // "devshell" or "user"
}

// GetInstalledPackagesOptions configures how GetInstalledPackages retrieves packages
type GetInstalledPackagesOptions struct {
	// ProjectRoot is the root directory of the project (for file lookups and nix eval)
	ProjectRoot string
	// ConfigJSONPath is an explicit path to the config JSON file (highest priority)
	ConfigJSONPath string
}

// GetInstalledPackages returns the list of installed packages from the devshell configuration.
// It tries multiple fast paths before falling back to slow nix eval:
//  1. Explicit configJSONPath (if provided in options)
//  2. STACKPANEL_CONFIG_JSON env var (pre-computed at shell entry)
//  3. State file at .stack/state/stackpanel.json
//  4. Generated config at .stack/gen/config.json
//  5. Nix eval against the flake (slow, last resort)
//
// If projectRoot is empty, it will attempt to find it from STACKPANEL_ROOT env var
// or by searching up from the current directory.
func GetInstalledPackages(
	ctx context.Context,
	opts GetInstalledPackagesOptions,
) ([]InstalledPackage, error) {
	projectRoot := opts.ProjectRoot

	// Resolve project root first (needed for file-based lookups)
	if projectRoot == "" {
		projectRoot = findProjectRoot()
	}
	if projectRoot != "" {
		links, err := userconfig.LoadLinkedModules(projectRoot)
		if err != nil {
			return nil, err
		}
		if len(links) != 0 {
			return evalInstalledPackages(ctx, projectRoot)
		}
	}

	// Fast path 1: explicit config JSON path (e.g., from executor's devshell env)
	if opts.ConfigJSONPath != "" {
		packages, err := getInstalledPackagesFromJSON(opts.ConfigJSONPath)
		if err == nil && len(packages) > 0 {
			return packages, nil
		}
	}

	// Fast path 2: try to read from STACKPANEL_CONFIG_JSON env var
	if configPath := os.Getenv(
		"STACKPANEL_CONFIG_JSON",
	); configPath != "" &&
		projectRoot == os.Getenv("STACKPANEL_ROOT") {
		packages, err := getInstalledPackagesFromJSON(configPath)
		if err == nil && len(packages) > 0 {
			return packages, nil
		}
	}

	// Fast path 3: try state file
	if projectRoot != "" {
		stateFile := projectRoot + "/.stack/state/stackpanel.json"
		packages, err := getInstalledPackagesFromJSON(stateFile)
		if err == nil && len(packages) > 0 {
			return packages, nil
		}
	}

	// Fast path 4: try generated config
	if projectRoot != "" {
		genConfig := projectRoot + "/.stack/gen/config.json"
		packages, err := getInstalledPackagesFromJSON(genConfig)
		if err == nil && len(packages) > 0 {
			return packages, nil
		}
	}

	// Slow path: evaluate from flake
	if projectRoot == "" {
		return nil, fmt.Errorf(
			"no project root found - set STACKPANEL_ROOT or pass projectRoot",
		)
	}

	return evalInstalledPackages(ctx, projectRoot)
}

func evalInstalledPackages(
	ctx context.Context,
	projectRoot string,
) ([]InstalledPackage, error) {
	data, err := EvalOnce(ctx, EvalOnceParams{
		ProjectRoot: projectRoot,
		Expression:  ProjectAttr("stackpanelPackages"),
		Timeout:     5 * time.Minute,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate installed packages: %w", err)
	}

	var packages []InstalledPackage
	if err := json.Unmarshal(data, &packages); err != nil {
		return nil, fmt.Errorf("failed to parse installed packages: %w", err)
	}

	return packages, nil
}

// getInstalledPackagesFromJSON reads packages from a JSON config file.
// The file should have a "packages" field with an array of package objects.
func getInstalledPackagesFromJSON(configPath string) ([]InstalledPackage, error) {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, err
	}

	var config struct {
		Packages []InstalledPackage `json:"packages"`
	}
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, err
	}

	return config.Packages, nil
}

// GetInstalledPackageNames returns just the package names as a set for fast lookup.
// If projectRoot is empty, it will attempt to find it automatically.
func GetInstalledPackageNames(
	ctx context.Context,
	opts GetInstalledPackagesOptions,
) (map[string]bool, error) {
	packages, err := GetInstalledPackages(ctx, opts)
	if err != nil {
		return nil, err
	}

	nameSet := make(map[string]bool, len(packages)*2)
	for _, pkg := range packages {
		if pkg.Name != "" {
			nameSet[strings.ToLower(pkg.Name)] = true
		}
		if pkg.AttrPath != "" {
			nameSet[strings.ToLower(pkg.AttrPath)] = true
		}
	}

	return nameSet, nil
}
