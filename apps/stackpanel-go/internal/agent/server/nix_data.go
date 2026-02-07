package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	nixser "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
	"github.com/rs/zerolog/log"
)

// nixDataRequest represents a request to read or write a Nix data file.
type nixDataRequest struct {
	// Entity is the name of the data file (without .nix extension).
	// Maps to .stackpanel/data/<entity>.nix
	Entity string `json:"entity"`

	// Key is the specific key to update within the entity (optional).
	// If set, only this key is updated/deleted instead of replacing the whole file.
	Key string `json:"key,omitempty"`

	// Delete indicates this is a key deletion (used with Key).
	Delete bool `json:"delete,omitempty"`

	// Data is the Go value to serialize to Nix (for writes only).
	// Will be converted to a Nix expression.
	// If Key is set, this is the value for that key.
	// If Key is not set, this replaces the entire file content.
	Data any `json:"data,omitempty"`
}

// handleNixData handles CRUD operations on Nix data files in .stackpanel/data/.
// GET: Read and evaluate a data file, returning the JSON result.
// POST: Write a data file by serializing the provided data to Nix.
// DELETE: Remove a data file.
func (s *Server) handleNixData(w http.ResponseWriter, r *http.Request) {
	log.Debug().
		Str("method", r.Method).
		Str("url", r.URL.String()).
		Msg("handleNixData called")

	switch r.Method {
	case http.MethodGet:
		s.handleNixDataRead(w, r)
	case http.MethodPost:
		s.handleNixDataWrite(w, r)
	case http.MethodDelete:
		s.handleNixDataDelete(w, r)
	default:
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// handleNixDataRead reads and evaluates a Nix data file.
// For certain entities (like "variables"), it returns the merged config from
// the evaluated flake, which includes both user-defined and module-contributed values.
func (s *Server) handleNixDataRead(w http.ResponseWriter, r *http.Request) {
	entity := strings.TrimSpace(r.URL.Query().Get("entity"))
	if entity == "" {
		s.writeAPIError(w, http.StatusBadRequest, "entity is required")
		return
	}

	if err := validateEntityName(entity); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	// For certain entities, return the merged config from the evaluated flake.
	// This includes both user-defined values and module-contributed values.
	if isEvaluatedEntity(entity) {
		s.handleNixDataReadEvaluated(w, r, entity)
		return
	}

	dataPath := s.nixDataPath(entity)
	if isExternalEntity(entity) {
		dataPath = s.nixExternalDataPath(entity)
	}

	// Check if file exists
	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"entity": entity,
			"exists": false,
			"data":   nil,
		})
		return
	}

	// Evaluate the Nix file to get JSON
	// Use --impure to allow reading files and environment variables
	args := []string{"eval", "--impure", "--json", "-f", dataPath}
	res, err := s.exec.RunNix(args...)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if res.ExitCode != 0 {
		s.writeAPIError(w, http.StatusBadRequest, strings.TrimSpace(res.Stderr))
		return
	}

	// Parse the JSON output
	var data any
	if err := json.Unmarshal([]byte(res.Stdout), &data); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse nix eval output")
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"entity": entity,
		"exists": true,
		"data":   data,
	})
}

// isEvaluatedEntity returns true if the entity should be read from the
// evaluated flake config (which includes module-contributed values) rather
// than just the data file.
func isEvaluatedEntity(entity string) bool {
	// These entities include values contributed by Nix modules
	// (e.g., app ports, service ports) in addition to user-defined values.
	evaluatedEntities := map[string]bool{
		"variables": true,
	}
	return evaluatedEntities[entity]
}

// handleNixDataReadEvaluated reads an entity from the evaluated flake config.
// This is used for entities like "variables" where the final value includes
// both user-defined data and module-contributed values.
func (s *Server) handleNixDataReadEvaluated(w http.ResponseWriter, r *http.Request, entity string) {
	ctx := r.Context()

	// Try to get from FlakeWatcher (has caching and file watching)
	if s.flakeWatcher != nil {
		config, err := s.flakeWatcher.GetConfig(ctx)
		if err == nil {
			// Extract the entity from the config
			if data, ok := config[entity]; ok {
				s.writeAPI(w, http.StatusOK, map[string]any{
					"entity": entity,
					"exists": true,
					"data":   data,
					"source": "evaluated",
				})
				return
			}
			// Entity not in config - return empty
			s.writeAPI(w, http.StatusOK, map[string]any{
				"entity": entity,
				"exists": false,
				"data":   nil,
				"source": "evaluated",
			})
			return
		}
		log.Debug().Err(err).Str("entity", entity).Msg("FlakeWatcher failed, falling back to direct eval")
	}

	// Fallback: evaluate config directly
	config, err := s.evaluateConfig()
	if err != nil {
		// If config evaluation fails, fall back to data file only
		log.Warn().Err(err).Str("entity", entity).Msg("Config evaluation failed, falling back to data file")
		s.handleNixDataReadFromFile(w, entity)
		return
	}

	// Extract the entity from the config
	if data, ok := config[entity]; ok {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"entity": entity,
			"exists": true,
			"data":   data,
			"source": "evaluated",
		})
		return
	}

	// Entity not in config - return empty
	s.writeAPI(w, http.StatusOK, map[string]any{
		"entity": entity,
		"exists": false,
		"data":   nil,
		"source": "evaluated",
	})
}

// handleNixDataReadFromFile reads an entity directly from the data file.
// This is the fallback when config evaluation fails.
func (s *Server) handleNixDataReadFromFile(w http.ResponseWriter, entity string) {
	dataPath := s.nixDataPath(entity)
	if isExternalEntity(entity) {
		dataPath = s.nixExternalDataPath(entity)
	}

	// Check if file exists
	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"entity": entity,
			"exists": false,
			"data":   nil,
		})
		return
	}

	// Evaluate the Nix file to get JSON
	args := []string{"eval", "--impure", "--json", "-f", dataPath}
	res, err := s.exec.RunNix(args...)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if res.ExitCode != 0 {
		s.writeAPIError(w, http.StatusBadRequest, strings.TrimSpace(res.Stderr))
		return
	}

	// Parse the JSON output
	var data any
	if err := json.Unmarshal([]byte(res.Stdout), &data); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse nix eval output")
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"entity": entity,
		"exists": true,
		"data":   data,
	})
}

// handleNixDataWrite writes data to a Nix data file.
func (s *Server) handleNixDataWrite(w http.ResponseWriter, r *http.Request) {
	log.Debug().Msg("handleNixDataWrite: parsing request body")

	var req nixDataRequest
	if err := s.readJSON(r.Body, &req); err != nil {
		log.Error().Err(err).Msg("handleNixDataWrite: failed to parse JSON")
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	log.Debug().
		Str("entity", req.Entity).
		Interface("data", req.Data).
		Msg("handleNixDataWrite: received request")

	req.Entity = strings.TrimSpace(req.Entity)
	if req.Entity == "" {
		log.Error().Msg("handleNixDataWrite: entity is required")
		s.writeAPIError(w, http.StatusBadRequest, "entity is required")
		return
	}

	if err := validateEntityName(req.Entity); err != nil {
		log.Error().Err(err).Str("entity", req.Entity).Msg("handleNixDataWrite: invalid entity name")
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	if isExternalEntity(req.Entity) {
		s.writeAPIError(w, http.StatusBadRequest, "external entities are read-only")
		return
	}

	// Handle key-level updates
	if req.Key != "" {
		s.handleKeyLevelWrite(w, req)
		return
	}

	if req.Data == nil {
		log.Error().Msg("handleNixDataWrite: data is required")
		s.writeAPIError(w, http.StatusBadRequest, "data is required")
		return
	}

	// Serialize the data to Nix
	nixExpr, err := nixser.SerializeIndented(req.Data, "  ")
	if err != nil {
		log.Error().Err(err).Msg("handleNixDataWrite: failed to serialize to Nix")
		s.writeAPIError(w, http.StatusBadRequest, "failed to serialize data to Nix: "+err.Error())
		return
	}

	log.Debug().
		Str("entity", req.Entity).
		Str("nixExpr", nixExpr).
		Msg("handleNixDataWrite: serialized to Nix")

	// Ensure data directory exists
	dataDir := s.nixDataDir()
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		log.Error().Err(err).Str("dataDir", dataDir).Msg("handleNixDataWrite: failed to create data directory")
		s.writeAPIError(w, http.StatusInternalServerError, "failed to create data directory: "+err.Error())
		return
	}

	// Write the file
	dataPath := s.nixDataPath(req.Entity)
	log.Debug().Str("path", dataPath).Msg("handleNixDataWrite: writing file")

	if err := os.WriteFile(dataPath, []byte(nixExpr+"\n"), 0o644); err != nil {
		log.Error().Err(err).Str("path", dataPath).Msg("handleNixDataWrite: failed to write file")
		s.writeAPIError(w, http.StatusInternalServerError, "failed to write data file: "+err.Error())
		return
	}

	log.Info().
		Str("entity", req.Entity).
		Str("path", dataPath).
		Msg("handleNixDataWrite: successfully wrote data file")

	s.writeAPI(w, http.StatusOK, map[string]any{
		"entity":  req.Entity,
		"path":    dataPath,
		"success": true,
	})
}

// handleNixDataDelete removes a Nix data file.
func (s *Server) handleNixDataDelete(w http.ResponseWriter, r *http.Request) {
	entity := strings.TrimSpace(r.URL.Query().Get("entity"))
	if entity == "" {
		s.writeAPIError(w, http.StatusBadRequest, "entity is required")
		return
	}

	if err := validateEntityName(entity); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	if isExternalEntity(entity) {
		s.writeAPIError(w, http.StatusBadRequest, "external entities are read-only")
		return
	}

	dataPath := s.nixDataPath(entity)

	// Check if file exists
	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"entity":  entity,
			"deleted": false,
			"reason":  "file does not exist",
		})
		return
	}

	if err := os.Remove(dataPath); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to delete file: "+err.Error())
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"entity":  entity,
		"deleted": true,
	})
}

// handleNixDataList lists all Nix data files.
func (s *Server) handleNixDataList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	dataDir := s.nixDataDir()
	entries, err := os.ReadDir(dataDir)
	if err != nil {
		if os.IsNotExist(err) {
			s.writeAPI(w, http.StatusOK, map[string]any{
				"entities": []string{},
			})
			return
		}
		s.writeAPIError(w, http.StatusInternalServerError, "failed to read data directory: "+err.Error())
		return
	}

	var entities []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if strings.HasSuffix(name, ".nix") {
			entities = append(entities, strings.TrimSuffix(name, ".nix"))
		}
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"entities": entities,
	})
}

// nixDataDir returns the path to the .stackpanel directory.
func (s *Server) nixDataDir() string {
	return filepath.Join(s.config.ProjectRoot, ".stackpanel")
}

// nixDataFilePath returns the path to the single consolidated config.nix file.
// This is the single source of truth for all stackpanel configuration.
func (s *Server) nixDataFilePath() string {
	return filepath.Join(s.nixDataDir(), "config.nix")
}

// nixLegacyDataDir returns the path to the legacy data/ directory (for migration).
func (s *Server) nixLegacyDataDir() string {
	return filepath.Join(s.nixDataDir(), "data")
}

func (s *Server) nixExternalDataDir() string {
	return filepath.Join(s.nixDataDir(), "external")
}

// nixDataPath returns the path to a specific data file.
// For backwards compatibility, this checks if the legacy data/ directory exists.
// TODO: Remove after migration to single data.nix file.
func (s *Server) nixDataPath(entity string) string {
	legacyPath := filepath.Join(s.nixLegacyDataDir(), entity+".nix")
	if _, err := os.Stat(legacyPath); err == nil {
		return legacyPath
	}
	// Use the single data.nix file (entity is a key within it)
	return s.nixDataFilePath()
}

// isUsingConsolidatedConfig checks if an entity is stored in the consolidated config.nix
// rather than a legacy individual file like data/apps.nix.
func (s *Server) isUsingConsolidatedConfig(entity string) bool {
	legacyPath := filepath.Join(s.nixLegacyDataDir(), entity+".nix")
	_, err := os.Stat(legacyPath)
	return os.IsNotExist(err)
}

func (s *Server) nixExternalDataPath(entity string) string {
	name := strings.TrimPrefix(entity, "external-")
	return filepath.Join(s.nixExternalDataDir(), name+".nix")
}

// validateEntityName checks if an entity name is valid.
// Entity names must be alphanumeric with optional hyphens/underscores.
func validateEntityName(name string) error {
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

func isExternalEntity(name string) bool {
	return strings.HasPrefix(name, "external-")
}

// =============================================================================
// Connect Handler Helpers
// =============================================================================
// These methods are called by the generated Connect handlers in connect_entities_gen.go

// readNixEntityJSON reads a Nix data entity and returns its JSON representation.
// Used by generated Connect handlers for Get* methods.
// Note: Nix uses kebab-case for attribute names, but protojson expects camelCase.
// This function automatically transforms keys from kebab-case to camelCase.
func (s *Server) readNixEntityJSON(entity string) ([]byte, error) {
	if err := validateEntityName(entity); err != nil {
		return nil, err
	}

	// For evaluated entities (like variables), use the merged config first.
	if isEvaluatedEntity(entity) {
		if data, ok, err := s.readEvaluatedEntityData(entity); err == nil {
			if !ok {
				// Not present in evaluated config; return empty map/object
				if isMapEntity(entity) {
					return transformNixJSONToCamelCase(
						mustMarshalJSON(map[string]any{entity: map[string]any{}}),
						mapFieldNames(),
					)
				}
				return transformNixJSONToCamelCase(mustMarshalJSON(map[string]any{}), mapFieldNames())
			}

			wrapped := data
			if isMapEntity(entity) {
				wrapped = map[string]any{entity: data}
			}
			return transformNixJSONToCamelCase(mustMarshalJSON(wrapped), mapFieldNames())
		}
	}

	dataPath := s.nixDataPath(entity)
	isConsolidated := s.isUsingConsolidatedConfig(entity)
	if isExternalEntity(entity) {
		dataPath = s.nixExternalDataPath(entity)
		isConsolidated = false
	}

	// Check if file exists
	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		// Return empty JSON object for non-existent entities
		return []byte("{}"), nil
	}

	// Evaluate the Nix file to get JSON
	// For consolidated config.nix, extract just the entity attribute
	args := []string{"eval", "--impure", "--json", "-f", dataPath}
	if isConsolidated {
		args = append(args, entity)
	}
	res, err := s.exec.RunNix(args...)
	if err != nil {
		return nil, err
	}
	if res.ExitCode != 0 {
		return nil, errors.New(strings.TrimSpace(res.Stderr))
	}

	// Parse JSON into generic structure
	var parsed any
	if err := json.Unmarshal([]byte(res.Stdout), &parsed); err != nil {
		return nil, err
	}

	// Wrap map entities to match proto envelope (e.g., Apps -> {apps: {...}})
	if isMapEntity(entity) {
		parsed = map[string]any{entity: parsed}
	}

	// Transform kebab-case keys to camelCase for protojson compatibility
	return transformNixJSONToCamelCase(mustMarshalJSON(parsed), mapFieldNames())
}

// writeNixEntityJSON writes JSON data to a Nix data entity file.
// Used by generated Connect handlers for Set* methods.
// Note: protojson uses camelCase for attribute names, but Nix expects kebab-case.
// This function automatically transforms keys from camelCase to kebab-case.
func (s *Server) writeNixEntityJSON(entity string, data []byte) error {
	if err := validateEntityName(entity); err != nil {
		return err
	}

	if isExternalEntity(entity) {
		return errors.New("external entities are read-only")
	}

	// Transform camelCase keys to kebab-case for Nix compatibility
	transformedData, err := transformCamelCaseToNixJSON(data, mapFieldNames())
	if err != nil {
		return err
	}

	// Parse JSON to Go value
	var value any
	if err := json.Unmarshal(transformedData, &value); err != nil {
		return err
	}

	// Unwrap map entities to match Nix data files (store raw map)
	if isMapEntity(entity) {
		if obj, ok := value.(map[string]any); ok {
			if inner, ok := obj[entity]; ok {
				value = inner
			}
		}
	}

	// Serialize to Nix
	nixExpr, err := nixser.SerializeIndented(value, "  ")
	if err != nil {
		return err
	}

	// Ensure data directory exists
	dataDir := s.nixDataDir()
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return err
	}

	// Write the file
	dataPath := s.nixDataPath(entity)
	if err := os.WriteFile(dataPath, []byte(nixExpr+"\n"), 0o644); err != nil {
		return err
	}

	log.Info().
		Str("entity", entity).
		Str("path", dataPath).
		Msg("writeNixEntityJSON: successfully wrote data file")

	return nil
}

func isMapEntity(entity string) bool {
	switch entity {
	case "apps", "variables", "users":
		return true
	default:
		return false
	}
}

// readEvaluatedEntityData reads an entity from the evaluated config, using
// flake watcher when available and falling back to direct evaluation.
func (s *Server) readEvaluatedEntityData(entity string) (any, bool, error) {
	ctx := context.Background()

	if s.flakeWatcher != nil {
		config, err := s.flakeWatcher.GetConfig(ctx)
		if err == nil {
			data, ok := config[entity]
			return data, ok, nil
		}
	}

	config, err := s.evaluateConfig()
	if err != nil {
		return nil, false, err
	}

	data, ok := config[entity]
	return data, ok, nil
}

func mapFieldNames() map[string]struct{} {
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

func mustMarshalJSON(value any) []byte {
	data, err := json.Marshal(value)
	if err != nil {
		return []byte("{}")
	}
	return data
}

// handleKeyLevelWrite handles updating or deleting a single key in a data file.
// This reads the existing file, updates/deletes the key, and writes back.
func (s *Server) handleKeyLevelWrite(w http.ResponseWriter, req nixDataRequest) {
	log.Debug().
		Str("entity", req.Entity).
		Str("key", req.Key).
		Bool("delete", req.Delete).
		Msg("handleKeyLevelWrite: processing key-level update")

	// Read existing data from the data file (not evaluated config)
	dataPath := s.nixDataPath(req.Entity)
	existing := make(map[string]any)

	// Try to read existing file
	if _, err := os.Stat(dataPath); err == nil {
		// File exists, read it
		data, err := s.readNixDataFile(req.Entity)
		if err != nil {
			log.Error().Err(err).Str("entity", req.Entity).Msg("handleKeyLevelWrite: failed to read existing data")
			s.writeAPIError(w, http.StatusInternalServerError, "failed to read existing data: "+err.Error())
			return
		}
		if dataMap, ok := data.(map[string]any); ok {
			existing = dataMap
		}
	}

	// Apply the update
	if req.Delete {
		delete(existing, req.Key)
		log.Debug().Str("key", req.Key).Msg("handleKeyLevelWrite: deleted key")
	} else {
		if req.Data == nil {
			s.writeAPIError(w, http.StatusBadRequest, "data is required for key update")
			return
		}
		existing[req.Key] = req.Data
		log.Debug().Str("key", req.Key).Msg("handleKeyLevelWrite: set key")
	}

	// Serialize and write
	nixExpr, err := nixser.SerializeIndented(existing, "  ")
	if err != nil {
		log.Error().Err(err).Msg("handleKeyLevelWrite: failed to serialize to Nix")
		s.writeAPIError(w, http.StatusBadRequest, "failed to serialize data to Nix: "+err.Error())
		return
	}

	// Ensure data directory exists
	dataDir := s.nixDataDir()
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		log.Error().Err(err).Str("dataDir", dataDir).Msg("handleKeyLevelWrite: failed to create data directory")
		s.writeAPIError(w, http.StatusInternalServerError, "failed to create data directory: "+err.Error())
		return
	}

	if err := os.WriteFile(dataPath, []byte(nixExpr+"\n"), 0o644); err != nil {
		log.Error().Err(err).Str("path", dataPath).Msg("handleKeyLevelWrite: failed to write file")
		s.writeAPIError(w, http.StatusInternalServerError, "failed to write data file: "+err.Error())
		return
	}

	log.Info().
		Str("entity", req.Entity).
		Str("key", req.Key).
		Bool("delete", req.Delete).
		Str("path", dataPath).
		Msg("handleKeyLevelWrite: successfully updated key")

	s.writeAPI(w, http.StatusOK, map[string]any{
		"entity":  req.Entity,
		"key":     req.Key,
		"path":    dataPath,
		"success": true,
	})
}

// readNixDataFile reads and evaluates a Nix data file, returning the Go value.
func (s *Server) readNixDataFile(entity string) (any, error) {
	dataPath := s.nixDataPath(entity)

	// Use nix eval to evaluate the file
	args := []string{"eval", "--impure", "--json", "--expr", "builtins.fromJSON (builtins.toJSON (import " + dataPath + "))"}
	res, err := s.exec.RunNix(args...)
	if err != nil {
		return nil, err
	}

	if res.ExitCode != 0 {
		return nil, errors.New("nix eval failed: " + res.Stderr)
	}

	var data any
	if err := json.Unmarshal([]byte(res.Stdout), &data); err != nil {
		return nil, errors.New("failed to parse JSON: " + err.Error())
	}

	return data, nil
}

// =============================================================================
// Consolidated config.nix Support
// =============================================================================

// configNixHeader is the file header added to config.nix when writing.
const configNixHeader = `# ==============================================================================
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

// readConsolidatedData reads the entire config.nix file as a map.
func (s *Server) readConsolidatedData() (map[string]any, error) {
	dataPath := s.nixDataFilePath()

	// Check if file exists
	if _, err := os.Stat(dataPath); os.IsNotExist(err) {
		return make(map[string]any), nil
	}

	// Use nix eval to evaluate the file
	args := []string{"eval", "--impure", "--json", "-f", dataPath}
	res, err := s.exec.RunNix(args...)
	if err != nil {
		return nil, err
	}

	if res.ExitCode != 0 {
		return nil, errors.New("nix eval failed: " + res.Stderr)
	}

	var data map[string]any
	if err := json.Unmarshal([]byte(res.Stdout), &data); err != nil {
		return nil, errors.New("failed to parse JSON: " + err.Error())
	}

	return data, nil
}

// writeConsolidatedData writes the entire data map to config.nix.
func (s *Server) writeConsolidatedData(data map[string]any) error {
	// Serialize to Nix with section comments
	nixExpr, err := nixser.SerializeWithSections(data, "  ", getSectionHeaders())
	if err != nil {
		return err
	}

	// Ensure .stackpanel directory exists
	dataDir := s.nixDataDir()
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return err
	}

	// Write the file with header
	dataPath := s.nixDataFilePath()
	content := configNixHeader + nixExpr + "\n"
	if err := os.WriteFile(dataPath, []byte(content), 0o644); err != nil {
		return err
	}

	log.Info().
		Str("path", dataPath).
		Msg("writeConsolidatedData: successfully wrote config.nix")

	return nil
}

// getSectionHeaders returns the section header comments for top-level config keys.
func getSectionHeaders() map[string]string {
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

// patchConsolidatedData patches a value at a nested path within config.nix.
// The path is dot-separated and uses camelCase (converted to kebab-case for Nix).
// Example: "deployment.fly.organization" -> config.deployment.fly.organization
func (s *Server) patchConsolidatedData(path string, value any) error {
	// Read existing data
	data, err := s.readConsolidatedData()
	if err != nil {
		return err
	}

	// Navigate and set the value
	pathParts := strings.Split(path, ".")
	target := data

	for i, part := range pathParts {
		kebabPart := camelToKebab(part)

		if i == len(pathParts)-1 {
			// Last segment: set the value
			target[kebabPart] = value
		} else {
			// Intermediate segment: navigate deeper
			child, ok := target[kebabPart]
			if !ok {
				// Create intermediate map
				target[kebabPart] = make(map[string]any)
				child = target[kebabPart]
			}
			childMap, ok := child.(map[string]any)
			if !ok {
				return errors.New("path segment is not a map: " + part)
			}
			target = childMap
		}
	}

	// Write back
	return s.writeConsolidatedData(data)
}

// parseConfigPath parses a configPath like "stackpanel.deployment.fly.organization"
// and returns the path within config.nix (without the "stackpanel." prefix).
func parseConfigPath(configPath string) string {
	// Remove "stackpanel." prefix if present
	path := strings.TrimPrefix(configPath, "stackpanel.")
	return path
}
