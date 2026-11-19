package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
)

func TestPairRedeemRequiresExactProof(t *testing.T) {
	jwt, err := NewJWTManager()
	if err != nil {
		t.Fatal(err)
	}
	s := &Server{config: &config.Config{}, jwtManager: jwt}
	const agent = "http://localhost:9876"
	grant := pairReturnGrant{
		origin:   "http://localhost:3000",
		endpoint: agent,
		state:    "test-state",
		verifier: "private-tab-proof",
	}
	code := s.pairReturns.issue(grant, time.Now())
	if code == "" {
		t.Fatal("expected code")
	}
	redeem := func(method, endpoint, origin, state, verifier, query string, want int) {
		t.Helper()
		body, err := json.Marshal(
			map[string]string{"code": code, "state": state, "verifier": verifier},
		)
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(
			method,
			endpoint+"/pair/redeem"+query,
			bytes.NewReader(body),
		)
		r.Header.Set("Origin", origin)
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		s.handlePairRedeem(w, r)
		if w.Code != want || w.Header().Get("Cache-Control") != "no-store" {
			t.Fatalf("unexpected redemption status %d (want %d)", w.Code, want)
		}
		if want == http.StatusOK {
			var result struct {
				Token string `json:"token"`
			}
			if err := json.Unmarshal(
				w.Body.Bytes(),
				&result,
			); err != nil ||
				!jwt.IsValidToken(result.Token) {
				t.Fatal("expected valid agent credential only in response body")
			}
		}
	}
	redeem("GET", agent, grant.origin, grant.state, grant.verifier, "", 405)
	redeem("POST", agent, "", grant.state, grant.verifier, "", 403)
	redeem("POST", agent, "http://127.0.0.1:3000", grant.state, grant.verifier, "", 403)
	redeem(
		"POST",
		"http://127.0.0.1:9876",
		grant.origin,
		grant.state,
		grant.verifier,
		"",
		403,
	)
	redeem("POST", agent, grant.origin, "wrong-state", grant.verifier, "", 403)
	redeem("POST", agent, grant.origin, grant.state, "", "", 403)
	redeem("POST", agent, grant.origin, grant.state, grant.verifier, "?code="+code, 400)
	redeem("POST", agent, grant.origin, grant.state, grant.verifier, "", 200)
	redeem("POST", agent, grant.origin, grant.state, grant.verifier, "", 403)
}

func TestPairReturnBoundedExpiryAndConcurrentReplay(t *testing.T) {
	var store pairReturnStore
	now := time.Now()
	grant := pairReturnGrant{
		origin:   "studio",
		endpoint: "agent",
		state:    "state",
		verifier: "verifier",
	}
	var first string
	for i := range pairReturnLimit {
		code := store.issue(grant, now)
		if code == "" {
			t.Fatal("did not issue return code")
		}
		if i == 0 {
			first = code
		}
	}
	if store.issue(grant, now) != "" {
		t.Fatal("store exceeded limit")
	}
	now = now.Add(pairReturnTTL)
	if store.consume(first, grant, now) {
		t.Fatal("expired code accepted")
	}
	code := store.issue(grant, now)
	if code == "" || len(store.grants) != 1 {
		t.Fatal("expired entries not reclaimed")
	}
	var count atomic.Int32
	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if store.consume(code, grant, now) {
				count.Add(1)
			}
		}()
	}
	wg.Wait()
	if count.Load() != 1 {
		t.Fatalf("code consumed %d times", count.Load())
	}
}
