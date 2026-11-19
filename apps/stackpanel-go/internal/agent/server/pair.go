package server

import (
	"bytes"
	"net/http"
	"net/netip"
	"net/url"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
)

// Studio submits a top-level form into its pairing popup. A POST navigation
// carries the browser's Origin even when a cross-origin Referer is omitted.
// Never take the recipient of a bearer credential from a URL parameter.

// pairTemplateData is injected into the pair.html popup template.
type pairTemplateData struct {
	ProjectRoot  string
	TargetOrigin string
	ReturnURL    string
	State        string
	ReturnCode   string
	Token        string
}

func validPairNonce(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, c := range value {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	return true
}

// handlePair serves the pairing popup page. It validates the requesting origin,
// generates a fresh JWT, and renders an HTML page that posts the token back.
func (s *Server) handlePair(w http.ResponseWriter, r *http.Request) {
	// Pairing is a standalone navigation, never an embeddable document or
	// a resource the sandbox may fetch. Apply both browser enforcement and
	// Fetch Metadata checks before minting any credential.
	w.Header().Set("Content-Security-Policy", "frame-ancestors 'none'")
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	dest, mode := r.Header.Get("Sec-Fetch-Dest"), r.Header.Get("Sec-Fetch-Mode")
	if r.Method != http.MethodPost || (dest != "" && dest != "document") ||
		(mode != "" && mode != "navigate") || r.Header.Get("Sec-Fetch-Site") == "same-origin" {
		http.Error(w, "pairing requires a standalone navigation", http.StatusForbidden)
		return
	}
	origin := r.Header.Get("Origin")
	if !s.validPairPeer(origin, r) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write(
			[]byte("Pairing not allowed from this origin. Open Stackpanel first."),
		)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid pairing form", http.StatusBadRequest)
		return
	}
	state := r.PostForm.Get("state")
	if !validPairNonce(state) {
		http.Error(w, "missing pairing state", http.StatusBadRequest)
		return
	}
	returnURL := pairReturnURL(r.PostForm.Get("return_to"), origin)
	verifier := r.PostForm.Get("verifier")
	if returnURL != "" && (!validPairNonce(verifier) || verifier == state) {
		http.Error(w, "invalid return verifier", http.StatusBadRequest)
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
		TargetOrigin: origin,
		ReturnURL:    returnURL,
		State:        state,
		Token:        token,
	}
	if data.ReturnURL != "" {
		data.ReturnCode = s.pairReturns.issue(pairReturnGrant{
			origin: origin, endpoint: pairEndpoint(r), state: state, verifier: verifier,
		}, time.Now())
		// Saturation disables redirect only; direct popup approval still works.
		if data.ReturnCode == "" {
			data.ReturnURL = ""
		}
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

func (s *Server) validPairPeer(origin string, r *http.Request) bool {
	peer, err := url.Parse(origin)
	if err != nil || (peer.Scheme != "http" && peer.Scheme != "https") || peer.Hostname() == "" ||
		peer.User != nil ||
		origin != peer.Scheme+"://"+peer.Host {
		return false
	}
	agent := url.URL{Scheme: "http", Host: r.Host}
	if r.TLS != nil {
		agent.Scheme = "https"
	}
	if peer.Scheme == agent.Scheme && samePairHost(peer.Hostname(), agent.Hostname()) &&
		pairPort(peer) == pairPort(&agent) {
		return false
	}
	return s.isOriginAllowed(origin)
}

func samePairHost(a, b string) bool {
	if strings.EqualFold(a, b) {
		return true
	}
	// An IPv6 address may arrive in compressed or expanded form.
	ip, err := netip.ParseAddr(a)
	if err != nil {
		return false
	}
	other, err := netip.ParseAddr(b)
	return err == nil && ip == other
}

func pairPort(u *url.URL) string {
	if port := u.Port(); port != "" {
		return strings.TrimLeft(port, "0")
	}
	if u.Scheme == "https" {
		return "443"
	}
	return "80"
}

// normalizeOrigin strips path/query from a URL and returns just scheme://host.
func normalizeOrigin(raw string) (string, bool) {
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "https" && u.Scheme != "http") || u.Hostname() == "" ||
		u.User != nil {
		return "", false
	}
	return u.Scheme + "://" + u.Host, true
}

func pairReturnURL(raw, origin string) string {
	if raw == "" {
		return "" // popup-only pairing; no URL-selected remote agent fallback
	}
	u, err := url.Parse(raw)
	if err != nil || u.User != nil || u.Scheme+"://"+u.Host != origin ||
		(u.Path != "/studio" && !strings.HasPrefix(u.Path, "/studio/")) {
		return origin + "/studio"
	}
	// Only Studio routing metadata is needed for the fallback. Never nest the
	// caller's fragment or a legacy ?token= in a network-visible return URL.
	u.RawQuery, u.Fragment, u.RawFragment = studioHandoff(u.Query()).Encode(), "", ""
	return u.String()
}
