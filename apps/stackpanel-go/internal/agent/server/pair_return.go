package server

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"net/http"
	"sync"
	"time"
)

const (
	pairReturnLimit = 128
	pairReturnTTL   = 5 * time.Minute
)

// No JWT is stored or returned in a URL. Possession of a code and state is
// insufficient: redemption needs the private verifier from the initiating tab.
type pairReturnGrant struct {
	origin, endpoint, state, verifier string
	expires                           time.Time
}

type pairReturnStore struct {
	mu     sync.Mutex
	grants map[string]pairReturnGrant
}

func (s *pairReturnStore) issue(grant pairReturnGrant, now time.Time) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	for code, existing := range s.grants {
		if !now.Before(existing.expires) {
			delete(s.grants, code)
		}
	}
	if len(s.grants) >= pairReturnLimit {
		return ""
	}
	var random [32]byte
	if _, err := rand.Read(random[:]); err != nil {
		return ""
	}
	if s.grants == nil {
		s.grants = make(map[string]pairReturnGrant)
	}
	code := hex.EncodeToString(random[:])
	grant.expires = now.Add(pairReturnTTL)
	s.grants[code] = grant
	return code
}

func (s *pairReturnStore) consume(
	code string,
	want pairReturnGrant,
	now time.Time,
) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	grant, ok := s.grants[code]
	if !ok {
		return false
	}
	if !now.Before(grant.expires) {
		delete(s.grants, code)
		return false
	}
	if grant.origin != want.origin || grant.endpoint != want.endpoint ||
		grant.state != want.state ||
		subtle.ConstantTimeCompare([]byte(grant.verifier), []byte(want.verifier)) != 1 {
		return false
	}
	delete(s.grants, code)
	return true
}

func pairEndpoint(r *http.Request) string {
	if r.TLS != nil {
		return "https://" + r.Host
	}
	return "http://" + r.Host
}

func (s *Server) handlePairRedeem(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	origin := r.Header.Get("Origin")
	if !s.validPairPeer(origin, r) {
		http.Error(w, "invalid pairing peer", http.StatusForbidden)
		return
	}
	var body struct {
		Code     string `json:"code"`
		State    string `json:"state"`
		Verifier string `json:"verifier"`
	}
	if r.URL.RawQuery != "" || r.Header.Get("Content-Type") != "application/json" ||
		s.readJSON(http.MaxBytesReader(w, r.Body, 1024), &body) != nil {
		http.Error(
			w,
			"expected a pairing exchange in the request body",
			http.StatusBadRequest,
		)
		return
	}
	grant := pairReturnGrant{
		origin:   origin,
		endpoint: pairEndpoint(r),
		state:    body.State,
		verifier: body.Verifier,
	}
	if !s.pairReturns.consume(body.Code, grant, time.Now()) {
		http.Error(w, "invalid or expired pairing exchange", http.StatusForbidden)
		return
	}
	token, err := s.jwtManager.GenerateToken(origin)
	if err != nil {
		http.Error(w, "could not finish pairing", http.StatusInternalServerError)
		return
	}
	s.writeJSON(w, http.StatusOK, map[string]string{"token": token})
}
