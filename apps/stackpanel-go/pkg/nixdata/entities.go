// Package nixdata provides core Nix data operations for reading, writing,
// and transforming Stackpanel configuration stored in .nix files.
//
// This package is the shared foundation used by both the agent HTTP server
// and the CLI. It has no dependency on net/http or any transport layer.
package nixdata

import "errors"

// ValidateEntityName checks that a Nix data entity name is well-formed.
// These constraints mirror Nix attribute name rules (plus hyphens), and the
// 64-char limit prevents filesystem issues with generated paths.
func ValidateEntityName(name string) error {
	if name == "" {
		return errors.New("entity name cannot be empty")
	}
	if len(name) > 64 {
		return errors.New("entity name too long (max 64 chars)")
	}
	for i, r := range name {
		if i == 0 {
			if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_') {
				return errors.New("entity name must start with a letter or underscore")
			}
		} else {
			if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_') {
				return errors.New("entity name can only contain letters, numbers, hyphens, and underscores")
			}
		}
	}
	return nil
}

// IsExternalEntity returns true if the entity is provided by an external
// source (e.g. "external-github-collaborators"). External entities are
// read-only — they're synced from external systems and must not be modified
// by the UI or CLI.
func IsExternalEntity(name string) bool {
	return len(name) > 9 && name[:9] == "external-"
}

// IsMapEntity returns true if the entity is stored as a Nix attribute set
// keyed by user-defined IDs (e.g. apps, variables, users). Map entities
// support key-level reads and writes so that individual entries can be
// updated without replacing the whole file.
func IsMapEntity(entity string) bool {
	switch entity {
	case "apps", "variables", "users":
		return true
	default:
		return false
	}
}

// IsEvaluatedEntity returns true if the entity should be read from the
// fully-evaluated flake config rather than from the raw data file. Evaluated
// entities include values contributed by Nix modules that don't exist in the
// raw data file (e.g. "variables" merges user-defined and module-generated vars).
func IsEvaluatedEntity(entity string) bool {
	switch entity {
	case "variables":
		return true
	default:
		return false
	}
}

// PrefersConsolidatedConfig returns true for entities that should always be read
// and written through .stack/config.nix, bypassing any legacy per-entity files.
// This drives the migration from individual .stack/data/<entity>.nix files to
// the single config.nix source of truth.
func PrefersConsolidatedConfig(entity string) bool {
	switch entity {
	case "variables", "users", "secrets":
		return true
	default:
		return false
	}
}

// MapFieldNames returns the set of JSON/Nix attribute names whose children
// are user-defined map keys that must NOT be case-transformed. Without this,
// a variable key like "/apps/web/port" would be mangled to "/apps/web/port"
// during camelCase<->kebab-case conversion.
//
// SYNC: Must stay in sync with MAP_FIELD_NAMES in
// apps/web/src/lib/nix-data/index.ts.
func MapFieldNames() map[string]struct{} {
	return map[string]struct{}{
		"aliases":       {},
		"apps":          {},
		"categories":    {},
		"codegen":       {},
		"collaborators": {},
		"commands":      {},
		"databases":     {},
		"env":           {},
		"environments":  {},
		"entries":       {},
		"extensions":    {},
		"masterKeys":    {},
		"modules":       {},
		"outputs":       {},
		"scripts":       {},
		"sites":         {},
		"steps":         {},
		"tasks":         {},
		"users":         {},
		"variables":     {},
		"zones":         {},
	}
}
