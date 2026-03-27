// registry.go implements the module registry: browsing, searching, and installing
// external Stackpanel modules from a remote JSON registry.
//
// Installation uses tree-sitter (via flakeedit) to parse and modify flake.nix,
// adding the required flake input and stackpanelImports entry. If auto-editing
// fails, a fallback returns code snippets for manual installation.
//
// When the registry is unreachable, sample/builtin modules are returned so the
// UI always has something to display.
package server

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/rs/zerolog/log"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
)

// Default registry URL - can be overridden via config
const DefaultRegistryURL = "https://raw.githubusercontent.com/darkmatter/stackpanel-registry/main/modules.json"

// RegistryModule represents a module available in the registry
type RegistryModule struct {
	ID             string         `json:"id"`
	Meta           ModuleMeta     `json:"meta"`
	Features       ModuleFeatures `json:"features"`
	Requires       []string       `json:"requires,omitempty"`
	Conflicts      []string       `json:"conflicts,omitempty"`
	Tags           []string       `json:"tags,omitempty"`
	FlakeURL       string         `json:"flakeUrl"`
	FlakePath      string         `json:"flakePath,omitempty"`
	Ref            string         `json:"ref,omitempty"`
	Downloads      int            `json:"downloads,omitempty"`
	Rating         float64        `json:"rating,omitempty"`
	UpdatedAt      string         `json:"updatedAt,omitempty"`
	Installed      bool           `json:"installed,omitempty"`      // True if module is active in Nix config
	PendingInstall bool           `json:"pendingInstall,omitempty"` // True if enabled but requires devshell re-entry
	Builtin        bool           `json:"builtin,omitempty"`        // True for modules that are built into stackpanel
}

// RegistrySource represents a module registry source
type RegistrySource struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	URL      string `json:"url"`
	Official bool   `json:"official,omitempty"`
	Enabled  bool   `json:"enabled"`
}

// RegistryManifest is the format of the registry JSON file
type RegistryManifest struct {
	Version     int              `json:"version"`
	Name        string           `json:"name"`
	Description string           `json:"description,omitempty"`
	Modules     []RegistryModule `json:"modules"`
	UpdatedAt   string           `json:"updatedAt"`
}

// RegistryModulesResponse is the API response for registry modules
type RegistryModulesResponse struct {
	Modules     []RegistryModule `json:"modules"`
	Total       int              `json:"total"`
	Sources     []RegistrySource `json:"sources"`
	LastUpdated string           `json:"lastUpdated"`
}

// InstallModuleRequest is the request to install a module
type InstallModuleRequest struct {
	ModuleID  string `json:"moduleId"`
	FlakeURL  string `json:"flakeUrl"`
	FlakePath string `json:"flakePath,omitempty"`
	Ref       string `json:"ref,omitempty"`
}

// InstallModuleResponse is the response from installing a module
type InstallModuleResponse struct {
	Success            bool   `json:"success"`
	Message            string `json:"message"`
	InputAdded         bool   `json:"inputAdded,omitempty"`
	ImportAdded        bool   `json:"importAdded,omitempty"`
	InputAlreadyExists bool   `json:"inputAlreadyExists,omitempty"`
	LockUpdated        bool   `json:"lockUpdated,omitempty"`
	// Legacy fields — returned when auto-edit fails and the user must edit manually
	FlakeInputCode   string `json:"flakeInputCode,omitempty"`
	ModuleImportCode string `json:"moduleImportCode,omitempty"`
}

// handleRegistry routes registry-related API requests
func (s *Server) handleRegistry(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/registry")
	path = strings.TrimPrefix(path, "/")

	parts := strings.Split(path, "/")

	switch {
	case path == "" || path == "modules" || path == "modules/":
		// List registry modules
		s.handleRegistryModules(w, r)
	case len(parts) == 2 && parts[0] == "modules" && parts[1] == "install":
		// Install a module
		s.handleRegistryInstall(w, r)
	default:
		s.writeAPIError(w, http.StatusNotFound, "endpoint not found")
	}
}

// handleRegistryModules returns modules available in the registry
func (s *Server) handleRegistryModules(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	category := r.URL.Query().Get("category")
	search := r.URL.Query().Get("search")

	// Get registry sources (for now just use default)
	sources := []RegistrySource{
		{
			ID:       "official",
			Name:     "Stackpanel Official",
			URL:      DefaultRegistryURL,
			Official: true,
			Enabled:  true,
		},
	}

	// Fetch modules from all enabled registries
	var allModules []RegistryModule
	for _, source := range sources {
		if !source.Enabled {
			continue
		}

		modules, err := s.fetchRegistryModules(source.URL)
		if err != nil {
			log.Warn().Str("source", source.Name).Err(err).Msg("Failed to fetch registry modules")
			continue
		}
		allModules = append(allModules, modules...)
	}

	// If registry fetch failed or is empty, provide sample modules
	if len(allModules) == 0 {
		allModules = getSampleRegistryModules()
	}

	// Get installed modules to mark which are already installed
	installedModules, _ := s.getModules(true)
	installedSet := make(map[string]bool)
	for _, m := range installedModules {
		installedSet[m.ID] = true
	}

	// Also check pending enables from data files (not yet in Nix config)
	pendingEnables := s.getPendingModuleEnables()
	for moduleID := range pendingEnables {
		installedSet[moduleID] = true
	}

	// Mark installed modules and filter
	var filteredModules []RegistryModule
	for _, m := range allModules {
		m.Installed = installedSet[m.ID]

		// Filter by category
		if category != "" && m.Meta.Category != category {
			continue
		}

		// Filter by search
		if search != "" {
			searchLower := strings.ToLower(search)
			if !strings.Contains(strings.ToLower(m.ID), searchLower) &&
				!strings.Contains(strings.ToLower(m.Meta.Name), searchLower) &&
				(m.Meta.Description == nil || !strings.Contains(strings.ToLower(*m.Meta.Description), searchLower)) {
				continue
			}
		}

		filteredModules = append(filteredModules, m)
	}

	// Sort by downloads (popularity)
	sort.Slice(filteredModules, func(i, j int) bool {
		return filteredModules[i].Downloads > filteredModules[j].Downloads
	})

	s.writeAPI(w, http.StatusOK, RegistryModulesResponse{
		Modules:     filteredModules,
		Total:       len(filteredModules),
		Sources:     sources,
		LastUpdated: time.Now().Format(time.RFC3339),
	})
}

// handleRegistryInstall installs a module by editing flake.nix with tree-sitter.
// On success it also runs `nix flake lock --update-input` to fetch the new input.
// If any step fails, the original flake.nix is restored from a backup.
func (s *Server) handleRegistryInstall(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var request InstallModuleRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		s.writeAPIError(w, http.StatusBadRequest, "invalid JSON: "+err.Error())
		return
	}

	if request.ModuleID == "" || request.FlakeURL == "" {
		s.writeAPIError(w, http.StatusBadRequest, "moduleId and flakeUrl are required")
		return
	}

	// Skip auto-install for builtin modules
	if request.FlakeURL == "builtin" {
		s.writeAPI(w, http.StatusOK, InstallModuleResponse{
			Success: true,
			Message: fmt.Sprintf("Module %s is builtin — enable it in your stackpanel config", request.ModuleID),
		})
		return
	}

	inputName := sanitizeFlakeInputName(request.ModuleID)
	flakePath := request.FlakePath
	if flakePath == "" {
		flakePath = "stackpanelModules.default"
	}

	// Determine project root
	projectRoot := s.config.ProjectRoot
	if projectRoot == "" {
		s.handleRegistryInstallFallback(w, request, inputName, flakePath)
		return
	}

	flakeNixPath := filepath.Join(projectRoot, "flake.nix")

	// Read flake.nix
	source, err := os.ReadFile(flakeNixPath)
	if err != nil {
		log.Warn().Err(err).Str("path", flakeNixPath).Msg("Could not read flake.nix, falling back to manual install")
		s.handleRegistryInstallFallback(w, request, inputName, flakePath)
		return
	}

	// Parse with tree-sitter
	editor, err := flakeedit.NewFlakeEditor(source)
	if err != nil {
		log.Warn().Err(err).Msg("Could not parse flake.nix, falling back to manual install")
		s.handleRegistryInstallFallback(w, request, inputName, flakePath)
		return
	}
	defer editor.Close()

	// Build the import expression
	importExpr := fmt.Sprintf("inputs.%s.%s", inputName, flakePath)

	// Perform the edit
	editResult, err := editor.AddInputAndImport(
		flakeedit.FlakeInput{
			Name:           inputName,
			URL:            request.FlakeURL,
			FollowsNixpkgs: true,
		},
		importExpr,
	)
	if err != nil {
		log.Warn().Err(err).Msg("Failed to edit flake.nix, falling back to manual install")
		s.handleRegistryInstallFallback(w, request, inputName, flakePath)
		return
	}

	// Write backup
	backupPath := flakeNixPath + ".bak"
	if err := os.WriteFile(backupPath, source, 0o644); err != nil {
		log.Warn().Err(err).Msg("Could not write flake.nix backup")
	}

	// Write modified flake.nix
	if err := os.WriteFile(flakeNixPath, editResult.Modified, 0o644); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("failed to write flake.nix: %v", err))
		return
	}

	// Lock the new input
	lockUpdated := false
	if editResult.InputAdded {
		lockCmd := exec.Command("nix", "flake", "lock", "--update-input", inputName)
		lockCmd.Dir = projectRoot
		if lockErr := lockCmd.Run(); lockErr != nil {
			log.Warn().Err(lockErr).Str("input", inputName).Msg("nix flake lock failed, rolling back")
			// Rollback
			if rbErr := os.WriteFile(flakeNixPath, source, 0o644); rbErr != nil {
				log.Error().Err(rbErr).Msg("Failed to rollback flake.nix")
			}
			s.writeAPIError(w, http.StatusInternalServerError, fmt.Sprintf("nix flake lock failed for input %s: %v", inputName, lockErr))
			return
		}
		lockUpdated = true
	}

	// Clean up backup on success
	os.Remove(backupPath)

	// Broadcast SSE event
	s.broadcastSSE(SSEEvent{
		Event: "module.installed",
		Data: map[string]any{
			"moduleId":           request.ModuleID,
			"flakeUrl":           request.FlakeURL,
			"flakePath":          flakePath,
			"inputAdded":         editResult.InputAdded,
			"importAdded":        editResult.ImportAdded,
			"inputAlreadyExists": editResult.InputAlreadyExists,
			"lockUpdated":        lockUpdated,
		},
	})

	message := fmt.Sprintf("Module %s installed successfully", request.ModuleID)
	if editResult.InputAlreadyExists {
		message = fmt.Sprintf("Input %s already exists; added module import", inputName)
	}

	s.writeAPI(w, http.StatusOK, InstallModuleResponse{
		Success:            true,
		Message:            message,
		InputAdded:         editResult.InputAdded,
		ImportAdded:        editResult.ImportAdded,
		InputAlreadyExists: editResult.InputAlreadyExists,
		LockUpdated:        lockUpdated,
	})
}

// handleRegistryInstallFallback returns code snippets for manual installation
// when auto-editing is not possible (no project root, parse failure, etc.).
func (s *Server) handleRegistryInstallFallback(w http.ResponseWriter, request InstallModuleRequest, inputName, flakePath string) {
	flakeInputCode := fmt.Sprintf(`    %s.url = "%s";
    %s.inputs.nixpkgs.follows = "nixpkgs";`, inputName, request.FlakeURL, inputName)

	moduleImportCode := fmt.Sprintf(`    inputs.%s.%s`, inputName, flakePath)

	s.broadcastSSE(SSEEvent{
		Event: "module.install.manual",
		Data: map[string]any{
			"moduleId":  request.ModuleID,
			"flakeUrl":  request.FlakeURL,
			"flakePath": flakePath,
		},
	})

	s.writeAPI(w, http.StatusOK, InstallModuleResponse{
		Success:          true,
		Message:          fmt.Sprintf("Auto-install not available. To install %s, add the following to your flake.nix:", request.ModuleID),
		FlakeInputCode:   flakeInputCode,
		ModuleImportCode: moduleImportCode,
	})
}

// fetchRegistryModules fetches modules from a registry URL
func (s *Server) fetchRegistryModules(url string) ([]RegistryModule, error) {
	client := &http.Client{Timeout: 10 * time.Second}

	resp, err := client.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch registry: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("registry returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var manifest RegistryManifest
	if err := json.Unmarshal(body, &manifest); err != nil {
		return nil, fmt.Errorf("failed to parse registry manifest: %w", err)
	}

	return manifest.Modules, nil
}

// sanitizeFlakeInputName converts a module ID to a valid flake input name
func sanitizeFlakeInputName(moduleID string) string {
	// Replace invalid characters with underscores
	name := strings.ReplaceAll(moduleID, "-", "_")
	name = strings.ReplaceAll(name, ".", "_")
	return name
}

// getSampleRegistryModules returns sample modules when registry is unavailable
func getSampleRegistryModules() []RegistryModule {
	// Built-in module descriptions
	oxlintDesc := "Blazing fast JavaScript/TypeScript linter written in Rust. Supports React, TypeScript, and more."
	goDesc := "Go application support with air live reload, gomod2nix, and automatic file generation."
	gitHooksDesc := "Git hooks integration with pre-commit linting and formatting support."
	turboDesc := "Turborepo task integration for monorepo build orchestration."

	// External module descriptions
	sampleDesc1 := "Production-ready PostgreSQL with replication, backups, and monitoring"
	sampleDesc2 := "Redis cluster with high availability and automatic failover"
	sampleDesc3 := "S3-compatible object storage for local development"
	sampleDesc4 := "Full observability stack with Prometheus, Grafana, and Loki"
	sampleDesc5 := "Automated SSL certificates with Let's Encrypt"
	sampleAuthor := "Stackpanel Team"

	return []RegistryModule{
		// Built-in modules (already available, just need to enable)
		{
			ID: "oxlint",
			Meta: ModuleMeta{
				Name:        "OxLint",
				Description: &oxlintDesc,
				Category:    "development",
				Author:      &sampleAuthor,
				Version:     strPtr("1.0.0"),
				Icon:        strPtr("search-code"),
				Homepage:    strPtr("https://oxc.rs"),
			},
			Features: ModuleFeatures{
				Files:        true,
				Scripts:      true,
				Healthchecks: true,
				Packages:     true,
			},
			Tags:      []string{"linting", "javascript", "typescript", "react", "rust", "oxc"},
			FlakeURL:  "builtin",
			FlakePath: "stackpanel.apps.<app>.linting.oxlint.enable = true",
			Downloads: 5000,
			Rating:    4.9,
			UpdatedAt: "2024-01-22T10:00:00Z",
			Builtin:   true,
		},
		{
			ID: "go",
			Meta: ModuleMeta{
				Name:        "Go Support",
				Description: &goDesc,
				Category:    "development",
				Author:      &sampleAuthor,
				Version:     strPtr("1.0.0"),
				Icon:        strPtr("code"),
			},
			Features: ModuleFeatures{
				Files:        true,
				Scripts:      true,
				Healthchecks: true,
				Packages:     true,
			},
			Tags:      []string{"go", "golang", "air", "live-reload", "gomod2nix"},
			FlakeURL:  "builtin",
			FlakePath: "stackpanel.apps.<app>.go.enable = true",
			Downloads: 3500,
			Rating:    4.8,
			UpdatedAt: "2024-01-20T10:00:00Z",
			Builtin:   true,
		},
		{
			ID: "git-hooks",
			Meta: ModuleMeta{
				Name:        "Git Hooks",
				Description: &gitHooksDesc,
				Category:    "development",
				Author:      &sampleAuthor,
				Version:     strPtr("1.0.0"),
				Icon:        strPtr("git-branch"),
			},
			Features: ModuleFeatures{
				Scripts: true,
			},
			Tags:      []string{"git", "hooks", "pre-commit", "linting", "formatting"},
			FlakeURL:  "builtin",
			FlakePath: "stackpanel.git-hooks.enable = true",
			Downloads: 4200,
			Rating:    4.7,
			UpdatedAt: "2024-01-18T10:00:00Z",
			Builtin:   true,
		},
		{
			ID: "turbo",
			Meta: ModuleMeta{
				Name:        "Turborepo",
				Description: &turboDesc,
				Category:    "development",
				Author:      &sampleAuthor,
				Version:     strPtr("1.0.0"),
				Icon:        strPtr("zap"),
			},
			Features: ModuleFeatures{
				Files:   true,
				Scripts: true,
				Tasks:   true,
			},
			Tags:      []string{"turbo", "turborepo", "monorepo", "build", "tasks"},
			FlakeURL:  "builtin",
			FlakePath: "stackpanel.turbo.enable = true",
			Downloads: 3800,
			Rating:    4.6,
			UpdatedAt: "2024-01-19T10:00:00Z",
			Builtin:   true,
		},
		// External/installable modules
		{
			ID: "postgres-ha",
			Meta: ModuleMeta{
				Name:        "PostgreSQL HA",
				Description: &sampleDesc1,
				Category:    "database",
				Author:      &sampleAuthor,
				Version:     strPtr("1.2.0"),
			},
			Features: ModuleFeatures{
				Services:     true,
				Healthchecks: true,
				Secrets:      true,
			},
			Tags:      []string{"database", "postgres", "ha", "production"},
			FlakeURL:  "github:stackpanel/modules",
			FlakePath: "stackpanelModules.postgres-ha",
			Downloads: 1250,
			Rating:    4.8,
			UpdatedAt: "2024-01-15T10:00:00Z",
		},
		{
			ID: "redis-cluster",
			Meta: ModuleMeta{
				Name:        "Redis Cluster",
				Description: &sampleDesc2,
				Category:    "database",
				Author:      &sampleAuthor,
				Version:     strPtr("1.0.0"),
			},
			Features: ModuleFeatures{
				Services:     true,
				Healthchecks: true,
			},
			Tags:      []string{"database", "redis", "cache", "cluster"},
			FlakeURL:  "github:stackpanel/modules",
			FlakePath: "stackpanelModules.redis-cluster",
			Downloads: 890,
			Rating:    4.5,
			UpdatedAt: "2024-01-10T10:00:00Z",
		},
		{
			ID: "minio-server",
			Meta: ModuleMeta{
				Name:        "MinIO Server",
				Description: &sampleDesc3,
				Category:    "infrastructure",
				Author:      &sampleAuthor,
				Version:     strPtr("1.1.0"),
			},
			Features: ModuleFeatures{
				Services:     true,
				Healthchecks: true,
				Files:        true,
			},
			Tags:      []string{"storage", "s3", "minio", "object-storage"},
			FlakeURL:  "github:stackpanel/modules",
			FlakePath: "stackpanelModules.minio",
			Downloads: 670,
			Rating:    4.3,
			UpdatedAt: "2024-01-08T10:00:00Z",
		},
		{
			ID: "observability",
			Meta: ModuleMeta{
				Name:        "Observability Stack",
				Description: &sampleDesc4,
				Category:    "monitoring",
				Author:      &sampleAuthor,
				Version:     strPtr("2.0.0"),
			},
			Features: ModuleFeatures{
				Services:     true,
				Healthchecks: true,
				Files:        true,
				Packages:     true,
			},
			Tags:      []string{"monitoring", "prometheus", "grafana", "loki", "metrics"},
			FlakeURL:  "github:stackpanel/modules",
			FlakePath: "stackpanelModules.observability",
			Downloads: 2100,
			Rating:    4.9,
			UpdatedAt: "2024-01-20T10:00:00Z",
		},
		{
			ID: "acme-certs",
			Meta: ModuleMeta{
				Name:        "ACME Certificates",
				Description: &sampleDesc5,
				Category:    "infrastructure",
				Author:      &sampleAuthor,
				Version:     strPtr("1.0.0"),
			},
			Features: ModuleFeatures{
				Scripts:      true,
				Healthchecks: true,
				Secrets:      true,
			},
			Tags:      []string{"ssl", "tls", "certificates", "letsencrypt"},
			FlakeURL:  "github:stackpanel/modules",
			FlakePath: "stackpanelModules.acme",
			Downloads: 450,
			Rating:    4.2,
			UpdatedAt: "2024-01-05T10:00:00Z",
		},
	}
}

// Helper to create string pointer
func strPtr(s string) *string {
	return &s
}
