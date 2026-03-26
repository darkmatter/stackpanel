package nixeval

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// Preset Nix expressions for common evaluations.
// These are self-contained snippets passed to `nix eval --impure --expr`.
// They rely on STACKPANEL_ROOT being set (via builtins.getEnv) to locate
// project files. The .stack/ path is tried first with .stackpanel/ as legacy fallback.
const (
	// UsersPreset evaluates the users configuration from .stack/data or .stackpanel/data
	// Returns the users attrset in stackpanel.users format
	UsersPreset = `
let
  root = builtins.getEnv "STACKPANEL_ROOT";
  usersStack = root + "/.stack/data/users.nix";
  usersLegacy = root + "/.stackpanel/data/users.nix";
  usersPath = if builtins.pathExists usersStack then usersStack else usersLegacy;
in
  if builtins.pathExists usersPath
  then import usersPath
  else {}
`

	// GitHubCollaboratorsPreset evaluates raw collaborators data
	GitHubCollaboratorsPreset = `
let
  root = builtins.getEnv "STACKPANEL_ROOT";
  collabsStack = root + "/.stack/data/github-collaborators.nix";
  collabsLegacy = root + "/.stackpanel/data/github-collaborators.nix";
  collabsPath = if builtins.pathExists collabsStack then collabsStack else collabsLegacy;
in
  if builtins.pathExists collabsPath
  then import collabsPath
  else { collaborators = {}; }
`

	// StackpanelConfigPreset evaluates the full stackpanel config from .stack or .stackpanel.
	// Note: config.nix may be a plain attrset or a function taking { pkgs, lib, ... }.
	// We pass nulls for pkgs/lib since this lightweight eval can't provide them --
	// configs that depend on pkgs won't work here (use the flake-based presets instead).
	StackpanelConfigPreset = `
let
  root = builtins.getEnv "STACKPANEL_ROOT";
  configStack = root + "/.stack/config.nix";
  configLegacy = root + "/.stackpanel/config.nix";
  configPath = if builtins.pathExists configStack then configStack else configLegacy;
  rawConfig =
    if builtins.pathExists configPath
    then import configPath
    else {};
  evaluatedConfig =
    if builtins.isFunction rawConfig
    then rawConfig {
      pkgs = null;
      lib = null;
      inputs = {};
      self = null;
      config = evaluatedConfig;
    }
    else rawConfig;
in
  evaluatedConfig.stackpanel or evaluatedConfig or {}
`

	// StackpanelSerializablePreset evaluates the full config from the flake's top-level
	// output. Unlike the preset above, this goes through the full module system and
	// includes computed values (ports, URLs, commands). Requires a valid flake.nix.
	StackpanelSerializablePreset = `.#stackpanelConfig`

	// ActiveConfigPreset reads the config attached to the default devshell's passthru.
	// This is the canonical path for user projects that consume stackpanel as a flake input.
	ActiveConfigPreset = `.#devShells.${builtins.currentSystem}.default.passthru.moduleConfig.stackpanel`

	// InitFilesPreset evaluates the db module to get boilerplate files for project scaffolding
	// Returns a map of relative paths to file contents
	InitFilesPreset = `
let
  root = builtins.getEnv "STACKPANEL_ROOT";
  dbModule = import (root + "/nix/stackpanel/db") { };
in
  dbModule.initFiles
`

	// DbSchemasPreset evaluates all schemas from the db module for codegen
	// Returns a map of entity names to JSON Schema
	DbSchemasPreset = `
let
  root = builtins.getEnv "STACKPANEL_ROOT";
  dbModule = import (root + "/nix/stackpanel/db") { };
in
  dbModule.forCodegen
`
)

// InstalledPackagesExpr builds a Nix expression that extracts the package list
// from a flake. It bakes the absolute projectRoot into the expression as a
// git+file:// URI -- this avoids copying the entire worktree into the Nix store
// (which would include node_modules, .git, etc.) and makes evaluation much faster.
func InstalledPackagesExpr(projectRoot string) string {
	return fmt.Sprintf(`
let
  system = builtins.currentSystem;
  flake = builtins.getFlake "git+file://%s";

  # Priority 1: devshell passthru (for user projects consuming stackpanel)
  devShell = flake.devShells.${system}.default or null;
  passthruPackages = if devShell != null then devShell.passthru.stackpanelPackages or null else null;

  # Priority 2: flake output (for stackpanel repo itself)
  flakePackages = flake.stackpanelPackages or null;
in
  if passthruPackages != null then passthruPackages
  else if flakePackages != null then flakePackages
  else []
`, projectRoot)
}

// EvalExprResult holds the raw JSON bytes from a nix eval invocation.
// Use [EvalExprResult.Unmarshal] to decode into a typed Go struct.
type EvalExprResult struct {
	Raw json.RawMessage
}

// Unmarshal decodes the raw JSON into the provided value.
func (r *EvalExprResult) Unmarshal(v interface{}) error {
	return json.Unmarshal(r.Raw, v)
}

// findNixBin locates the nix binary. PATH is checked first; if that fails
// (e.g. running from a non-interactive context like launchd or systemd),
// common Nix installation paths are tried as a fallback.
func findNixBin() (string, error) {
	if path, err := exec.LookPath("nix"); err == nil {
		return path, nil
	}

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
// The expression is evaluated with --impure so it can read environment variables.
//
// Example:
//
//	result, err := EvalExpr(ctx, nixeval.UsersPreset)
//	if err != nil { ... }
//	var users map[string]User
//	result.Unmarshal(&users)
func EvalExpr(ctx context.Context, nixExpr string) (*EvalExprResult, error) {
	return EvalExprWithTimeout(ctx, nixExpr, 10*time.Second)
}

// EvalExprWithTimeout is like EvalExpr but with a custom timeout
func EvalExprWithTimeout(ctx context.Context, nixExpr string, timeout time.Duration) (*EvalExprResult, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	nixBin, err := findNixBin()
	if err != nil {
		return nil, err
	}

	// Use nix eval --expr for inline expressions
	cmd := exec.CommandContext(ctx, nixBin, "eval", "--impure", "--json", "--expr", nixExpr)

	// Set STACKPANEL_ROOT if not already set
	if os.Getenv("STACKPANEL_ROOT") == "" {
		if root := findProjectRoot(); root != "" {
			cmd.Env = append(os.Environ(), "STACKPANEL_ROOT="+root)
		}
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("nix eval failed: %w\nstderr: %s", err, stderr.String())
	}

	return &EvalExprResult{Raw: stdout.Bytes()}, nil
}

// User represents a stackpanel user from the users config
type User struct {
	Name                       string   `json:"name,omitempty"`
	GitHub                     string   `json:"github,omitempty"`
	PublicKeys                 []string `json:"public-keys,omitempty"`
	SecretsAllowedEnvironments []string `json:"secrets-allowed-environments,omitempty"`
}

// GetUsers evaluates and returns the users configuration
func GetUsers(ctx context.Context) (map[string]User, error) {
	result, err := EvalExpr(ctx, UsersPreset)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate users: %w", err)
	}

	var users map[string]User
	if err := result.Unmarshal(&users); err != nil {
		return nil, fmt.Errorf("failed to parse users: %w", err)
	}

	return users, nil
}

// GitHubCollaborator represents a collaborator from github-collaborators.nix
type GitHubCollaborator struct {
	Login      string   `json:"login"`
	ID         int      `json:"id"`
	Role       string   `json:"role"`
	IsAdmin    bool     `json:"isAdmin"`
	PublicKeys []string `json:"publicKeys"`
}

// GitHubCollaboratorsData represents the full github-collaborators.nix structure
type GitHubCollaboratorsData struct {
	Meta struct {
		Source      string `json:"source"`
		GeneratedAt string `json:"generatedAt"`
	} `json:"_meta"`
	Collaborators map[string]GitHubCollaborator `json:"collaborators"`
}

// GetGitHubCollaborators evaluates and returns the GitHub collaborators
func GetGitHubCollaborators(ctx context.Context) (*GitHubCollaboratorsData, error) {
	result, err := EvalExpr(ctx, GitHubCollaboratorsPreset)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate collaborators: %w", err)
	}

	var data GitHubCollaboratorsData
	if err := result.Unmarshal(&data); err != nil {
		return nil, fmt.Errorf("failed to parse collaborators: %w", err)
	}

	return &data, nil
}

// GetStackpanelConfig evaluates the stackpanel section from .stack/config.nix.
// This is a lightweight eval that passes null for pkgs/lib, so configs using
// pkgs (e.g. for package references) will fail. Use the flake-based path for full eval.
func GetStackpanelConfig(ctx context.Context) (map[string]interface{}, error) {
	result, err := EvalExpr(ctx, StackpanelConfigPreset)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate config: %w", err)
	}

	var config map[string]interface{}
	if err := result.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	return config, nil
}

// GetInitFiles evaluates the db module and returns the map of paths to content
// for scaffolding a new project.
// DEPRECATED: Use GetInitFilesFromFlake instead for portable scaffolding.
func GetInitFiles(ctx context.Context) (map[string]string, error) {
	result, err := EvalExpr(ctx, InitFilesPreset)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate initFiles: %w", err)
	}

	var files map[string]string
	if err := result.Unmarshal(&files); err != nil {
		return nil, fmt.Errorf("failed to parse initFiles: %w", err)
	}

	return files, nil
}

// GetInitFilesFromFlake evaluates initFiles from a stackpanel flake reference.
// This is the portable way to get scaffold templates - works from any directory.
//
// The flakeRef can be:
//   - "github:darkmatter/stackpanel" (from GitHub)
//   - "path:/local/path/to/stackpanel" (for local development)
//   - Any valid Nix flake reference
//
// Example:
//
//	files, err := GetInitFilesFromFlake(ctx, "github:darkmatter/stackpanel")
//	// files[".stack/config.nix"] = "..."
func GetInitFilesFromFlake(ctx context.Context, flakeRef string) (map[string]string, error) {
	// Evaluate <flakeRef>#lib.initFiles
	flakeAttr := flakeRef + "#lib.initFiles"
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

// EvalFlakeAttr evaluates a flake attribute and returns the JSON result.
// The flakeAttr should be in the form "flakeRef#attrPath" (e.g., "github:owner/repo#lib.foo").
func EvalFlakeAttr(ctx context.Context, flakeAttr string) (*EvalExprResult, error) {
	return EvalFlakeAttrWithTimeout(ctx, flakeAttr, 30*time.Second)
}

// EvalFlakeAttrWithTimeout evaluates a flake attribute with a custom timeout.
func EvalFlakeAttrWithTimeout(ctx context.Context, flakeAttr string, timeout time.Duration) (*EvalExprResult, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	nixBin, err := findNixBin()
	if err != nil {
		return nil, err
	}

	// Use nix eval <flakeRef>#<attr> --json
	cmd := exec.CommandContext(ctx, nixBin, "eval", "--json", flakeAttr)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("nix eval failed: %w\nstderr: %s", err, stderr.String())
	}

	return &EvalExprResult{Raw: stdout.Bytes()}, nil
}

// GetDbSchemas evaluates the db module and returns all schemas for codegen
func GetDbSchemas(ctx context.Context) (map[string]interface{}, error) {
	result, err := EvalExpr(ctx, DbSchemasPreset)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate db schemas: %w", err)
	}

	var schemas map[string]interface{}
	if err := result.Unmarshal(&schemas); err != nil {
		return nil, fmt.Errorf("failed to parse db schemas: %w", err)
	}

	return schemas, nil
}

// BuildExpr performs simple ${key} substitution on a Nix expression template.
// Values are escaped for safe embedding in Nix double-quoted strings (backslashes,
// quotes, and ${ interpolation sequences are all escaped).
//
// This is intentionally not a full template engine -- for complex expressions,
// prefer --argstr or build the expression programmatically.
func BuildExpr(template string, vars map[string]string) string {
	result := template
	for k, v := range vars {
		escaped := strings.ReplaceAll(v, "\\", "\\\\")
		escaped = strings.ReplaceAll(escaped, "\"", "\\\"")
		escaped = strings.ReplaceAll(escaped, "${", "\\${")
		result = strings.ReplaceAll(result, "${"+k+"}", escaped)
	}
	return result
}

// InstalledPackage represents a package installed in the devenv/stackpanel config
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

// GetInstalledPackages returns the list of packages in the devshell. It uses
// a waterfall of increasingly expensive strategies:
//
//  1. Explicit configJSONPath (from options)
//  2. STACKPANEL_CONFIG_JSON env var (pre-computed at shell entry)
//  3. State file at .stack/profile/stackpanel.json
//  4. Generated config at .stack/gen/config.json
//  5. Raw packages.nix data file (user-installed only, no devshell packages)
//  6. Full flake evaluation (slow -- may download from caches, 5min timeout)
//
// The fast paths (1-4) read pre-generated JSON from disk. The slow path (6)
// evaluates the actual flake, which triggers a full Nix build if the evaluation
// requires IFD (import-from-derivation).
func GetInstalledPackages(ctx context.Context, opts GetInstalledPackagesOptions) ([]InstalledPackage, error) {
	projectRoot := opts.ProjectRoot

	// Resolve project root first (needed for file-based lookups)
	if projectRoot == "" {
		projectRoot = findProjectRoot()
	}

	// Fast path 1: explicit config JSON path (e.g., from executor's devshell env)
	if opts.ConfigJSONPath != "" {
		packages, err := getInstalledPackagesFromJSON(opts.ConfigJSONPath)
		if err == nil && len(packages) > 0 {
			return packages, nil
		}
	}

	// Fast path 2: try to read from STACKPANEL_CONFIG_JSON env var
	if configPath := os.Getenv("STACKPANEL_CONFIG_JSON"); configPath != "" {
		packages, err := getInstalledPackagesFromJSON(configPath)
		if err == nil && len(packages) > 0 {
			return packages, nil
		}
	}

	// Fast path 3: try state file (.stack/profile then .stackpanel/state)
	if projectRoot != "" {
		for _, p := range []string{projectRoot + "/.stack/profile/stackpanel.json", projectRoot + "/.stackpanel/state/stackpanel.json"} {
			packages, err := getInstalledPackagesFromJSON(p)
			if err == nil && len(packages) > 0 {
				return packages, nil
			}
		}
	}

	// Fast path 4: try generated config (.stack/gen then .stackpanel/gen)
	if projectRoot != "" {
		for _, p := range []string{projectRoot + "/.stack/gen/config.json", projectRoot + "/.stackpanel/gen/config.json"} {
			packages, err := getInstalledPackagesFromJSON(p)
			if err == nil && len(packages) > 0 {
				return packages, nil
			}
		}
	}

	// Fast path 5: try reading user packages directly from data file
	if projectRoot != "" {
		userPackages, err := getUserPackagesFromDataFile(projectRoot)
		if err == nil && len(userPackages) > 0 {
			// Return user packages if we can't get the full list from config
			return userPackages, nil
		}
	}

	// Slow path: evaluate from flake
	if projectRoot == "" {
		return nil, fmt.Errorf("no project root found - set STACKPANEL_ROOT or pass projectRoot")
	}

	expr := InstalledPackagesExpr(projectRoot)
	// 5 minutes allows time for Nix to download packages from caches
	result, err := EvalExprWithTimeout(ctx, expr, 5*time.Minute)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate installed packages: %w", err)
	}

	var packages []InstalledPackage
	if err := result.Unmarshal(&packages); err != nil {
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

// getUserPackagesFromDataFile reads user-installed packages from .stack/data or .stackpanel/data
// This is a fallback when the config JSON doesn't have packages or doesn't exist yet.
// The file format is a simple Nix list of attribute path strings:
//
//	[ "ripgrep" "jq" "htop" ]
func getUserPackagesFromDataFile(projectRoot string) ([]InstalledPackage, error) {
	packagesFile := projectRoot + "/.stack/data/packages.nix"
	if _, err := os.Stat(packagesFile); os.IsNotExist(err) {
		packagesFile = projectRoot + "/.stackpanel/data/packages.nix"
	}
	if _, err := os.Stat(packagesFile); os.IsNotExist(err) {
		return nil, err
	}

	// Use nix eval to read the file (it's a Nix expression, not JSON)
	nixBin, err := findNixBin()
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, nixBin, "eval", "--json", "-f", packagesFile)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("nix eval failed: %w\nstderr: %s", err, stderr.String())
	}

	// Parse as list of strings (attribute paths)
	var attrPaths []string
	if err := json.Unmarshal(stdout.Bytes(), &attrPaths); err != nil {
		return nil, fmt.Errorf("failed to parse packages.nix: %w", err)
	}

	// Convert to InstalledPackage structs
	packages := make([]InstalledPackage, 0, len(attrPaths))
	for _, attrPath := range attrPaths {
		packages = append(packages, InstalledPackage{
			Name:     attrPath, // Use attr path as name (will be resolved by Nix)
			AttrPath: attrPath,
			Source:   "user",
		})
	}

	return packages, nil
}

// GetInstalledPackageNames returns a set of lowercased package names and attr
// paths for O(1) membership checks. Both Name and AttrPath are indexed so
// lookups work regardless of which identifier the caller has.
func GetInstalledPackageNames(ctx context.Context, opts GetInstalledPackagesOptions) (map[string]bool, error) {
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
