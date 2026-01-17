package server

import (
	"bufio"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
)

// -----------------------------
// Security / CORS helpers
// -----------------------------

// withLogging logs all incoming requests with method, path, and duration
func (s *Server) withLogging(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Wrap response writer to capture status code
		wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next(wrapped, r)

		// Skip logging for health checks to reduce noise
		if r.URL.Path == "/health" {
			return
		}

		duration := time.Since(start)

		log.Debug().
			Str("method", r.Method).
			Str("path", r.URL.Path).
			Int("status", wrapped.statusCode).
			Dur("duration", duration).
			Str("origin", r.Header.Get("Origin")).
			Msg("HTTP request")
	}
}

// responseWriter wraps http.ResponseWriter to capture the status code
// It also implements http.Hijacker to support WebSocket upgrades
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// Hijack implements http.Hijacker to support WebSocket upgrades
func (rw *responseWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	if hijacker, ok := rw.ResponseWriter.(http.Hijacker); ok {
		return hijacker.Hijack()
	}
	return nil, nil, http.ErrNotSupported
}

// Flush implements http.Flusher for SSE support
func (rw *responseWriter) Flush() {
	if flusher, ok := rw.ResponseWriter.(http.Flusher); ok {
		flusher.Flush()
	}
}

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

	// Check JWT token first
	if s.jwtManager.IsValidToken(token) {
		return true
	}

	// Also allow static auth token from config (for CLI/scripts)
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
		// Allow Tailscale domains (*.ts.net) for remote access
		if strings.HasSuffix(host, ".ts.net") {
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
