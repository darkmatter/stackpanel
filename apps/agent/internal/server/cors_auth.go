package server

import (
	"net/http"
	"net/url"
	"strings"
)

// -----------------------------
// Security / CORS helpers
// -----------------------------

func (s *Server) withCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && s.isOriginAllowed(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "content-type, authorization, x-stackpanel-token")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			// Private Network Access (PNA) preflight support (Chrome)
			w.Header().Set("Access-Control-Allow-Private-Network", "true")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next(w, r)
	}
}

func (s *Server) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && !s.isOriginAllowed(origin) {
			s.writeAPIError(w, http.StatusForbidden, "origin not allowed")
			return
		}

		if !s.hasValidToken(r) {
			s.writeAPIError(w, http.StatusUnauthorized, "missing or invalid token")
			return
		}

		next(w, r)
	}
}

func (s *Server) hasValidToken(r *http.Request) bool {
	if token := strings.TrimSpace(r.Header.Get("X-Stackpanel-Token")); token != "" {
		return s.isValidToken(token)
	}

	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(auth), "bearer ") {
		return s.isValidToken(strings.TrimSpace(auth[7:]))
	}

	// Browser WebSocket connections can't set custom headers, so we also allow
	// providing the token via the query string, e.g. /ws?token=...
	if token := strings.TrimSpace(r.URL.Query().Get("token")); token != "" {
		return s.isValidToken(token)
	}

	return false
}

func (s *Server) isValidToken(token string) bool {
	if token == "" {
		return false
	}
	if token == s.pairToken {
		return true
	}
	if s.config.AuthToken != "" && token == s.config.AuthToken {
		return true
	}
	return false
}

func (s *Server) isOriginAllowed(origin string) bool {
	// Always allow loopback + *.localhost (Caddy/dev domains).
	if u, err := url.Parse(origin); err == nil {
		host := strings.ToLower(u.Hostname())
		if host == "localhost" || host == "127.0.0.1" || host == "::1" || strings.HasSuffix(host, ".localhost") {
			return true
		}
	}

	// If configured, enforce allowlist.
	if len(s.config.AllowedOrigins) > 0 {
		for _, allowed := range s.config.AllowedOrigins {
			if origin == allowed {
				return true
			}
		}
		return false
	}

	// Default allowlist for hosted UI.
	return origin == "https://stackpanel.com" || origin == "https://stackpanel.dev"
}
