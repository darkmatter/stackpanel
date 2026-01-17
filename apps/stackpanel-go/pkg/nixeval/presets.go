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

// Preset Nix expressions for common evaluations
// These are self-contained snippets that can be evaluated directly
const (
	// UsersPreset evaluates the users configuration from .stackpanel/data/users.nix
	// Returns the users attrset in stackpanel.users format
	UsersPreset = `
let
  root = builtins.getEnv "STACKPANEL_ROOT";
  usersPath = root + "/.stackpanel/data/users.nix";
in
  if builtins.pathExists usersPath
  then import usersPath
  else {}
`

	// GitHubCollaboratorsPreset evaluates raw collaborators data
	GitHubCollaboratorsPreset = `
let
  root = builtins.getEnv "STACKPANEL_ROOT";
  collabsPath = root + "/.stackpanel/data/github-collaborators.nix";
in
  if builtins.pathExists collabsPath
  then import collabsPath
  else { collaborators = {}; }
`

	// StackpanelConfigPreset evaluates the full stackpanel config from .stackpanel/config.nix
	StackpanelConfigPreset = `
let
  root = builtins.getEnv "STACKPANEL_ROOT";
  configPath = root + "/.stackpanel/config.nix";
in
  if builtins.pathExists configPath
  then (import configPath { pkgs = null; lib = null; config = {}; inputs = {}; }).stackpanel or {}
  else {}
`

	// StackpanelSerializablePreset evaluates the serializable config from the flake output
	// This includes computed values like devshell._commandsSerializable
	StackpanelSerializablePreset = `.#stackpanelConfig`

	// ActiveConfig returns the current active stackpanel configuration as JSON (evaluated)
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

// InstalledPackagesExpr builds a Nix expression to get installed packages from a flake.
// Uses the pre-computed .#stackpanelPackages flake output for fast evaluation.
// The projectRoot is baked directly into the expression to avoid relying on environment variables.
// Uses git+file:// protocol to avoid copying untracked files (node_modules, etc.)
func InstalledPackagesExpr(projectRoot string) string {
	return fmt.Sprintf(`
let
  flake = builtins.getFlake "git+file://%s";
in
  # Use pre-computed stackpanelPackages if available (fast path)
  if flake ? stackpanelPackages then
    flake.stackpanelPackages
  # Fallback: try to get from devshell passthru (slower)
  else
    let
      system = builtins.currentSystem;
      devShell = flake.devShells.${system}.default or null;
      stackpanelPackages = if devShell != null then devShell.passthru.stackpanelPackages or null else null;
    in
      if stackpanelPackages != null then stackpanelPackages else []
`, projectRoot)
}

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

// GetStackpanelConfig evaluates the stackpanel section from .stackpanel/config.nix
// Note: This is a simplified evaluation that doesn't have access to pkgs/lib
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
// for scaffolding a new project
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

// BuildExpr builds a Nix expression from a template with variables
// Variables are substituted as string interpolations
func BuildExpr(template string, vars map[string]string) string {
	result := template
	for k, v := range vars {
		// Escape the value for Nix string embedding
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

// GetInstalledPackages returns the list of installed packages from the devshell configuration.
// It tries multiple fast paths before falling back to slow nix eval:
//  1. Explicit configJSONPath (if provided in options)
//  2. STACKPANEL_CONFIG_JSON env var (pre-computed at shell entry)
//  3. State file at .stackpanel/state/stackpanel.json
//  4. Generated config at .stackpanel/gen/config.json
//  5. Nix eval against the flake (slow, last resort)
//
// If projectRoot is empty, it will attempt to find it from STACKPANEL_ROOT env var
// or by searching up from the current directory.
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

	// Fast path 3: try state file
	if projectRoot != "" {
		stateFile := projectRoot + "/.stackpanel/state/stackpanel.json"
		packages, err := getInstalledPackagesFromJSON(stateFile)
		if err == nil && len(packages) > 0 {
			return packages, nil
		}
	}

	// Fast path 4: try generated config
	if projectRoot != "" {
		genConfig := projectRoot + "/.stackpanel/gen/config.json"
		packages, err := getInstalledPackagesFromJSON(genConfig)
		if err == nil && len(packages) > 0 {
			return packages, nil
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
	result, err := EvalExprWithTimeout(ctx, expr, 60*time.Second)
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

// getUserPackagesFromDataFile reads user-installed packages from .stackpanel/data/packages.nix
// This is a fallback when the config JSON doesn't have packages or doesn't exist yet.
// The file format is a simple Nix list of attribute path strings:
//
//	[ "ripgrep" "jq" "htop" ]
func getUserPackagesFromDataFile(projectRoot string) ([]InstalledPackage, error) {
	packagesFile := projectRoot + "/.stackpanel/data/packages.nix"

	// Check if file exists
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

// GetInstalledPackageNames returns just the package names as a set for fast lookup.
// If projectRoot is empty, it will attempt to find it automatically.
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
