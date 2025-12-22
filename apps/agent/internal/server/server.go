// Package server provides the HTTP/gRPC server for the stackpanel agent.
package server

import (
	"fmt"
	"net/http"

	"github.com/darkmatter/stackpanel/agent/internal/config"
)

// Server is the main agent server
type Server struct {
	config     *config.Config
	httpServer *http.Server
}

// New creates a new server instance
func New(cfg *config.Config) (*Server, error) {
	s := &Server{
		config: cfg,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/status", s.handleStatus)

	s.httpServer = &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.Port),
		Handler: mux,
	}

	return s, nil
}

// Start begins serving requests
func (s *Server) Start() error {
	return s.httpServer.ListenAndServe()
}

// Stop gracefully shuts down the server
func (s *Server) Stop() {
	if s.httpServer != nil {
		s.httpServer.Close()
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status": "running"}`))
}
