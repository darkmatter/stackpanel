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

// SSEEvent represents a server-sent event.
type SSEEvent struct {
	Event string `json:"event"`
	Data  any    `json:"data"`
}

// watchConfigFiles watches for changes to stackpanel config files and broadcasts SSE events.
func (s *Server) watchConfigFiles() {
	// Watch the state file
	stateFile := envvars.StackpanelStateFile.Get()
	if err := s.watcher.Add(filepath.Dir(stateFile)); err != nil {
		log.Warn().Err(err).Str("path", stateFile).Msg("failed to watch state directory")
	}

	// Watch the gen directory for file changes
	genDir := envvars.StackpanelGenDir.Get()
	if err := s.watcher.Add(genDir); err != nil {
		log.Warn().Err(err).Str("path", genDir).Msg("failed to watch gen directory")
	}

	// Watch the data directory for Nix data file changes
	dataDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "data")
	if err := s.watcher.Add(dataDir); err != nil {
		// Data dir might not exist yet, that's fine
		log.Debug().Err(err).Str("path", dataDir).Msg("failed to watch data directory (may not exist yet)")
	}

	// Debounce rapid file changes
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

	// Send initial connection event
	fmt.Fprintf(w, "event: connected\ndata: {\"status\":\"ok\"}\n\n")
	flusher.Flush()

	// Stream events
	for {
		select {
		case <-r.Context().Done():
			return
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

// broadcastSSE sends an event to all connected SSE subscribers.
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
