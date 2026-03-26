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

// withLogging wraps a handler to log method, path, status, and duration.
// Health checks are excluded to avoid log spam from the UI's polling.
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

// responseWriter wraps http.ResponseWriter to capture the status code for logging.
// It also implements Hijacker (WebSocket upgrades) and Flusher (SSE streaming).
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

// withCORS adds CORS headers for allowed origins. This is required because the
// web UI may be served from a different origin (e.g., stackpanel.com or a Caddy
// dev domain) while the agent runs on localhost:9876.
//
// Notable: includes Private Network Access (PNA) headers for Chrome, which
// requires explicit opt-in for public websites to access localhost servers.
func (s *Server) withCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && s.isOriginAllowed(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			// Include Connect-RPC headers: connect-protocol-version, connect-timeout-ms
			w.Header().Set("Access-Control-Allow-Headers", "content-type, authorization, x-stackpanel-token, connect-protocol-version, connect-timeout-ms")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			// Expose Connect-RPC headers in responses
			w.Header().Set("Access-Control-Expose-Headers", "connect-protocol-version, grpc-status, grpc-message")
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

// requireAuth enforces both origin allowlist and JWT token validation.
// Origin is checked first to fast-fail cross-origin attacks before token parsing.
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

// hasValidToken checks for a valid token in three places (in priority order):
// 1. X-Stackpanel-Token header (preferred, used by the web UI)
// 2. Authorization: Bearer header (standard, used by API clients)
// 3. ?token= query param (fallback for WebSocket connections that can't set headers)
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

// isValidToken checks a token against JWT validation first, then falls back to
// a static auth token from config. The static token is used by CLI scripts and
// automation that don't go through the browser pairing flow.
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

// isOriginAllowed determines if a browser origin can talk to the agent.
// The check is layered:
//  1. Always allow loopback and *.localhost (covers Caddy dev domains like myapp.localhost)
//  2. Always allow *.ts.net (Tailscale remote access)
//  3. If AllowedOrigins is configured, use that as a strict allowlist
//  4. Otherwise, allow only the hosted UI domains (stackpanel.com/dev)
func (s *Server) isOriginAllowed(origin string) bool {
	if u, err := url.Parse(origin); err == nil {
		host := strings.ToLower(u.Hostname())
		if host == "localhost" || host == "127.0.0.1" || host == "::1" || strings.HasSuffix(host, ".localhost") {
			return true
		}
		if strings.HasSuffix(host, ".ts.net") {
			return true
		}
	}

	if len(s.config.AllowedOrigins) > 0 {
		for _, allowed := range s.config.AllowedOrigins {
			if origin == allowed {
				return true
			}
		}
		return false
	}

	return origin == "https://stackpanel.com" || origin == "https://stackpanel.dev"
}
