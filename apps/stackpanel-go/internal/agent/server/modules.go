package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// Module represents a Stackpanel module from Nix config
type Module struct {
	ID           string         `json:"id"`
	Enabled      bool           `json:"enabled"`
	Meta         ModuleMeta     `json:"meta"`
	Source       ModuleSource   `json:"source"`
	Features     ModuleFeatures `json:"features"`
	Requires     []string       `json:"requires,omitempty"`
	Conflicts    []string       `json:"conflicts,omitempty"`
	Priority     int            `json:"priority"`
	Tags         []string       `json:"tags,omitempty"`
	ConfigSchema *string        `json:"configSchema,omitempty"`
	Panels       []ModulePanel  `json:"panels,omitempty"`
	Apps         map[string]any `json:"apps,omitempty"`
	HealthModule *string        `json:"healthcheckModule,omitempty"`
	Health       *ModuleHealth  `json:"health,omitempty"`
}

// ModuleMeta contains display metadata for a module
type ModuleMeta struct {
	Name        string  `json:"name"`
	Description *string `json:"description,omitempty"`
	Icon        *string `json:"icon,omitempty"`
	Category    string  `json:"category"`
	Author      *string `json:"author,omitempty"`
	Version     *string `json:"version,omitempty"`
	Homepage    *string `json:"homepage,omitempty"`
}

// ModuleSource describes where a module comes from
type ModuleSource struct {
	Type       string  `json:"type"` // builtin, local, flake-input, registry
	FlakeInput *string `json:"flakeInput,omitempty"`
	Path       *string `json:"path,omitempty"`
	RegistryID *string `json:"registryId,omitempty"`
	Ref        *string `json:"ref,omitempty"`
}

// ModuleFeatures describes which stackpanel features a module uses
type ModuleFeatures struct {
	Files        bool `json:"files"`
	Scripts      bool `json:"scripts"`
	Tasks        bool `json:"tasks"`
	Healthchecks bool `json:"healthchecks"`
	Services     bool `json:"services"`
	Secrets      bool `json:"secrets"`
	Packages     bool `json:"packages"`
	AppModule    bool `json:"appModule"`
}

// ModulePanel represents a UI panel provided by a module
type ModulePanel struct {
	ID          string       `json:"id"`
	Title       string       `json:"title"`
	Description *string      `json:"description,omitempty"`
	Type        string       `json:"type"`
	Order       int          `json:"order"`
	Fields      []PanelField `json:"fields,omitempty"`
}

// PanelField represents a field in a module panel
type PanelField struct {
	Name    string   `json:"name"`
	Type    string   `json:"type"`
	Value   string   `json:"value"`
	Options []string `json:"options,omitempty"`
}

// ModulesResponse is the response for the modules list endpoint
type ModulesResponse struct {
	Modules     []Module `json:"modules"`
	Total       int      `json:"total"`
	Enabled     int      `json:"enabled"`
	LastUpdated string   `json:"lastUpdated"`
}

// ModuleConfig represents stored configuration for a module
type ModuleConfig struct {
	Enable   *bool          `yaml:"enable,omitempty" json:"enable,omitempty"`
	Settings map[string]any `yaml:"settings,omitempty" json:"settings,omitempty"`
}

// handleModules routes module-related API requests
func (s *Server) handleModules(w http.ResponseWriter, r *http.Request) {
	// Extract module name from path if present
	// /api/modules -> list all
	// /api/modules/postgres -> single module
	// /api/modules/postgres/config -> module config
	// /api/modules/postgres/enable -> enable/disable module

	path := strings.TrimPrefix(r.URL.Path, "/api/modules")
	path = strings.TrimPrefix(path, "/")

	parts := strings.Split(path, "/")

	switch {
	case path == "" || path == "/":
		// List all modules
		s.handleModulesList(w, r)
	case len(parts) == 1:
		// Single module: /api/modules/{name}
		s.handleModuleGet(w, r, parts[0])
	case len(parts) == 2 && parts[1] == "config":
		// Module config: /api/modules/{name}/config
		s.handleModuleConfig(w, r, parts[0])
	case len(parts) == 2 && parts[1] == "enable":
		// Enable/disable: /api/modules/{name}/enable
		s.handleModuleEnable(w, r, parts[0])
	default:
		s.writeAPIError(w, http.StatusNotFound, "endpoint not found")
	}
}

// handleModulesList returns all modules
func (s *Server) handleModulesList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	includeHealth := r.URL.Query().Get("includeHealth") == "true"
	includeDisabled := r.URL.Query().Get("includeDisabled") == "true"
	category := r.URL.Query().Get("category")

	modules, err := s.getModules(includeDisabled)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to get modules: "+err.Error())
		return
	}

	// Filter by category if specified
	if category != "" {
		var filtered []Module
		for _, m := range modules {
			if m.Meta.Category == category {
				filtered = append(filtered, m)
			}
		}
		modules = filtered
	}

	// Optionally include health status
	if includeHealth {
		modules = s.hydrateModulesWithHealth(r.Context(), modules)
	}

	enabledCount := 0
	for _, m := range modules {
		if m.Enabled {
			enabledCount++
		}
	}

	s.writeAPI(w, http.StatusOK, ModulesResponse{
		Modules:     modules,
		Total:       len(modules),
		Enabled:     enabledCount,
		LastUpdated: time.Now().Format(time.RFC3339),
	})
}

// handleModuleGet returns a single module by name
func (s *Server) handleModuleGet(w http.ResponseWriter, r *http.Request, name string) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	includeHealth := r.URL.Query().Get("includeHealth") == "true"

	modules, err := s.getModules(true) // Include disabled to find the module
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to get modules: "+err.Error())
		return
	}

	var module *Module
	for i := range modules {
		if modules[i].ID == name {
			module = &modules[i]
			break
		}
	}

	if module == nil {
		s.writeAPIError(w, http.StatusNotFound, "module not found: "+name)
		return
	}

	// Optionally include health status
	if includeHealth && module.HealthModule != nil {
		health := s.getModuleHealth(r.Context(), *module.HealthModule)
		module.Health = health
	}

	// Include stored config
	config, _ := s.loadModuleConfig(name)

	response := map[string]any{
		"module": module,
		"config": config,
	}

	s.writeAPI(w, http.StatusOK, response)
}

// handleModuleConfig handles reading and writing module configuration
func (s *Server) handleModuleConfig(w http.ResponseWriter, r *http.Request, name string) {
	switch r.Method {
	case http.MethodGet:
		config, err := s.loadModuleConfig(name)
		if err != nil {
			if os.IsNotExist(err) {
				// Return empty config if file doesn't exist
				s.writeAPI(w, http.StatusOK, ModuleConfig{})
				return
			}
			s.writeAPIError(w, http.StatusInternalServerError, "failed to load config: "+err.Error())
			return
		}
		s.writeAPI(w, http.StatusOK, config)

	case http.MethodPost, http.MethodPut:
		var config ModuleConfig
		if err := json.NewDecoder(r.Body).Decode(&config); err != nil {
			s.writeAPIError(w, http.StatusBadRequest, "invalid JSON: "+err.Error())
			return
		}

		if err := s.saveModuleConfig(name, config); err != nil {
			s.writeAPIError(w, http.StatusInternalServerError, "failed to save config: "+err.Error())
			return
		}

		// Broadcast config change
		s.broadcastSSE(SSEEvent{
			Event: "module.config.updated",
			Data: map[string]any{
				"module": name,
				"config": config,
			},
		})

		s.writeAPI(w, http.StatusOK, map[string]any{
			"success": true,
			"message": "Configuration saved. Re-enter devshell to apply changes.",
		})

	default:
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// handleModuleEnable handles enabling/disabling a module
func (s *Server) handleModuleEnable(w http.ResponseWriter, r *http.Request, name string) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var request struct {
		Enable bool `json:"enable"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "invalid JSON: "+err.Error())
		return
	}

	// Load existing config
	config, err := s.loadModuleConfig(name)
	if err != nil && !os.IsNotExist(err) {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to load config: "+err.Error())
		return
	}

	// Update enable state
	config.Enable = &request.Enable

	if err := s.saveModuleConfig(name, config); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to save config: "+err.Error())
		return
	}

	// Broadcast enable change
	s.broadcastSSE(SSEEvent{
		Event: "module.enabled.changed",
		Data: map[string]any{
			"module":  name,
			"enabled": request.Enable,
		},
	})

	action := "enabled"
	if !request.Enable {
		action = "disabled"
	}

	s.writeAPI(w, http.StatusOK, map[string]any{
		"success": true,
		"message": fmt.Sprintf("Module %s. Re-enter devshell to apply changes.", action),
	})
}

// getModules retrieves module list from Nix config
func (s *Server) getModules(includeDisabled bool) ([]Module, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	var config map[string]any
	var err error

	// Try FlakeWatcher first
	if s.flakeWatcher != nil {
		config, err = s.flakeWatcher.GetConfig(ctx)
	}

	// Fallback to direct evaluation
	if config == nil || err != nil {
		config, err = s.evaluateConfig()
		if err != nil {
			return nil, err
		}
	}

	// Try to get modules from ui.modules or ui.modulesList
	ui, ok := config["ui"].(map[string]any)
	if !ok {
		log.Debug().Msg("No ui section in config")
		return []Module{}, nil
	}

	// Try modulesList first (flat list)
	var modules []Module
	if modulesList, ok := ui["modulesList"]; ok {
		data, err := json.Marshal(modulesList)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal modulesList: %w", err)
		}
		if err := json.Unmarshal(data, &modules); err != nil {
			return nil, fmt.Errorf("failed to unmarshal modulesList: %w", err)
		}
	} else if modulesMap, ok := ui["modules"].(map[string]any); ok {
		// Fall back to modules map
		for name, modData := range modulesMap {
			data, err := json.Marshal(modData)
			if err != nil {
				log.Warn().Str("module", name).Err(err).Msg("Failed to marshal module")
				continue
			}
			var module Module
			if err := json.Unmarshal(data, &module); err != nil {
				log.Warn().Str("module", name).Err(err).Msg("Failed to unmarshal module")
				continue
			}
			module.ID = name
			modules = append(modules, module)
		}
	}

	// Filter disabled if requested
	if !includeDisabled {
		var enabled []Module
		for _, m := range modules {
			if m.Enabled {
				enabled = append(enabled, m)
			}
		}
		modules = enabled
	}

	return modules, nil
}

// hydrateModulesWithHealth adds health information to modules
func (s *Server) hydrateModulesWithHealth(ctx context.Context, modules []Module) []Module {
	for i := range modules {
		if modules[i].HealthModule != nil {
			modules[i].Health = s.getModuleHealth(ctx, *modules[i].HealthModule)
		}
	}
	return modules
}

// getModuleHealth gets health status for a specific health module
func (s *Server) getModuleHealth(ctx context.Context, healthModule string) *ModuleHealth {
	healthchecks, err := s.getHealthcheckDefinitions()
	if err != nil {
		log.Warn().Err(err).Msg("Failed to get healthcheck definitions")
		return nil
	}

	// Filter to checks for this module
	var moduleChecks []Healthcheck
	for _, check := range healthchecks {
		if check.Module == healthModule && check.Enabled {
			moduleChecks = append(moduleChecks, check)
		}
	}

	if len(moduleChecks) == 0 {
		return nil
	}

	// Run checks (use cached results)
	var results []HealthcheckResult
	for _, check := range moduleChecks {
		result := s.getCachedResult(check.ID)
		if result == nil {
			result = s.runHealthcheck(ctx, check)
			s.cacheResult(result)
		}
		result.Check = &check
		results = append(results, *result)
	}

	// Build module health
	health := &ModuleHealth{
		Module:      healthModule,
		DisplayName: healthModule, // Will be overridden if we have better info
		Checks:      results,
		TotalCount:  len(results),
		LastUpdated: time.Now().Format(time.RFC3339),
	}

	// Count healthy and determine overall status
	health.Status = HealthStatusHealthy
	for _, r := range results {
		if r.Status == HealthStatusHealthy {
			health.HealthyCount++
		} else if r.Status == HealthStatusUnhealthy {
			health.Status = HealthStatusUnhealthy
		} else if r.Status == HealthStatusDegraded && health.Status != HealthStatusUnhealthy {
			health.Status = HealthStatusDegraded
		}
	}

	return health
}

// loadModuleConfig loads configuration for a module from disk
func (s *Server) loadModuleConfig(name string) (ModuleConfig, error) {
	configPath := s.moduleConfigPath(name)

	data, err := os.ReadFile(configPath)
	if err != nil {
		return ModuleConfig{}, err
	}

	var config ModuleConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return ModuleConfig{}, fmt.Errorf("failed to parse YAML: %w", err)
	}

	return config, nil
}

// saveModuleConfig saves configuration for a module to disk
func (s *Server) saveModuleConfig(name string, config ModuleConfig) error {
	configPath := s.moduleConfigPath(name)

	// Ensure directory exists
	dir := filepath.Dir(configPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	data, err := yaml.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal YAML: %w", err)
	}

	// Add header comment
	content := fmt.Sprintf("# Stackpanel module configuration for %s\n# This file is managed by the Stackpanel UI\n# Re-enter devshell to apply changes\n\n%s", name, string(data))

	if err := os.WriteFile(configPath, []byte(content), 0644); err != nil {
		return fmt.Errorf("failed to write config: %w", err)
	}

	return nil
}

// moduleConfigPath returns the path to a module's config file
func (s *Server) moduleConfigPath(name string) string {
	// Config stored in .stackpanel/data/modules/{name}.yaml
	return filepath.Join(s.config.ProjectRoot, ".stackpanel", "data", "modules", name+".yaml")
}
