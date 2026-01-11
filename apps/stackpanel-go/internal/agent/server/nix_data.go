package server

import (
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

	// Data is the Go value to serialize to Nix (for writes only).
	// Will be converted to a Nix expression.
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

	dataPath := s.nixDataPath(entity)

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

// nixDataDir returns the path to the data directory.
func (s *Server) nixDataDir() string {
	return filepath.Join(s.config.ProjectRoot, ".stackpanel", "data")
}

// nixDataPath returns the path to a specific data file.
func (s *Server) nixDataPath(entity string) string {
	return filepath.Join(s.nixDataDir(), entity+".nix")
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
