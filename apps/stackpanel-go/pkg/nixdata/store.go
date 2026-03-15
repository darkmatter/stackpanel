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

// RawExpr is a raw Nix expression that should be written without quoting.
type RawExpr string

// DeleteValue removes the target binding when patching config.nix.
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
// value (typically map[string]any or []any). For external entities the
// external data path is used; for consolidated configs only the entity's
// attribute is extracted.
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
// to match the proto message shape.
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

// ReadRawNixFile evaluates a Nix data file using a round-trip through
// builtins.toJSON/builtins.fromJSON. This is used for key-level updates
// where the raw file value (not the merged flake output) is needed.
func (s *Store) ReadRawNixFile(entity string) (any, error) {
	dataPath := s.paths.EntityPath(entity)
	expr := "builtins.fromJSON (builtins.toJSON (" + s.importExpr(dataPath) + "))"

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
// entity's data file. The data value should already have kebab-case keys
// if it came from the HTTP layer; no key transformation is performed here.
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
// transforms keys to kebab-case, unwraps map entity envelopes, serialises
// to Nix, and writes the result.
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

// SetKey performs a key-level upsert on a map entity. It reads the current
// file, sets key to value, and writes the result back. Only the targeted
// key is modified; all sibling keys are preserved.
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

	existing, err := s.readExistingMap(entity)
	if err != nil {
		return "", err
	}

	existing[key] = value

	return s.writeMap(entity, existing)
}

// DeleteKey removes a single key from a map entity. It is a no-op if the
// key does not exist.
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
// returns its top-level attributes as a map.
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

// WriteConsolidatedData writes an entire data map to config.nix with the
// standard file header and section comments.
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
// config.nix. Path segments are converted from camelCase to kebab-case so
// that UI panel editPaths (e.g. "deployment.fly.organization") map
// correctly to Nix attribute names.
//
// Intermediate maps are created automatically if they do not exist.
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

// ReadAppVariableLinks returns app/env/envKey -> variable ID mappings parsed
// from raw config.nix source.
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
// segments while preserving user-defined keys under map fields like apps,
// environments, env, and variables.
func NormalizeConfigPathParts(path string) []string {
	parts := strings.Split(path, ".")
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

// DeleteEntity removes the data file for entity. For consolidated configs
// this is a no-op (the entity key must be removed via PatchConsolidatedData
// instead). Returns the path that was deleted, or "" if nothing was removed.
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
