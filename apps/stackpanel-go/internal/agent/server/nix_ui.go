package server

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"
)

// uiRuntimeCache caches the JSON-safe Stackpanel runtime config that we read
// via nix eval (impure) from STACKPANEL_CONFIG_JSON.
//
// This is intentionally separate from the main config evaluation pipeline:
// - The runtime snapshot is JSON-safe by construction (written by stackpanel core/cli.nix)
// - Evaluating it is fast and avoids encoding derivations/packages/etc.
type uiRuntimeCache struct {
	mu        sync.RWMutex
	data      any
	updatedAt time.Time
}

var globalUIRuntimeCache uiRuntimeCache

const uiRuntimeCacheTTL = 2 * time.Second

func (s *Server) getUIRuntimeSnapshot() (any, int, error) {
	// Fast path: cached
	globalUIRuntimeCache.mu.RLock()
	if globalUIRuntimeCache.data != nil && time.Since(globalUIRuntimeCache.updatedAt) < uiRuntimeCacheTTL {
		data := globalUIRuntimeCache.data
		globalUIRuntimeCache.mu.RUnlock()
		return data, http.StatusOK, nil
	}
	globalUIRuntimeCache.mu.RUnlock()

	// Slow path: nix eval (impure) to read STACKPANEL_CONFIG_JSON
	//
	// We keep this as a nix eval instead of reading the env var directly in Go because:
	// - The executor may have loaded the devshell env (STACKPANEL_CONFIG_JSON) for nix runs
	// - The agent process environment may not include it
	args := []string{
		"eval",
		"--impure",
		"--json",
		"--expr",
		`builtins.fromJSON (builtins.readFile (builtins.getEnv "STACKPANEL_CONFIG_JSON"))`,
	}

	res, err := s.exec.RunNix(args...)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if res.ExitCode != 0 {
		return nil, http.StatusBadRequest, errString(res.Stderr)
	}

	var v any
	if err := json.Unmarshal([]byte(res.Stdout), &v); err != nil {
		return nil, http.StatusInternalServerError, errString("failed to parse nix eval output as JSON")
	}

	globalUIRuntimeCache.mu.Lock()
	globalUIRuntimeCache.data = v
	globalUIRuntimeCache.updatedAt = time.Now()
	globalUIRuntimeCache.mu.Unlock()

	return v, http.StatusOK, nil
}

func errString(s string) error {
	return &runtimeError{msg: s}
}

type runtimeError struct {
	msg string
}

func (e *runtimeError) Error() string { return e.msg }

// handleNixUIRuntime returns the JSON-safe runtime snapshot for the current project.
// This is sourced from STACKPANEL_CONFIG_JSON (Nix store path) and evaluated via nix.
func (s *Server) handleNixUIRuntime(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	v, status, err := s.getUIRuntimeSnapshot()
	if err != nil {
		s.writeAPIError(w, status, err.Error())
		return
	}
	s.writeAPI(w, http.StatusOK, v)
}

// handleNixUIExtensions returns the declarative UI extension registry.
// This is a subset of the runtime snapshot: runtime.ui.extensions
func (s *Server) handleNixUIExtensions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	v, status, err := s.getUIRuntimeSnapshot()
	if err != nil {
		s.writeAPIError(w, status, err.Error())
		return
	}

	// Extract runtime.ui.extensions (default to empty object)
	extensions := map[string]any{}
	if root, ok := v.(map[string]any); ok {
		if ui, ok := root["ui"].(map[string]any); ok {
			if exts, ok := ui["extensions"].(map[string]any); ok {
				extensions = exts
			}
		}
	}

	s.writeAPI(w, http.StatusOK, extensions)
}
