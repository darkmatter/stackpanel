// nix_data.go provides CRUD operations for Nix data files in .stack/.
//
// Data entities are either standalone files (.stack/<entity>.nix or .stack/data/<entity>.nix)
// or keys within the consolidated .stack/config.nix. Some entities like "variables"
// are "evaluated" — their final value merges user data with Nix module contributions,
// so reads go through the flake evaluation pipeline rather than just the raw file.
//
// External entities (.stack/data/external/*.nix) are read-only since they're
// auto-synced from external sources like GitHub collaborators.
package server

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/rs/zerolog/log"
)

// nixDataRequest represents a request to read or write a Nix data file.
type nixDataRequest struct {
	// Entity is the name of the data file (without .nix extension).
	// Maps to .stack/data/<entity>.nix or a key in .stack/config.nix.
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

// =============================================================================
// HTTP Handlers
// =============================================================================

// handleNixData handles CRUD operations on Nix data files in .stack/.
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

	if err := nixdata.ValidateEntityName(entity); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	// For certain entities, return the merged config from the evaluated flake.
	// This includes both user-defined values and module-contributed values.
	if nixdata.IsEvaluatedEntity(entity) {
		s.handleNixDataReadEvaluated(w, r, entity)
		return
	}

	data, err := s.store.ReadEntity(entity)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if data == nil {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"entity": entity,
			"exists": false,
			"data":   nil,
		})
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"entity": entity,
		"exists": true,
		"data":   data,
	})
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
	data, err := s.store.ReadEntity(entity)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if data == nil {
		s.writeAPI(w, http.StatusOK, map[string]any{
			"entity": entity,
			"exists": false,
			"data":   nil,
		})
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

	if err := nixdata.ValidateEntityName(req.Entity); err != nil {
		log.Error().Err(err).Str("entity", req.Entity).Msg("handleNixDataWrite: invalid entity name")
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	if nixdata.IsExternalEntity(req.Entity) {
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

	dataPath, err := s.store.WriteEntity(req.Entity, req.Data)
	if err != nil {
		log.Error().Err(err).Str("entity", req.Entity).Msg("handleNixDataWrite: failed to write entity")
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

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

	if err := nixdata.ValidateEntityName(entity); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	if nixdata.IsExternalEntity(entity) {
		s.writeAPIError(w, http.StatusBadRequest, "external entities are read-only")
		return
	}

	path, err := s.store.DeleteEntity(entity)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if path == "" {
		// Nothing was deleted — entity lives in consolidated config or doesn't exist.
		s.writeAPI(w, http.StatusOK, map[string]any{
			"entity":  entity,
			"exists":  false,
			"deleted": false,
		})
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"entity":  entity,
		"deleted": true,
		"path":    path,
		"success": true,
	})
}

// handleNixDataList lists all available data entities.
func (s *Server) handleNixDataList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	paths := s.store.Paths()
	var entities []string

	// Read .stack/ directory (consolidated config files)
	seen := map[string]struct{}{}
	if entries, err := os.ReadDir(paths.Dir()); err == nil {
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".nix") {
				continue
			}
			name := strings.TrimSuffix(entry.Name(), ".nix")
			if name == "config" {
				continue
			}
			if _, ok := seen[name]; ok {
				continue
			}
			seen[name] = struct{}{}
			entities = append(entities, name)
		}
	} else if !os.IsNotExist(err) {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to read data directory: "+err.Error())
		return
	}

	// Read legacy .stack/data/ directory
	if entries, err := os.ReadDir(paths.LegacyDataDir()); err == nil {
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".nix") {
				continue
			}
			name := strings.TrimSuffix(entry.Name(), ".nix")
			if nixdata.PrefersConsolidatedConfig(name) {
				continue
			}
			if _, ok := seen[name]; ok {
				continue
			}
			seen[name] = struct{}{}
			entities = append(entities, name)
		}
	}

	// Read external entities from data/ directory
	if entries, err := os.ReadDir(paths.ExternalDataDir()); err == nil {
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".nix") {
				continue
			}
			name := "external-" + strings.TrimSuffix(entry.Name(), ".nix")
			if _, ok := seen[name]; ok {
				continue
			}
			seen[name] = struct{}{}
			entities = append(entities, name)
		}
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"entities": entities,
	})
}

// handleAppVariableLinks returns app/env/envKey -> variable ID link mappings
// parsed from raw app config sources such as config.nix and config.apps.nix.
func (s *Server) handleAppVariableLinks(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if s.store == nil {
		s.writeAPIError(w, http.StatusPreconditionRequired, "no project open")
		return
	}
	links, err := s.store.ReadAppVariableLinks()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}
	s.writeAPI(w, http.StatusOK, map[string]any{
		"links": links,
	})
}

// handleKeyLevelWrite handles updating or deleting a single key in a map entity.
func (s *Server) handleKeyLevelWrite(w http.ResponseWriter, req nixDataRequest) {
	log.Debug().
		Str("entity", req.Entity).
		Str("key", req.Key).
		Bool("delete", req.Delete).
		Msg("handleKeyLevelWrite: processing key-level update")

	var dataPath string
	var err error

	if req.Delete {
		dataPath, err = s.store.DeleteKey(req.Entity, req.Key)
	} else {
		if req.Data == nil {
			s.writeAPIError(w, http.StatusBadRequest, "data is required for key update")
			return
		}
		dataPath, err = s.store.SetKey(req.Entity, req.Key, req.Data)
	}

	if err != nil {
		log.Error().Err(err).
			Str("entity", req.Entity).
			Str("key", req.Key).
			Msg("handleKeyLevelWrite: failed")
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
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

// =============================================================================
// Server Methods (thin wrappers for callers in other server files)
//
// These keep the existing method signatures so that connect_entities_gen.go,
// connect_patch.go, agenix.go, etc. continue to compile without changes.
// The real work is done by s.store (pkg/nixdata).
// =============================================================================

// readNixEntityJSON reads a Nix data entity and returns its JSON representation.
// Used by generated Connect handlers for Get* methods.
//
// For evaluated entities (like "variables") the merged flake output is tried
// first via the FlakeWatcher / evaluateConfig (server-specific), falling back
// to the raw data file through the store.
func (s *Server) readNixEntityJSON(entity string) ([]byte, error) {
	if err := nixdata.ValidateEntityName(entity); err != nil {
		return nil, err
	}

	// For evaluated entities, use the merged config from the flake first.
	if nixdata.IsEvaluatedEntity(entity) {
		if data, ok, err := s.readEvaluatedEntityData(entity); err == nil {
			if !ok {
				// Entity not present in evaluated config — return empty envelope.
				if nixdata.IsMapEntity(entity) {
					return nixdata.NixJSONToCamelCase(
						mustMarshalJSON(map[string]any{entity: map[string]any{}}),
						nixdata.MapFieldNames(),
					)
				}
				return nixdata.NixJSONToCamelCase(mustMarshalJSON(map[string]any{}), nixdata.MapFieldNames())
			}

			wrapped := data
			if nixdata.IsMapEntity(entity) {
				wrapped = map[string]any{entity: data}
			}
			return nixdata.NixJSONToCamelCase(mustMarshalJSON(wrapped), nixdata.MapFieldNames())
		}
		// Evaluated read failed — fall through to file-based read.
	}

	// Delegate the file-based read to the shared store.
	return s.store.ReadEntityJSON(entity)
}

// writeNixEntityJSON writes camelCase JSON data to a Nix entity file.
// Used by generated Connect handlers for Set* methods.
func (s *Server) writeNixEntityJSON(entity string, data []byte) error {
	_, err := s.store.WriteEntityJSON(entity, data)
	return err
}

// readConsolidatedData reads the entire .stack/config.nix as a map.
func (s *Server) readConsolidatedData() (map[string]any, error) {
	return s.store.ReadConsolidatedData()
}

// writeConsolidatedData writes an entire data map to config.nix.
func (s *Server) writeConsolidatedData(data map[string]any) error {
	return s.store.WriteConsolidatedData(data)
}

// patchConsolidatedData patches a value at a nested path within config.nix.
func (s *Server) patchConsolidatedData(path string, value any) error {
	return s.store.PatchConsolidatedData(path, value)
}

// nixDataFilePath returns the path to the consolidated config.nix file.
// Used by connect_patch.go for logging.
func (s *Server) nixDataFilePath() string {
	return s.store.Paths().ConfigFilePath()
}

// readEvaluatedEntityData reads an entity from the evaluated config, using
// the FlakeWatcher when available and falling back to direct evaluation.
// This is server-specific because it depends on the FlakeWatcher and
// evaluateConfig, which are not part of the shared nixdata package.
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

// =============================================================================
// Compatibility Aliases
//
// Package-level functions that forward to pkg/nixdata. These exist so that
// other files in the server package (connect_patch.go, etc.) continue to
// compile without modification. New code should use nixdata.* directly.
// =============================================================================

func validateEntityName(name string) error     { return nixdata.ValidateEntityName(name) }
func isExternalEntity(name string) bool        { return nixdata.IsExternalEntity(name) }
func isMapEntity(entity string) bool           { return nixdata.IsMapEntity(entity) }
func isEvaluatedEntity(entity string) bool     { return nixdata.IsEvaluatedEntity(entity) }
func mapFieldNames() map[string]struct{}       { return nixdata.MapFieldNames() }
func parseConfigPath(configPath string) string { return nixdata.ParseConfigPath(configPath) }

// =============================================================================
// Local Helpers
// =============================================================================

func mustMarshalJSON(value any) []byte {
	data, err := json.Marshal(value)
	if err != nil {
		return []byte("{}")
	}
	return data
}
