package nixdata

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
	executor "github.com/darkmatter/stackpanel/stackpanel-go/pkg/exec"
	nixser "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
	"github.com/rs/zerolog/log"
)

// RawExpr is a Nix expression that should be written verbatim (no string quoting).
// Use this for computed values like "config.services.postgres.port" that must
// remain as live Nix references rather than being serialized as string literals.
type RawExpr string

// DeleteValue is a sentinel type: pass it as the value to PatchConsolidatedData
// or SetKey to remove the target binding from config.nix.
type DeleteValue struct{}

// NixRunner is the interface required by Store to evaluate Nix expressions.
//
// *exec.Executor satisfies this interface directly — no adapter is needed
// when constructing a Store from the agent server or CLI:
//
//	exec, _ := executor.New(projectRoot, nil)
//	store := nixdata.NewStore(projectRoot, exec)
//
// For tests, any type with a matching RunNix method works.
type NixRunner interface {
	RunNix(args ...string) (*executor.Result, error)
}

// Store provides read, write, and patch operations on the Nix data files
// that back a Stackpanel project's configuration.
//
// It is transport-agnostic: the agent HTTP server and the CLI both
// construct a Store with the same project root and nix runner, then call
// the same methods.
type Store struct {
	paths *Paths
	nix   NixRunner
}

// NewStore creates a Store for the project at projectRoot. The provided
// NixRunner is used for all nix eval invocations.
func NewStore(projectRoot string, nix NixRunner) *Store {
	return &Store{
		paths: NewPaths(projectRoot),
		nix:   nix,
	}
}

// Paths returns the underlying path resolver. This is useful when callers
// need raw filesystem paths (e.g. for file watchers).
func (s *Store) Paths() *Paths {
	return s.paths
}

// ---------------------------------------------------------------------------
// Read
// ---------------------------------------------------------------------------

// ReadEntity evaluates the Nix file for entity and returns the parsed Go
// value (typically map[string]any or []any). Returns nil (not an error) if
// the entity file doesn't exist yet — callers should treat nil as "empty".
//
// For external entities the external data path is used; for consolidated
// configs only the entity's attribute is extracted via a Nix expression
// that plucks the key from the full config.nix attrset.
func (s *Store) ReadEntity(entity string) (any, error) {
	if err := ValidateEntityName(entity); err != nil {
		return nil, err
	}

	dataPath := s.paths.EntityPath(entity)
	isConsolidated := s.paths.IsUsingConsolidatedConfig(entity)
	if IsExternalEntity(entity) {
		dataPath = s.paths.ExternalEntityPath(entity)
		isConsolidated = false
	}

	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		return nil, nil // entity does not exist
	}

	args := []string{"eval", "--impure", "--json"}
	if isConsolidated {
		args = append(args, "--expr", s.configEntityEvalExpr(entity))
	} else {
		args = append(args, "-f", dataPath)
	}

	res, err := s.nix.RunNix(args...)
	if err != nil {
		return nil, fmt.Errorf("nix eval: %w", err)
	}
	if res.ExitCode != 0 {
		return nil, errors.New(strings.TrimSpace(res.Stderr))
	}

	var data any
	if err := json.Unmarshal([]byte(res.Stdout), &data); err != nil {
		return nil, fmt.Errorf("parse nix eval output: %w", err)
	}

	return data, nil
}

// ReadEntityJSON reads entity and returns its JSON representation with
// keys converted to camelCase (suitable for protojson / Connect-RPC
// handlers). Map entities are wrapped in an envelope keyed by entity name
// to match the proto message shape, e.g. {"apps": {...}} for the "apps" entity.
//
// Returns "{}" (not null) when the entity file is missing, so callers
// can always unmarshal without nil checks.
func (s *Store) ReadEntityJSON(entity string) ([]byte, error) {
	if err := ValidateEntityName(entity); err != nil {
		return nil, err
	}

	dataPath := s.paths.EntityPath(entity)
	isConsolidated := s.paths.IsUsingConsolidatedConfig(entity)
	if IsExternalEntity(entity) {
		dataPath = s.paths.ExternalEntityPath(entity)
		isConsolidated = false
	}

	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		return []byte("{}"), nil
	}

	args := []string{"eval", "--impure", "--json"}
	if isConsolidated {
		args = append(args, "--expr", s.configEntityEvalExpr(entity))
	} else {
		args = append(args, "-f", dataPath)
	}

	res, err := s.nix.RunNix(args...)
	if err != nil {
		return nil, fmt.Errorf("nix eval: %w", err)
	}
	if res.ExitCode != 0 {
		return nil, errors.New(strings.TrimSpace(res.Stderr))
	}

	var parsed any
	if err := json.Unmarshal([]byte(res.Stdout), &parsed); err != nil {
		return nil, fmt.Errorf("parse nix eval output: %w", err)
	}

	if IsMapEntity(entity) {
		parsed = map[string]any{entity: parsed}
	}

	raw, err := json.Marshal(parsed)
	if err != nil {
		return nil, err
	}
	return NixJSONToCamelCase(raw, MapFieldNames())
}

// ReadRawNixFile evaluates a Nix data file via builtins.toJSON/fromJSON
// round-trip. Unlike ReadEntity (which may use the evaluated flake output),
// this always returns the literal file contents. This distinction matters for
// key-level updates: we must read-modify-write without picking up values
// injected by Nix modules (e.g. module-generated variables that shouldn't
// be persisted back into the data file).
func (s *Store) ReadRawNixFile(entity string) (any, error) {
	dataPath := s.paths.EntityPath(entity)
	expr := "builtins.fromJSON (builtins.toJSON (" + s.importExpr(dataPath) + "))"
	if s.paths.IsUsingConsolidatedConfig(entity) {
		expr = "builtins.fromJSON (builtins.toJSON (" + s.configEntityEvalExpr(entity) + "))"
	}

	res, err := s.nix.RunNix("eval", "--impure", "--json", "--expr", expr)
	if err != nil {
		return nil, fmt.Errorf("nix eval: %w", err)
	}
	if res.ExitCode != 0 {
		return nil, fmt.Errorf("nix eval failed: %s", res.Stderr)
	}

	var data any
	if err := json.Unmarshal([]byte(res.Stdout), &data); err != nil {
		return nil, fmt.Errorf("parse nix eval output: %w", err)
	}
	return data, nil
}

// ---------------------------------------------------------------------------
// Write
// ---------------------------------------------------------------------------

// WriteEntity serialises data as a Nix expression and writes it to the
// entity's data file. Expects keys to already be in kebab-case if the data
// came from the HTTP layer — no key transformation is performed here.
//
// For consolidated config, this does a full read-modify-write of config.nix
// (updating only this entity's key). For legacy per-entity files it writes
// the file directly. Returns the path of the written file.
func (s *Store) WriteEntity(entity string, data any) (string, error) {
	if err := ValidateEntityName(entity); err != nil {
		return "", err
	}
	if IsExternalEntity(entity) {
		return "", errors.New("external entities are read-only")
	}

	if err := s.paths.EnsureDir(); err != nil {
		return "", fmt.Errorf("create data directory: %w", err)
	}

	// For consolidated config, update only this entity's key within the
	// full config.nix file so sibling entities are preserved.
	if s.paths.IsUsingConsolidatedConfig(entity) {
		fullConfig, err := s.ReadConsolidatedData()
		if err != nil {
			return "", fmt.Errorf("read config.nix for entity write: %w", err)
		}
		fullConfig[entity] = data
		if err := s.WriteConsolidatedData(fullConfig); err != nil {
			return "", fmt.Errorf("write config.nix: %w", err)
		}
		dataPath := s.paths.ConfigFilePath()
		log.Info().
			Str("entity", entity).
			Str("path", dataPath).
			Msg("nixdata.Store: wrote entity (consolidated)")
		return dataPath, nil
	}

	// Legacy per-entity file: write directly.
	nixExpr, err := nixser.SerializeIndented(data, "  ")
	if err != nil {
		return "", fmt.Errorf("serialize to nix: %w", err)
	}

	dataPath := s.paths.EntityPath(entity)
	if err := os.WriteFile(dataPath, []byte(nixExpr+"\n"), 0o644); err != nil {
		return "", fmt.Errorf("write data file: %w", err)
	}

	log.Info().
		Str("entity", entity).
		Str("path", dataPath).
		Msg("nixdata.Store: wrote entity")

	return dataPath, nil
}

// WriteEntityJSON accepts camelCase JSON bytes (e.g. from protojson),
// transforms keys to kebab-case, unwraps map entity envelopes (removing the
// outer {"apps": ...} wrapper), and writes the result. This is the primary
// entry point for the agent HTTP handlers.
func (s *Store) WriteEntityJSON(entity string, data []byte) (string, error) {
	if err := ValidateEntityName(entity); err != nil {
		return "", err
	}
	if IsExternalEntity(entity) {
		return "", errors.New("external entities are read-only")
	}

	transformed, err := CamelCaseToNixJSON(data, MapFieldNames())
	if err != nil {
		return "", fmt.Errorf("transform keys: %w", err)
	}

	var value any
	if err := json.Unmarshal(transformed, &value); err != nil {
		return "", fmt.Errorf("parse json: %w", err)
	}

	// Unwrap map entities to match Nix data files (store raw map).
	if IsMapEntity(entity) {
		if obj, ok := value.(map[string]any); ok {
			if inner, ok := obj[entity]; ok {
				value = inner
			}
		}
	}

	return s.WriteEntity(entity, value)
}

// ---------------------------------------------------------------------------
// Key-level updates
// ---------------------------------------------------------------------------

// SetKey performs a key-level upsert on a map entity. For consolidated
// config.nix, this uses source-preserving AST patching (via flakeedit) so
// that comments and formatting in the user's file are kept intact. For legacy
// per-entity files it falls back to read/modify/write which reformats the file.
//
// Pass a DeleteValue{} as value to remove the key instead.
func (s *Store) SetKey(entity, key string, value any) (string, error) {
	if err := ValidateEntityName(entity); err != nil {
		return "", err
	}
	if IsExternalEntity(entity) {
		return "", errors.New("external entities are read-only")
	}
	if key == "" {
		return "", errors.New("key is required")
	}
	if s.paths.IsUsingConsolidatedConfig(entity) {
		path := entity + "." + EscapeConfigPathSegment(key)
		if err := s.PatchConsolidatedData(path, value); err != nil {
			return "", err
		}
		return s.paths.ConfigFilePath(), nil
	}

	existing, err := s.readExistingMap(entity)
	if err != nil {
		return "", err
	}

	existing[key] = value

	return s.writeMap(entity, existing)
}

// DeleteKey removes a single key from a map entity. It is a no-op (returns
// the config path, nil error) if the key does not exist — this avoids forcing
// callers to check existence before deletion.
func (s *Store) DeleteKey(entity, key string) (string, error) {
	if err := ValidateEntityName(entity); err != nil {
		return "", err
	}
	if IsExternalEntity(entity) {
		return "", errors.New("external entities are read-only")
	}
	if key == "" {
		return "", errors.New("key is required")
	}
	if s.paths.IsUsingConsolidatedConfig(entity) {
		path := entity + "." + EscapeConfigPathSegment(key)
		if err := s.PatchConsolidatedData(path, DeleteValue{}); err != nil {
			return "", err
		}
		return s.paths.ConfigFilePath(), nil
	}

	existing, err := s.readExistingMap(entity)
	if err != nil {
		return "", err
	}

	delete(existing, key)

	return s.writeMap(entity, existing)
}

// readExistingMap reads the raw data file for entity and returns it as a
// map. If the file does not exist yet an empty map is returned.
//
// For consolidated config (config.nix), only the entity's subtree is
// returned — not the entire file.
func (s *Store) readExistingMap(entity string) (map[string]any, error) {
	dataPath := s.paths.EntityPath(entity)
	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		return make(map[string]any), nil
	}

	raw, err := s.ReadRawNixFile(entity)
	if err != nil {
		return nil, fmt.Errorf("read existing data: %w", err)
	}

	m, ok := raw.(map[string]any)
	if !ok {
		return make(map[string]any), nil
	}

	// For consolidated config, the raw import returns ALL top-level keys
	// (apps, variables, users, …). Extract just this entity's subtree so
	// that key-level updates don't corrupt sibling entities.
	if s.paths.IsUsingConsolidatedConfig(entity) {
		sub, exists := m[entity]
		if !exists {
			return make(map[string]any), nil
		}
		if subMap, ok := sub.(map[string]any); ok {
			return subMap, nil
		}
		return make(map[string]any), nil
	}

	return m, nil
}

// writeMap serialises a map to Nix and writes it to the entity's data file.
//
// For consolidated config (config.nix), only the entity's key is updated
// within the full file — sibling entities are preserved.
func (s *Store) writeMap(entity string, data map[string]any) (string, error) {
	if err := s.paths.EnsureDir(); err != nil {
		return "", fmt.Errorf("create data directory: %w", err)
	}

	// For consolidated config, read the full file, update only this
	// entity's key, and write everything back with section headers.
	if s.paths.IsUsingConsolidatedConfig(entity) {
		fullConfig, err := s.ReadConsolidatedData()
		if err != nil {
			return "", fmt.Errorf("read config.nix for key update: %w", err)
		}
		fullConfig[entity] = data
		if err := s.WriteConsolidatedData(fullConfig); err != nil {
			return "", fmt.Errorf("write config.nix: %w", err)
		}
		dataPath := s.paths.ConfigFilePath()
		log.Info().
			Str("entity", entity).
			Str("path", dataPath).
			Msg("nixdata.Store: wrote map entity (consolidated)")
		return dataPath, nil
	}

	// Legacy per-entity file: write directly.
	nixExpr, err := nixser.SerializeIndented(data, "  ")
	if err != nil {
		return "", fmt.Errorf("serialize to nix: %w", err)
	}

	dataPath := s.paths.EntityPath(entity)
	if err := os.WriteFile(dataPath, []byte(nixExpr+"\n"), 0o644); err != nil {
		return "", fmt.Errorf("write data file: %w", err)
	}

	log.Info().
		Str("entity", entity).
		Str("path", dataPath).
		Msg("nixdata.Store: wrote map entity")

	return dataPath, nil
}

// ---------------------------------------------------------------------------
// Consolidated config.nix
// ---------------------------------------------------------------------------

// ReadConsolidatedData reads the entire .stack/config.nix file and
// returns its top-level attributes as a map. config.nix may be either
// a plain attrset or a function ({pkgs, lib, ...}: { ... }); the Nix
// expression handles both forms by calling it with null arguments.
func (s *Store) ReadConsolidatedData() (map[string]any, error) {
	dataPath := s.paths.ConfigFilePath()

	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		return make(map[string]any), nil
	}

	res, err := s.nix.RunNix("eval", "--impure", "--json", "--expr", s.configEvalExpr())
	if err != nil {
		return nil, fmt.Errorf("nix eval: %w", err)
	}
	if res.ExitCode != 0 {
		return nil, fmt.Errorf("nix eval failed: %s", res.Stderr)
	}

	var data map[string]any
	if err := json.Unmarshal([]byte(res.Stdout), &data); err != nil {
		return nil, fmt.Errorf("parse nix eval output: %w", err)
	}

	return data, nil
}

// WriteConsolidatedData writes an entire data map to config.nix with
// the standard file header and section comments. If the file already exists,
// it attempts to preserve any content outside the editable region (e.g. a
// function wrapper) using flakeedit.ReplaceNixEditableAttrset. Falls back
// to a full rewrite if the existing file can't be parsed.
func (s *Store) WriteConsolidatedData(data map[string]any) error {
	nixExpr, err := nixser.SerializeWithSections(data, "  ", SectionHeaders())
	if err != nil {
		return fmt.Errorf("serialize config.nix: %w", err)
	}

	if err := s.paths.EnsureDir(); err != nil {
		return fmt.Errorf("create data directory: %w", err)
	}

	dataPath := s.paths.ConfigFilePath()
	content := ConfigNixHeader + nixExpr + "\n"
	if existing, err := os.ReadFile(dataPath); err == nil && len(existing) > 0 {
		wrapped, wrapErr := flakeedit.ReplaceNixEditableAttrset(existing, nixExpr+"\n")
		if wrapErr == nil {
			content = string(wrapped)
		}
	}
	if err := os.WriteFile(dataPath, []byte(content), 0o644); err != nil {
		return fmt.Errorf("write config.nix: %w", err)
	}

	log.Info().
		Str("path", dataPath).
		Msg("nixdata.Store: wrote config.nix")

	return nil
}

// PatchConsolidatedData sets a single value at a dot-separated path within
// config.nix using source-preserving AST patching. This is the preferred
// mutation path because it keeps user comments and formatting intact.
//
// Path segments are converted from camelCase to kebab-case so that UI panel
// editPaths (e.g. "deployment.fly.organization") map correctly to Nix
// attribute names. Segments immediately after map field names (e.g. the app
// name after "apps.") are preserved verbatim since they're user-defined keys.
//
// Pass a DeleteValue{} to remove the binding at the given path.
// Intermediate attribute sets are created automatically if they do not exist.
func (s *Store) PatchConsolidatedData(path string, value any) error {
	dataPath := s.paths.ConfigFilePath()
	if err := s.paths.EnsureDir(); err != nil {
		return fmt.Errorf("create data directory: %w", err)
	}

	source, err := os.ReadFile(dataPath)
	if err != nil {
		if os.IsNotExist(err) {
			err = s.WriteConsolidatedData(map[string]any{})
			if err != nil {
				return fmt.Errorf("initialize config.nix: %w", err)
			}
			source, err = os.ReadFile(dataPath)
		}
		if err != nil {
			return fmt.Errorf("read config.nix: %w", err)
		}
	}

	parts := NormalizeConfigPathParts(path)
	valueExpr, shouldDelete, err := serializePatchedValue(value)
	if err != nil {
		return err
	}

	var modified []byte
	if shouldDelete {
		modified, err = flakeedit.DeleteNixPath(source, parts)
	} else {
		modified, err = flakeedit.PatchNixPath(source, parts, valueExpr)
	}
	if err != nil {
		return fmt.Errorf("patch config.nix: %w", err)
	}

	formatted := nixser.FormatSource(string(modified), "  ")
	if err := os.WriteFile(dataPath, []byte(formatted), 0o644); err != nil {
		return fmt.Errorf("write config.nix: %w", err)
	}
	return nil
}

// importExpr builds a Nix expression that imports a data file. config.nix may
// be either a plain attrset or a function ({pkgs, lib, ...}: { ... }), so we
// call it with null arguments when it's a function. Passing nulls avoids a
// full flake evaluation — we only need the raw data, not computed values.
func (s *Store) importExpr(dataPath string) string {
	quotedPath := fmt.Sprintf("%q", dataPath)
	return fmt.Sprintf(`
let
  path = %s;
  raw = import path;
  config = if builtins.isFunction raw then raw {
    pkgs = null;
    lib = null;
    inputs = { };
    self = null;
    inherit config;
  } else raw;
in
  config
`, quotedPath)
}

func (s *Store) configEvalExpr() string {
	return s.importExpr(s.paths.ConfigFilePath())
}

// configEntityEvalExpr builds a Nix expression that extracts a single entity
// from config.nix with a safe default. Map entities default to {} so callers
// can always iterate; non-map entities default to null.
func (s *Store) configEntityEvalExpr(entity string) string {
	defaultExpr := "null"
	if IsMapEntity(entity) {
		defaultExpr = "{}"
	}
	return fmt.Sprintf(`
let
  config = %s;
in
  if builtins.hasAttr %q config
  then builtins.getAttr %q config
  else %s
`, s.configEvalExpr(), entity, entity, defaultExpr)
}

// serializePatchedValue converts a Go value to a Nix expression string for
// source-level patching. The returned shouldDelete flag signals that the
// caller should remove the binding entirely (for DeleteValue sentinels)
// rather than writing an expression.
func serializePatchedValue(value any) (string, bool, error) {
	switch v := value.(type) {
	case DeleteValue:
		return "", true, nil
	case RawExpr:
		return string(v), false, nil
	default:
		expr, err := nixser.Serialize(value)
		if err != nil {
			return "", false, fmt.Errorf("serialize patch value: %w", err)
		}
		return expr, false, nil
	}
}

// ReadAppVariableLinks parses raw config.nix source (not evaluated output) to
// extract app/env/envKey -> variable ID mappings. These links are Nix
// expressions like `config.variables.myVar.value` that connect app environment
// variables to centrally-defined variables. They must be extracted from source
// because evaluation resolves the references, losing the link information.
func (s *Store) ReadAppVariableLinks() (map[string]map[string]map[string]string, error) {
	dataPath := s.paths.ConfigFilePath()
	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		return map[string]map[string]map[string]string{}, nil
	}
	source, err := os.ReadFile(dataPath)
	if err != nil {
		return nil, fmt.Errorf("read config.nix: %w", err)
	}
	return flakeedit.ExtractAppVariableLinksFromSource(source)
}

// NormalizeConfigPathParts converts a dotted UI/config path into Nix attribute
// segments with proper casing. Non-map segments are converted from camelCase
// to kebab-case to match Nix conventions. Segments immediately following a
// map field name (e.g. the app name after "apps.") are preserved verbatim
// since they are user-defined keys that must not be transformed.
func NormalizeConfigPathParts(path string) []string {
	parts := SplitConfigPath(path)
	if len(parts) == 0 {
		return nil
	}
	mapFields := MapFieldNames()
	normalized := make([]string, 0, len(parts))
	preserveNext := false
	for _, part := range parts {
		if part == "" {
			continue
		}
		if preserveNext {
			normalized = append(normalized, part)
			preserveNext = false
		} else {
			kebab := CamelToKebab(part)
			normalized = append(normalized, kebab)
			if _, ok := mapFields[kebab]; ok {
				preserveNext = true
			}
		}
	}
	return normalized
}

// DeleteEntity removes the legacy per-entity data file for entity. For
// consolidated configs this is a no-op — use PatchConsolidatedData with
// DeleteValue{} instead. Returns the path that was deleted, or "" if
// nothing was removed.
func (s *Store) DeleteEntity(entity string) (string, error) {
	if err := ValidateEntityName(entity); err != nil {
		return "", err
	}
	if IsExternalEntity(entity) {
		return "", errors.New("external entities are read-only")
	}

	// Only delete legacy per-entity files; consolidated entries are removed
	// by patching config.nix.
	if s.paths.IsUsingConsolidatedConfig(entity) {
		return "", nil
	}

	dataPath := s.paths.EntityPath(entity)
	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		return "", nil
	}

	if err := os.Remove(dataPath); err != nil {
		return "", fmt.Errorf("remove data file: %w", err)
	}

	log.Info().
		Str("entity", entity).
		Str("path", dataPath).
		Msg("nixdata.Store: deleted entity")

	return dataPath, nil
}
