package server

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	sharedexec "github.com/darkmatter/stackpanel/stackpanel-go/pkg/exec"
	"github.com/rs/zerolog/log"
)

// configCache holds the cached config and metadata
type configCache struct {
	mu          sync.RWMutex
	config      map[string]any
	lastUpdated time.Time
	configPath  string // Path to the cached config file
}

var globalConfigCache = &configCache{}

// handleNixConfig returns the current Stackpanel config.
// GET: Returns cached config (fast)
// POST: Forces a refresh by re-evaluating the flake (slow but fresh)
func (s *Server) handleNixConfig(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleNixConfigGet(w, r)
	case http.MethodPost:
		s.handleNixConfigRefresh(w, r)
	default:
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// handleNixConfigGet returns the current config, either from cache or by evaluating
func (s *Server) handleNixConfigGet(w http.ResponseWriter, r *http.Request) {
	// Check if force refresh is requested via query param
	forceRefresh := r.URL.Query().Get("refresh") == "true"

	// Try FlakeWatcher first (preferred - has file watching and smart caching)
	if s.flakeWatcher != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()

		if forceRefresh {
			s.flakeWatcher.InvalidateAll()
		}

		config, err := s.flakeWatcher.GetConfig(ctx)
		if err == nil {
			updated, cached := s.flakeWatcher.ConfigStatus()
			s.writeAPI(w, http.StatusOK, map[string]any{
				"config":       config,
				"last_updated": updated.Format(time.RFC3339),
				"cached":       cached,
				"source":       "flake_watcher",
			})
			return
		}
		log.Debug().Err(err).Msg("FlakeWatcher config evaluation failed, falling back to legacy")
	}

	// Fallback to legacy cache/evaluation
	if !forceRefresh {
		// Try to get from cache first
		globalConfigCache.mu.RLock()
		if globalConfigCache.config != nil {
			config := globalConfigCache.config
			lastUpdated := globalConfigCache.lastUpdated
			globalConfigCache.mu.RUnlock()

			s.writeAPI(w, http.StatusOK, map[string]any{
				"config":       config,
				"last_updated": lastUpdated.Format(time.RFC3339),
				"cached":       true,
				"source":       "legacy_cache",
			})
			return
		}
		globalConfigCache.mu.RUnlock()
	}

	// No cache or force refresh - evaluate config
	config, err := s.evaluateConfig()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to evaluate config: "+err.Error())
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"config":       config,
		"last_updated": time.Now().Format(time.RFC3339),
		"cached":       false,
		"source":       "fresh_eval",
	})
}

// handleNixConfigRefresh forces a config refresh by re-evaluating the flake
func (s *Server) handleNixConfigRefresh(w http.ResponseWriter, r *http.Request) {
	log.Info().Msg("Refreshing Stackpanel config from flake")

	ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
	defer cancel()

	// Try FlakeWatcher first
	if s.flakeWatcher != nil {
		if err := s.flakeWatcher.ForceRefresh(ctx); err != nil {
			log.Warn().Err(err).Msg("FlakeWatcher refresh failed, falling back to legacy")
		} else {
			config, _ := s.flakeWatcher.GetConfig(ctx)
			s.writeAPI(w, http.StatusOK, map[string]any{
				"config":       config,
				"last_updated": time.Now().Format(time.RFC3339),
				"refreshed":    true,
				"source":       "flake_watcher",
			})

			// Notify SSE subscribers that config has changed
			s.broadcastSSE(SSEEvent{
				Event: "config.refreshed",
				Data: map[string]any{
					"timestamp": time.Now().Format(time.RFC3339),
				},
			})
			return
		}
	}

	// Fallback to legacy evaluation
	config, err := s.evaluateConfig()
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to evaluate config: "+err.Error())
		return
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"config":       config,
		"last_updated": time.Now().Format(time.RFC3339),
		"refreshed":    true,
		"source":       "fresh_eval",
	})

	// Notify SSE subscribers that config has changed
	s.broadcastSSE(SSEEvent{
		Event: "config.refreshed",
		Data: map[string]any{
			"timestamp": time.Now().Format(time.RFC3339),
		},
	})
}

// evaluateConfig evaluates the Stackpanel config from the flake or config file
func (s *Server) evaluateConfig() (map[string]any, error) {
	var config map[string]any
	var err error

	// Strategy 1: Try to evaluate from flake output
	config, err = s.evaluateConfigFromFlake()
	if err == nil {
		s.cacheConfig(config)
		return config, nil
	}
	log.Debug().Err(err).Msg("Failed to evaluate config from flake, trying STACKPANEL_CONFIG_JSON")

	// Strategy 2: Try STACKPANEL_CONFIG_JSON env var (pre-computed JSON)
	if jsonPath := os.Getenv("STACKPANEL_CONFIG_JSON"); jsonPath != "" {
		config, err = s.loadConfigFromJSON(jsonPath)
		if err == nil {
			s.cacheConfig(config)
			return config, nil
		}
		log.Debug().Err(err).Str("path", jsonPath).Msg("Failed to load config from STACKPANEL_CONFIG_JSON")
	}

	// Strategy 3: Try to find a cached config in the project
	cachedPath := filepath.Join(s.config.ProjectRoot, ".stackpanel", "gen", "config.json")
	if config, err = s.loadConfigFromJSON(cachedPath); err == nil {
		s.cacheConfig(config)
		return config, nil
	}

	return nil, err
}

// evaluateConfigFromFlake evaluates the config by running nix eval on the flake
func (s *Server) evaluateConfigFromFlake() (map[string]any, error) {
	// Try paths in priority order:
	// 1. devshell passthru (for user projects consuming stackpanel)
	// 2. stackpanelConfig flake output (for stackpanel repo itself)
	// Note: Do NOT use stackpanelFullConfig - it contains non-serializable values (functions, modules)
	attributePaths := []string{
		// User projects: devshell passthru has the stackpanel config
		".#devShells." + getCurrentSystem() + ".default.passthru.stackpanelSerializable",
		".#devShells." + getCurrentSystem() + ".default.passthru.stackpanelConfig",
		// Stackpanel repo: direct flake outputs
		".#stackpanelConfig",
	}

	var res *sharedexec.Result
	var err error

	for _, attrPath := range attributePaths {
		args := []string{"eval", "--impure", "--json", attrPath}
		res, err = s.exec.RunNix(args...)
		if err == nil && res.ExitCode == 0 {
			break
		}
	}

	if res == nil || res.ExitCode != 0 {
		errMsg := "all attribute paths failed"
		if res != nil && res.Stderr != "" {
			errMsg = strings.TrimSpace(res.Stderr)
		}
		return nil, &evalError{stderr: errMsg}
	}

	var config map[string]any
	if err := json.Unmarshal([]byte(res.Stdout), &config); err != nil {
		return nil, err
	}

	// Also save to a local cache file for faster subsequent loads
	s.saveConfigToCache(config)

	return config, nil
}

// loadConfigFromJSON loads config from a JSON file
func (s *Server) loadConfigFromJSON(path string) (map[string]any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var config map[string]any
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, err
	}

	return config, nil
}

// cacheConfig stores the config in the in-memory cache
func (s *Server) cacheConfig(config map[string]any) {
	globalConfigCache.mu.Lock()
	defer globalConfigCache.mu.Unlock()

	globalConfigCache.config = config
	globalConfigCache.lastUpdated = time.Now()
}

// saveConfigToCache saves the config to a local JSON file for persistence
func (s *Server) saveConfigToCache(config map[string]any) {
	cacheDir := filepath.Join(s.config.ProjectRoot, ".stackpanel", "gen")
	if err := os.MkdirAll(cacheDir, 0755); err != nil {
		log.Warn().Err(err).Msg("Failed to create cache directory")
		return
	}

	cachePath := filepath.Join(cacheDir, "config.json")
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		log.Warn().Err(err).Msg("Failed to marshal config for cache")
		return
	}

	if err := os.WriteFile(cachePath, data, 0644); err != nil {
		log.Warn().Err(err).Str("path", cachePath).Msg("Failed to write config cache")
		return
	}

	globalConfigCache.mu.Lock()
	globalConfigCache.configPath = cachePath
	globalConfigCache.mu.Unlock()

	log.Debug().Str("path", cachePath).Msg("Saved config to cache file")
}

// getCurrentSystem returns the current Nix system (e.g., "x86_64-linux", "aarch64-darwin")
func getCurrentSystem() string {
	// Try to get from environment first (allows override)
	if system := os.Getenv("NIX_SYSTEM"); system != "" {
		return system
	}

	// Use runtime values (not env vars which may not be set)
	goos := runtime.GOOS
	goarch := runtime.GOARCH

	// Map Go arch to Nix arch
	nixArch := goarch
	switch goarch {
	case "amd64":
		nixArch = "x86_64"
	case "arm64":
		nixArch = "aarch64"
	}

	// Map Go OS to Nix OS
	nixOS := goos
	switch goos {
	case "darwin":
		nixOS = "darwin"
	case "linux":
		nixOS = "linux"
	}

	return nixArch + "-" + nixOS
}

// evalError wraps nix eval errors
type evalError struct {
	stderr string
}

func (e *evalError) Error() string {
	return e.stderr
}

// InvalidateConfigCache clears the config cache, forcing a refresh on next access
func InvalidateConfigCache() {
	globalConfigCache.mu.Lock()
	defer globalConfigCache.mu.Unlock()

	globalConfigCache.config = nil
	globalConfigCache.lastUpdated = time.Time{}
}
