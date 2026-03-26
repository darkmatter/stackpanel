package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"time"

	envvars "github.com/darkmatter/stackpanel/stackpanel-go/pkg/envvars"
	"github.com/fsnotify/fsnotify"
	"github.com/rs/zerolog/log"
)

// SSEEvent represents a server-sent event. Event types include:
//   - "connected": initial event with project info (sent on SSE connect)
//   - "config.changed": a file in .stack/ was modified on disk (fsnotify)
//   - "flake.config.updated": stackpanelConfig re-evaluated after nix file change
//   - "flake.packages.updated": stackpanelPackages re-evaluated
//   - "shell.stale": nix files changed, devshell may need rebuild
//   - "shell.rebuilding" / "shell.rebuilt": rebuild lifecycle
//   - "ping": keepalive heartbeat (every 5s)
type SSEEvent struct {
	Event string `json:"event"`
	Data  any    `json:"data"`
}

// watchConfigFiles uses fsnotify to watch .stack/state, .stack/gen, and .stack/data
// for changes, broadcasting "config.changed" SSE events. This is separate from
// FlakeWatcher — it handles simple file change notifications without re-evaluating Nix.
// Changes are debounced at 100ms to coalesce rapid file writes (e.g., during codegen).
func (s *Server) watchConfigFiles() {
	stateFile := envvars.StackpanelStateFile.Get()
	if err := s.watcher.Add(filepath.Dir(stateFile)); err != nil {
		log.Warn().Err(err).Str("path", stateFile).Msg("failed to watch state directory")
	}

	genDir := envvars.StackpanelGenDir.Get()
	if err := s.watcher.Add(genDir); err != nil {
		log.Warn().Err(err).Str("path", genDir).Msg("failed to watch gen directory")
	}

	dataDir := filepath.Join(s.config.ProjectRoot, ".stack", "data")
	if err := s.watcher.Add(dataDir); err != nil {
		log.Debug().Err(err).Str("path", dataDir).Msg("failed to watch data directory (may not exist yet)")
	}

	var debounceTimer *time.Timer
	debounceDuration := 100 * time.Millisecond

	for {
		select {
		case event, ok := <-s.watcher.Events:
			if !ok {
				return
			}
			if event.Op&(fsnotify.Write|fsnotify.Create) != 0 {
				name := event.Name
				// Debounce: reset timer on each event
				if debounceTimer != nil {
					debounceTimer.Stop()
				}
				debounceTimer = time.AfterFunc(debounceDuration, func() {
					log.Debug().Str("file", name).Msg("config file changed, broadcasting")
					s.broadcastSSE(SSEEvent{
						Event: "config.changed",
						Data: map[string]string{
							"file": name,
						},
					})
				})
			}
		case err, ok := <-s.watcher.Errors:
			if !ok {
				return
			}
			log.Warn().Err(err).Msg("file watcher error")
		}
	}
}

// handleSSE handles Server-Sent Events connections for real-time updates.
// The web UI's AgentSSEProvider maintains a persistent connection to this endpoint,
// using received events to invalidate TanStack Query caches and trigger refetches.
func (s *Server) handleSSE(w http.ResponseWriter, r *http.Request) {
	// Set SSE headers
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	// Create channel for this subscriber
	eventChan := make(chan SSEEvent, 10)

	// Register subscriber
	s.sseSubscribersMu.Lock()
	s.sseSubscribers[eventChan] = struct{}{}
	s.sseSubscribersMu.Unlock()

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
	hasProject := s.config.ProjectRoot != ""
	connectedData := map[string]any{
		"status":      "ok",
		"hasProject":  hasProject,
		"projectRoot": s.config.ProjectRoot,
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
		case <-r.Context().Done():
			return
		case <-heartbeatTicker.C:
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

// broadcastSSE fans out an event to all connected SSE subscribers.
// Uses non-blocking sends — if a subscriber's channel is full (buffer=10),
// the event is dropped for that subscriber rather than blocking all others.
func (s *Server) broadcastSSE(event SSEEvent) {
	s.sseSubscribersMu.RLock()
	defer s.sseSubscribersMu.RUnlock()

	for ch := range s.sseSubscribers {
		select {
		case ch <- event:
		default:
			// Channel full, skip (subscriber too slow)
			log.Debug().Msg("SSE subscriber channel full, skipping event")
		}
	}
}
