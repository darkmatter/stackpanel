// Package configsync implements the config formatter/sync logic.
//
// The formatter ensures that user-defined config in .stackpanel/config.nix
// gets migrated to .stackpanel/data/*.nix files (the canonical machine-writable
// data layer). This keeps config.nix small (only Nix-expression stuff that
// can't be plain data) and data files authoritative.
//
// Algorithm:
//  1. Eval the merged user config (_internal.nix) → raw user values (no module defaults)
//  2. Eval each data/*.nix file individually → data layer values
//  3. Diff per entity: userConfig[entity] vs dataFile[entity]
//  4. Keys/values in user config but not data file → came from config.nix
//  5. Sync: write those entries to data files
package configsync

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	nixser "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
)

// =============================================================================
// Types
// =============================================================================

// CheckResult is the output of a config check.
type CheckResult struct {
	// Entities with differences between merged config and data files.
	Diffs []EntityDiff `json:"diffs"`

	// Entities that failed to evaluate (e.g., derivation in JSON).
	Errors []EntityError `json:"errors"`

	// True if everything is in sync (no diffs, no errors).
	InSync bool `json:"in_sync"`
}

// EntityDiff describes differences for a single entity (e.g., "apps").
type EntityDiff struct {
	// Entity name (e.g., "apps", "variables").
	Entity string `json:"entity"`

	// Keys present in merged config but missing from the data file.
	// These came from config.nix and should be migrated.
	ExtraKeys []string `json:"extra_keys,omitempty"`

	// Keys present in both but with different values.
	// config.nix is overriding data file values.
	OverriddenKeys []string `json:"overridden_keys,omitempty"`

	// For non-map entities: true if the entire value differs.
	ValueDiffers bool `json:"value_differs,omitempty"`
}

// EntityError describes an eval failure for an entity.
type EntityError struct {
	Entity string `json:"entity"`
	Error  string `json:"error"`
}

// SyncResult is the output of a config sync.
type SyncResult struct {
	// Entities that were updated.
	Updated []EntityUpdate `json:"updated"`

	// Entities that failed to sync.
	Errors []EntityError `json:"errors"`
}

// EntityUpdate describes what was synced for an entity.
type EntityUpdate struct {
	Entity string   `json:"entity"`
	Keys   []string `json:"keys"` // Keys that were written to the data file
}

// =============================================================================
// Public API
// =============================================================================

// Check compares the merged user config against data files and returns diffs.
func Check(projectRoot string) (*CheckResult, error) {
	result := &CheckResult{}

	// 1. List data files
	entities, err := listDataEntities(projectRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to list data entities: %w", err)
	}

	// 2. Eval user config AND all data files in parallel (2 nix eval calls total)
	type evalResult struct {
		data map[string]any
		err  error
	}
	userCh := make(chan evalResult, 1)
	dataCh := make(chan evalResult, 1)

	go func() {
		cfg, err := evalUserConfig(projectRoot)
		userCh <- evalResult{cfg, err}
	}()
	go func() {
		data, err := evalAllDataFiles(projectRoot, entities)
		dataCh <- evalResult{data, err}
	}()

	userRes := <-userCh
	dataRes := <-dataCh

	if userRes.err != nil {
		return nil, fmt.Errorf("failed to eval user config: %w", userRes.err)
	}
	userConfig := userRes.data

	if dataRes.err != nil {
		return nil, fmt.Errorf("failed to eval data files: %w", dataRes.err)
	}
	allData := dataRes.data

	// 3. For each entity, compare
	for _, entity := range entities {
		dataValue, exists := allData[entity]
		if !exists {
			result.Errors = append(result.Errors, EntityError{
				Entity: entity,
				Error:  "not found in batch eval result",
			})
			continue
		}

		userValue, exists := userConfig[entity]
		if !exists {
			continue
		}

		diff := compareEntityValues(entity, userValue, dataValue)
		if diff != nil {
			result.Diffs = append(result.Diffs, *diff)
		}
	}

	// 4. Check for entities in user config that don't have a data file at all
	entitySet := make(map[string]bool, len(entities))
	for _, e := range entities {
		entitySet[e] = true
	}
	for key := range userConfig {
		if entitySet[key] || isSkippedConfigKey(key) {
			continue
		}
		result.Diffs = append(result.Diffs, EntityDiff{
			Entity:       key,
			ValueDiffers: true,
		})
	}

	result.InSync = len(result.Diffs) == 0 && len(result.Errors) == 0
	return result, nil
}

// Sync migrates config.nix entries to data files.
func Sync(projectRoot string) (*SyncResult, error) {
	result := &SyncResult{}

	// 1. Get the check result
	check, err := Check(projectRoot)
	if err != nil {
		return nil, err
	}

	if check.InSync {
		return result, nil // Nothing to do
	}

	// 2. Eval user config again for the values to write
	userConfig, err := evalUserConfig(projectRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to eval user config: %w", err)
	}

	// 3. For each entity with diffs, write the merged value to the data file
	for _, diff := range check.Diffs {
		userValue, exists := userConfig[diff.Entity]
		if !exists {
			continue
		}

		if isMapEntity(diff.Entity) {
			// Map entity (apps, variables, users): do key-level updates
			userMap, ok := toStringMap(userValue)
			if !ok {
				result.Errors = append(result.Errors, EntityError{
					Entity: diff.Entity,
					Error:  "expected map value for map entity",
				})
				continue
			}

			// Write the full merged map to the data file
			err := writeDataFile(projectRoot, diff.Entity, userMap)
			if err != nil {
				result.Errors = append(result.Errors, EntityError{
					Entity: diff.Entity,
					Error:  err.Error(),
				})
				continue
			}

			keys := append(diff.ExtraKeys, diff.OverriddenKeys...)
			result.Updated = append(result.Updated, EntityUpdate{
				Entity: diff.Entity,
				Keys:   keys,
			})
		} else {
			// Non-map entity: write the full value
			err := writeDataFile(projectRoot, diff.Entity, userValue)
			if err != nil {
				result.Errors = append(result.Errors, EntityError{
					Entity: diff.Entity,
					Error:  err.Error(),
				})
				continue
			}

			result.Updated = append(result.Updated, EntityUpdate{
				Entity: diff.Entity,
			})
		}
	}

	return result, nil
}

// =============================================================================
// Comparison Logic
// =============================================================================

// compareEntityValues compares a merged user config value with a data file value.
func compareEntityValues(entity string, userValue, dataValue any) *EntityDiff {
	if isMapEntity(entity) {
		return compareMapEntity(entity, userValue, dataValue)
	}
	return compareScalarEntity(entity, userValue, dataValue)
}

// compareMapEntity compares map entities (apps, variables, users) at the key level.
func compareMapEntity(entity string, userValue, dataValue any) *EntityDiff {
	userMap, userOK := toStringMap(userValue)
	dataMap, dataOK := toStringMap(dataValue)

	if !userOK || !dataOK {
		// Can't compare as maps — treat as scalar
		return compareScalarEntity(entity, userValue, dataValue)
	}

	var extraKeys []string
	var overriddenKeys []string

	for key, uv := range userMap {
		dv, exists := dataMap[key]
		if !exists {
			extraKeys = append(extraKeys, key)
		} else if !deepEqual(uv, dv) {
			overriddenKeys = append(overriddenKeys, key)
		}
	}

	if len(extraKeys) == 0 && len(overriddenKeys) == 0 {
		return nil // In sync
	}

	sort.Strings(extraKeys)
	sort.Strings(overriddenKeys)

	return &EntityDiff{
		Entity:         entity,
		ExtraKeys:      extraKeys,
		OverriddenKeys: overriddenKeys,
	}
}

// compareScalarEntity compares non-map entities as a whole.
func compareScalarEntity(entity string, userValue, dataValue any) *EntityDiff {
	if deepEqual(userValue, dataValue) {
		return nil
	}
	return &EntityDiff{
		Entity:       entity,
		ValueDiffers: true,
	}
}

// =============================================================================
// Helpers
// =============================================================================

// isMapEntity returns true for entities that are key-value maps.
func isMapEntity(entity string) bool {
	switch entity {
	case "apps", "variables", "users", "tasks", "services":
		return true
	default:
		return false
	}
}

// isSkippedConfigKey returns true for config keys that aren't expected
// to have a corresponding data file (they're module-only or structural).
func isSkippedConfigKey(key string) bool {
	skip := map[string]bool{
		// Module-evaluated keys (not user data)
		"enable":          true,
		"devshell":        true,
		"process-compose": true,
		"appModules":      true,
		"serviceModules":  true,
		"modules":         true,
		"files":           true,
		"gitignore":       true,
		"root":            true,
		"root-marker":     true,
		"dirs":            true,
		"computed":        true,
		"userPackages":    true,
		// Settings that belong in config.nix (Nix expressions)
		"globalServices": true,
		// Internal metadata
		"_meta": true,
	}
	return skip[key]
}

// Entities excluded from data table loading in _internal.nix.
// These should also be excluded from config sync.
var dataOnlyFiles = map[string]bool{
	"commands": true,
	"packages": true,
}

// listDataEntities lists all data entities (filenames without .nix extension)
// from .stackpanel/data/, excluding special files.
func listDataEntities(projectRoot string) ([]string, error) {
	dataDir := filepath.Join(projectRoot, ".stackpanel", "data")
	entries, err := os.ReadDir(dataDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	var entities []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !strings.HasSuffix(name, ".nix") {
			continue
		}
		if name == "default.nix" {
			continue
		}
		if strings.HasPrefix(name, "_") {
			continue
		}
		entity := strings.TrimSuffix(name, ".nix")
		if dataOnlyFiles[entity] {
			continue
		}
		entities = append(entities, entity)
	}

	sort.Strings(entities)
	return entities, nil
}

// toStringMap converts an any value to map[string]any if possible.
func toStringMap(v any) (map[string]any, bool) {
	m, ok := v.(map[string]any)
	return m, ok
}

// deepEqual compares two JSON-like values for equality.
func deepEqual(a, b any) bool {
	// Marshal both to JSON and compare strings.
	// This normalizes numeric types, ordering, etc.
	ja, err1 := json.Marshal(a)
	jb, err2 := json.Marshal(b)
	if err1 != nil || err2 != nil {
		return false
	}
	return string(ja) == string(jb)
}

// =============================================================================
// Nix Evaluation
// =============================================================================

// Default timeout for nix eval commands.
const nixEvalTimeout = 60 * time.Second

// evalUserConfig gets the raw merged user config (data + config.nix),
// WITHOUT module defaults.
//
// Uses the flake output .#legacyPackages.SYSTEM.stackpanelRawConfig which is:
//   - The raw _internal.nix result filtered to JSON-serializable values
//   - Fast because it shares the Nix eval cache with other flake evaluations
//   - Pre-computed as part of the flake (no separate nixpkgs import needed)
func evalUserConfig(projectRoot string) (map[string]any, error) {
	// Use the top-level flake output (fast — avoids forcing perSystem evaluation).
	args := []string{"eval", "--impure", "--json", ".#stackpanelRawConfig"}

	ctx, cancel := context.WithTimeout(context.Background(), nixEvalTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Dir = projectRoot

	out, err := cmd.Output()
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return nil, fmt.Errorf("nix eval timed out after %s (is the flake eval cache warm? try running 'nix eval .#stackpanelConfig' first)", nixEvalTimeout)
		}
		if ee, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("nix eval failed: %s", strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, err
	}

	var config map[string]any
	if err := json.Unmarshal(out, &config); err != nil {
		return nil, fmt.Errorf("failed to parse user config JSON: %w", err)
	}

	return config, nil
}

// evalAllDataFiles evaluates all data files in a single nix eval call.
// Returns a map of entity name → evaluated value.
func evalAllDataFiles(projectRoot string, entities []string) (map[string]any, error) {
	if len(entities) == 0 {
		return map[string]any{}, nil
	}

	dataDir := filepath.Join(projectRoot, ".stackpanel", "data")

	// Build a single Nix expression: { apps = import ./apps.nix; vars = import ./vars.nix; ... }
	var sb strings.Builder
	sb.WriteString("{\n")
	for _, entity := range entities {
		absPath := filepath.Join(dataDir, entity+".nix")
		sb.WriteString(fmt.Sprintf("  %s = import %s;\n", entity, absPath))
	}
	sb.WriteString("}")

	ctx, cancel := context.WithTimeout(context.Background(), nixEvalTimeout)
	defer cancel()

	args := []string{"eval", "--impure", "--json", "--expr", sb.String()}
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Dir = projectRoot

	out, err := cmd.Output()
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return nil, fmt.Errorf("nix eval timed out after %s", nixEvalTimeout)
		}
		if ee, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("nix eval failed: %s", strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, err
	}

	var result map[string]any
	if err := json.Unmarshal(out, &result); err != nil {
		return nil, fmt.Errorf("failed to parse data files JSON: %w", err)
	}

	return result, nil
}

// evalDataFile evaluates a single .stackpanel/data/<entity>.nix file.
// Used by Sync() when re-reading individual entities after writing.
func evalDataFile(projectRoot, entity string) (any, error) {
	dataPath := filepath.Join(projectRoot, ".stackpanel", "data", entity+".nix")

	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("data file does not exist: %s", dataPath)
	}

	ctx, cancel := context.WithTimeout(context.Background(), nixEvalTimeout)
	defer cancel()

	args := []string{"eval", "--impure", "--json", "-f", dataPath}
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Dir = projectRoot

	out, err := cmd.Output()
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return nil, fmt.Errorf("nix eval timed out after %s", nixEvalTimeout)
		}
		if ee, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("nix eval failed: %s", strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, err
	}

	var value any
	if err := json.Unmarshal(out, &value); err != nil {
		return nil, fmt.Errorf("failed to parse data file JSON: %w", err)
	}

	return value, nil
}

// writeDataFile writes a value to .stackpanel/data/<entity>.nix using nix serialization.
// For now, we shell out to a simple approach: JSON → Nix via the nix serialize package.
// This is called from Sync() and uses the pkg/nix serializer.
func writeDataFile(projectRoot, entity string, value any) error {
	dataDir := filepath.Join(projectRoot, ".stackpanel", "data")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return err
	}

	dataPath := filepath.Join(dataDir, entity+".nix")

	// Serialize Go value to Nix expression
	nixExpr, err := serializeToNix(value)
	if err != nil {
		return fmt.Errorf("failed to serialize to Nix: %w", err)
	}

	// Try to format with nixfmt
	nixExpr = tryNixfmt(nixExpr)

	return os.WriteFile(dataPath, []byte(nixExpr+"\n"), 0o644)
}

// serializeToNix converts a Go value (from JSON) to a Nix expression string.
// Uses the existing pkg/nix serializer for direct Go→Nix conversion (no subprocess).
func serializeToNix(value any) (string, error) {
	return nixser.SerializeIndented(value, "  ")
}

// tryNixfmt attempts to format a Nix expression with nixfmt.
func tryNixfmt(nixExpr string) string {
	cmd := exec.Command("nixfmt")
	cmd.Stdin = strings.NewReader(nixExpr)
	out, err := cmd.Output()
	if err != nil {
		return nixExpr // Return unformatted if nixfmt fails
	}
	return strings.TrimSpace(string(out))
}
