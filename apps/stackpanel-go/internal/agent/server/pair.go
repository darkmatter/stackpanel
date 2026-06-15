package server

import (
	"bytes"
	"encoding/json"
	"html/template"
	"net/http"
	"net/url"
	"strings"

	"github.com/rs/zerolog/log"
)

// Pairing flow: the web UI opens /pair?origin=<ui-origin> in a popup window.
// The page shows the project info and a "Pair" button. On click, it posts a
// JWT token back to the opener via window.postMessage, scoped to the origin.
// The UI stores this token in localStorage for subsequent API calls.

// pairTemplateData is injected into the pair.html popup template.
type pairTemplateData struct {
	ProjectRoot  string
	TargetOrigin template.JS // JS-safe quoted origin for postMessage targetOrigin
	ReturnURL    template.JS // JS-safe quoted URL for no-opener redirect fallback
	Token        template.JS // JS-safe quoted JWT for postMessage payload
}

// handlePair serves the pairing popup page. It validates the requesting origin,
// generates a fresh JWT, and renders an HTML page that posts the token back.
func (s *Server) handlePair(w http.ResponseWriter, r *http.Request) {
	origin := s.getPairOrigin(r)
	if origin == "" || !s.isOriginAllowed(origin) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write(
			[]byte("Pairing not allowed from this origin. Open Stackpanel first."),
		)
		return
	}

	// Generate a JWT token for this pairing request
	token, err := s.jwtManager.GenerateToken(origin)
	if err != nil {
		log.Error().Err(err).Msg("failed to generate JWT token")
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	data := pairTemplateData{
		ProjectRoot:  s.config.ProjectRoot,
		TargetOrigin: jsString(origin),
		ReturnURL:    jsString(s.getPairReturnURL(r, origin)),
		Token:        jsString(token),
	}

	var buf bytes.Buffer
	if err := s.pairTemplate.Execute(&buf, data); err != nil {
		log.Error().Err(err).Msg("failed to render pair template")
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(buf.Bytes())
}

// getPairOrigin extracts the origin for the pairing request, checking the
// ?origin query param first (explicit), then falling back to the Referer header.
func (s *Server) getPairOrigin(r *http.Request) string {
	if q := strings.TrimSpace(r.URL.Query().Get("origin")); q != "" {
		origin, ok := normalizeOrigin(q)
		if ok {
			return origin
		}
		return ""
	}

	ref := strings.TrimSpace(r.Referer())
	if ref == "" {
		return ""
	}
	u, err := url.Parse(ref)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host
}

// normalizeOrigin strips path/query from a URL and returns just scheme://host.
func normalizeOrigin(raw string) (string, bool) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return "", false
	}
	return u.Scheme + "://" + u.Host, true
}

func jsString(value string) template.JS {
	encoded, err := json.Marshal(value)
	if err != nil {
		return template.JS("null")
	}
	return template.JS(encoded)
}

func (s *Server) getPairReturnURL(r *http.Request, origin string) string {
	raw := strings.TrimSpace(r.URL.Query().Get("return_to"))
	if raw == "" {
		return origin
	}

	u, err := url.Parse(raw)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return origin
	}

	returnOrigin := u.Scheme + "://" + u.Host
	if returnOrigin != origin {
		return origin
	}

	return raw
}
