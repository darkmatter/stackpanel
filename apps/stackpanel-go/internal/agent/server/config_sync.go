package server

import (
	"net/http"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/configsync"
	"github.com/rs/zerolog/log"
)

// handleConfigCheck checks whether config.nix has entries that should be in data files.
// GET /api/config/check
func (s *Server) handleConfigCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	log.Debug().Msg("handleConfigCheck called")

	result, err := configsync.Check(s.config.ProjectRoot)
	if err != nil {
		log.Error().Err(err).Msg("Config check failed")
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	s.writeAPI(w, http.StatusOK, result)
}

// handleConfigSync migrates config.nix entries to data files.
// POST /api/config/sync
func (s *Server) handleConfigSync(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	log.Debug().Msg("handleConfigSync called")

	result, err := configsync.Sync(s.config.ProjectRoot)
	if err != nil {
		log.Error().Err(err).Msg("Config sync failed")
		s.writeAPIError(w, http.StatusInternalServerError, err.Error())
		return
	}

	s.writeAPI(w, http.StatusOK, result)
}
