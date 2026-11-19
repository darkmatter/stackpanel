package server

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupsession"
	"github.com/rs/zerolog/log"
)

const moduleDevDiagnosticsEvent = "module.dev.diagnostics"

// LinkedModuleStatus deliberately omits filesystem paths and full launch URLs.
// uiDevUrl is a display origin only (scheme and host, including port).
type LinkedModuleStatus struct {
	UIDevURL string `json:"uiDevUrl,omitempty"`
}

// ModuleDevDiagnostics is a replacement snapshot, not a delta. A pending
// evaluation has no timing; a successful config eval clears any previous error.
// Error is selected from fixed public summaries; it is never Nix stderr.
type ModuleDevDiagnostics struct {
	ProjectID     string                        `json:"projectId"`
	LinkedModules map[string]LinkedModuleStatus `json:"linkedModules"`
	EvaluatedAt   string                        `json:"evaluatedAt,omitempty"`
	DurationMs    *int64                        `json:"durationMs,omitempty"`
	Error         string                        `json:"error,omitempty"`
}

// SSEEvent represents a server-sent event. Event types include:
//   - "connected": initial event with project info (sent on SSE connect)
//   - "config.changed": a file in .stack/ was modified on disk (fsnotify)
//   - "flake.config.updated": stackpanelConfig re-evaluated after nix file change
//   - "flake.packages.updated": stackpanelPackages re-evaluated
//   - "module.dev.diagnostics": linked inputs and latest config evaluation result
//   - "shell.stale": nix files changed, devshell may need rebuild
//   - "shell.rebuilding" / "shell.rebuilt": rebuild lifecycle
//   - "ping": keepalive heartbeat (every 5s)
type SSEEvent struct {
	Event       string `json:"event"`
	Data        any    `json:"data"`
	ProjectRoot string `json:"-"` // stream routing only; empty for existing agent-wide events
}

// handleSSE handles Server-Sent Events connections for real-time updates.
// The web UI's AgentSSEProvider maintains a persistent connection to this endpoint,
// using received events to invalidate TanStack Query caches and trigger refetches.
func (s *Server) handleSSE(w http.ResponseWriter, r *http.Request) {
	setupID := r.URL.Query().Get("setup")
	projectID := r.URL.Query().Get("project")
	connectionID := ""
	root := s.config.ProjectRoot
	if setupID != "" {
		session, err := s.validateSetupRequest(r, setupID)
		if err != nil {
			s.writeAPIError(w, http.StatusConflict, err.Error())
			return
		}
		root = session.Root
		var nonce [16]byte
		if _, err := rand.Read(nonce[:]); err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		connectionID = hex.EncodeToString(nonce[:])
		if err := setupsession.Update(setupID, func(session *setupsession.Session) error {
			session.Connection = connectionID
			session.ConnectedAt = time.Now()
			session.ReadyAt = time.Time{}
			return nil
		}); err != nil {
			s.writeAPIError(w, http.StatusConflict, err.Error())
			return
		}
		defer func() {
			_ = setupsession.Update(setupID, func(session *setupsession.Session) error {
				if session.Connection == connectionID {
					session.Connection = ""
				}
				return nil
			})
		}()
	}
	// Legacy connections bind to the current project's non-sensitive updates.
	// Diagnostics additionally require an explicitly selected project/setup.
	if setupID == "" && projectID != "" {
		var err error
		root, err = s.resolveProjectRoot(projectID)
		if err != nil {
			s.writeAPIError(w, http.StatusBadRequest, err.Error())
			return
		}
	}
	var rt *projectRuntime
	var fw *FlakeWatcher
	if root != "" {
		var err error
		rt, err = s.runtimes.get(root)
		if err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, err.Error())
			return
		}
		s.runtimes.mu.Lock()
		fw = rt.flake
		s.runtimes.mu.Unlock()
		root, err = filepath.Abs(root)
		if err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, err.Error())
			return
		}
	}
	// Set SSE headers
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	// requireAuth has already validated the token (including for localhost).
	scope := sseScope{root: root, diagnostics: setupID != "" || projectID != ""}
	eventChan := s.subscribeSSE(scope, fw)

	// Cleanup on disconnect
	defer func() {
		s.sseSubscribersMu.Lock()
		delete(s.sseSubscribers, eventChan)
		s.sseSubscribersMu.Unlock()
		close(eventChan)
	}()

	// Flush support
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "SSE not supported", http.StatusInternalServerError)
		return
	}

	// Send initial "connected" event with project info so the UI can immediately
	// render project state without a separate health poll round-trip.
	hasProject := root != ""
	connectedData := map[string]any{
		"status":      "ok",
		"hasProject":  hasProject,
		"projectRoot": root,
		"agentId":     s.jwtManager.GetAgentID(),
	}
	connectedJSON, _ := json.Marshal(connectedData)
	fmt.Fprintf(w, "event: connected\ndata: %s\n\n", connectedJSON)
	flusher.Flush()

	// Heartbeat ticker - sends ping events every 5 seconds for keepalive
	heartbeatTicker := time.NewTicker(5 * time.Second)
	defer heartbeatTicker.Stop()

	// Stream events
	for {
		select {
		case <-s.done:
			return
		case <-r.Context().Done():
			return
		case <-heartbeatTicker.C:
			// An open non-current project in Studio is an active consumer even
			// when no RPCs have been made since the last edit.
			if rt != nil {
				s.runtimes.mu.Lock()
				rt.lastUsed = s.runtimes.now()
				s.runtimes.mu.Unlock()
			}
			if setupID != "" {
				_ = setupsession.Update(setupID, func(session *setupsession.Session) error {
					if session.Connection == connectionID {
						session.ConnectedAt = time.Now()
					}
					return nil
				})
			}
			// Send heartbeat ping
			fmt.Fprintf(w, "event: ping\ndata: {\"ts\":%d}\n\n", time.Now().UnixMilli())
			flusher.Flush()
		case event := <-eventChan:
			data, err := json.Marshal(event.Data)
			if err != nil {
				log.Warn().Err(err).Msg("failed to marshal SSE event data")
				continue
			}
			fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event.Event, data)
			flusher.Flush()
		}
	}
}

type sseScope struct {
	root        string
	diagnostics bool // explicitly selected, validated project/setup; never an implicit current project
}

func (scope sseScope) accepts(event SSEEvent) bool {
	if event.Event == moduleDevDiagnosticsEvent &&
		(!scope.diagnostics || event.ProjectRoot == "") {
		return false
	}
	return event.ProjectRoot == "" || event.ProjectRoot == scope.root
}

func (s *Server) subscribeSSE(scope sseScope, fw *FlakeWatcher) chan SSEEvent {
	ch := make(chan SSEEvent, 10)
	// Publish takes these locks in this order. Queue the snapshot atomically
	// with subscription, so a fast initial eval neither disappears nor replays
	// an older error over a newer result. No filesystem reads here.
	if scope.diagnostics && fw != nil {
		fw.mu.RLock()
		defer fw.mu.RUnlock()
	}
	s.sseSubscribersMu.Lock()
	defer s.sseSubscribersMu.Unlock()
	s.sseSubscribers[ch] = scope
	if scope.diagnostics && fw != nil {
		event := SSEEvent{
			Event:       moduleDevDiagnosticsEvent,
			ProjectRoot: fw.projectRoot,
			Data:        fw.diagnostics,
		}
		if scope.accepts(event) {
			ch <- event
		}
	}
	return ch
}

// broadcastSSE fans out an event to all connected SSE subscribers.
// Uses non-blocking sends — if a subscriber's channel is full (buffer=10),
// the event is dropped for that subscriber rather than blocking all others.
func (s *Server) broadcastSSE(event SSEEvent) {
	s.sseSubscribersMu.RLock()
	defer s.sseSubscribersMu.RUnlock()

	for ch, scope := range s.sseSubscribers {
		if !scope.accepts(event) {
			continue
		}
		select {
		case ch <- event:
		default:
			// Channel full, skip (subscriber too slow)
			log.Debug().Msg("SSE subscriber channel full, skipping event")
		}
	}
}
