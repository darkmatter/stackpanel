// nixpkgs_search.go provides package search and installed-package listing
// for the studio UI's package browser.
//
// Search uses `nix search nixpkgs --json`, which can be slow (~5s) but
// returns comprehensive results. Results are sorted by relevance:
// installed > exact match > prefix match > alphabetical.
package server

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/rs/zerolog/log"
)

// NixpkgsSearchRequest is the request body for searching nixpkgs
type NixpkgsSearchRequest struct {
	Query  string `json:"query"`
	Limit  int    `json:"limit,omitempty"`
	Offset int    `json:"offset,omitempty"`
}

// NixpkgsPackage represents a package from nixpkgs
type NixpkgsPackage struct {
	Name        string `json:"name"`
	AttrPath    string `json:"attr_path"`
	Version     string `json:"version"`
	Description string `json:"description"`
	Installed   bool   `json:"installed"`
	NixpkgsURL  string `json:"nixpkgs_url"` // Link to search.nixos.org
}

// NixpkgsPackageMeta represents detailed metadata for a package
type NixpkgsPackageMeta struct {
	Name        string   `json:"name"`
	AttrPath    string   `json:"attr_path"`
	Version     string   `json:"version"`
	Description string   `json:"description"`
	Homepage    string   `json:"homepage,omitempty"`
	Changelog   string   `json:"changelog,omitempty"`
	License     string   `json:"license,omitempty"`
	LicenseURL  string   `json:"license_url,omitempty"`
	Maintainers []string `json:"maintainers,omitempty"`
	Platforms   []string `json:"platforms,omitempty"`
	NixpkgsURL  string   `json:"nixpkgs_url"`
}

// NixpkgsSearchResponse is the response from the search endpoint
type NixpkgsSearchResponse struct {
	Packages []NixpkgsPackage `json:"packages"`
	Total    int              `json:"total"`
	Query    string           `json:"query"`
}

// nixSearchResult represents a package in nix search --json output
type nixSearchResult struct {
	Pname       string `json:"pname"`
	Version     string `json:"version"`
	Description string `json:"description"`
}

// handleNixpkgsSearch handles package search requests using nix search
func (s *Server) handleNixpkgsSearch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req NixpkgsSearchRequest

	if r.Method == http.MethodGet {
		// Parse from query parameters
		req.Query = r.URL.Query().Get("q")
		if limitStr := r.URL.Query().Get("limit"); limitStr != "" {
			if parsed, err := parseIntParam(limitStr); err == nil {
				req.Limit = parsed
			}
		}
		if offsetStr := r.URL.Query().Get("offset"); offsetStr != "" {
			if parsed, err := parseIntParam(offsetStr); err == nil {
				req.Offset = parsed
			}
		}
	} else {
		if err := s.readJSON(r.Body, &req); err != nil {
			s.writeAPIError(w, http.StatusBadRequest, err.Error())
			return
		}
	}

	req.Query = strings.TrimSpace(req.Query)
	if req.Query == "" {
		s.writeAPIError(w, http.StatusBadRequest, "query is required")
		return
	}

	// Default limit
	if req.Limit <= 0 {
		req.Limit = 20
	}
	if req.Limit > 100 {
		req.Limit = 100
	}

	// Check if executor is available
	if s.exec == nil {
		s.writeAPIError(w, http.StatusServiceUnavailable, "no project is open")
		return
	}

	// Get installed packages from config
	installedSet := s.getInstalledPackageSet()

	packages, total, err := s.searchWithNixSearch(req.Query, req.Limit, req.Offset, installedSet)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to search nixpkgs: "+err.Error())
		return
	}

	s.writeAPI(w, http.StatusOK, NixpkgsSearchResponse{
		Packages: packages,
		Total:    total,
		Query:    req.Query,
	})
}

// InstalledPackagesResponse is the response for the installed packages endpoint
type InstalledPackagesResponse struct {
	Packages []nixeval.InstalledPackage `json:"packages"`
	Count    int                        `json:"count"`
	Source   string                     `json:"source,omitempty"`
	Cached   bool                       `json:"cached,omitempty"`
}

// handleInstalledPackages returns the list of installed packages from devenv/stackpanel config
func (s *Server) handleInstalledPackages(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	limit := 0
	offset := 0
	forceRefresh := r.URL.Query().Get("refresh") == "true"

	if limitStr := r.URL.Query().Get("limit"); limitStr != "" {
		if parsed, err := parseIntParam(limitStr); err == nil {
			limit = parsed
		}
	}
	if offsetStr := r.URL.Query().Get("offset"); offsetStr != "" {
		if parsed, err := parseIntParam(offsetStr); err == nil {
			offset = parsed
		}
	}

	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()

	var packages []nixeval.InstalledPackage
	var source string
	var cached bool

	// Try FlakeWatcher first (preferred - has file watching and smart caching)
	if s.flakeWatcher != nil {
		if forceRefresh {
			s.flakeWatcher.InvalidatePackages()
		}

		flakePackages, err := s.flakeWatcher.GetPackages(ctx)
		if err == nil {
			packages = flakePackages
			_, _, cached = s.flakeWatcher.PackagesStatus()
			source = "flake_watcher"
		} else {
			log.Debug().Err(err).Msg("FlakeWatcher packages evaluation failed, falling back to legacy")
		}
	}

	// Fallback to legacy GetInstalledPackages if FlakeWatcher didn't work
	if packages == nil {
		opts := nixeval.GetInstalledPackagesOptions{
			ProjectRoot:    s.config.ProjectRoot,
			ConfigJSONPath: s.exec.GetEnv("STACKPANEL_CONFIG_JSON"),
		}
		var err error
		packages, err = nixeval.GetInstalledPackages(ctx, opts)
		if err != nil {
			// Fall back to empty list on error (config might not be available)
			s.writeAPI(w, http.StatusOK, InstalledPackagesResponse{
				Packages: []nixeval.InstalledPackage{},
				Count:    0,
				Source:   "error",
			})
			return
		}
		source = "legacy"
		cached = false
	}

	total := len(packages)
	if limit > 0 {
		if offset >= total {
			packages = []nixeval.InstalledPackage{}
		} else {
			endIdx := offset + limit
			if endIdx > total {
				endIdx = total
			}
			packages = packages[offset:endIdx]
		}
	}

	s.writeAPI(w, http.StatusOK, InstalledPackagesResponse{
		Packages: packages,
		Count:    total,
		Source:   source,
		Cached:   cached,
	})
}

// handleNixpkgsPackageMeta returns detailed metadata for a single package
func (s *Server) handleNixpkgsPackageMeta(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	attrPath := r.URL.Query().Get("attr")
	if attrPath == "" {
		s.writeAPIError(w, http.StatusBadRequest, "attr query parameter is required")
		return
	}

	// Check if executor is available
	if s.exec == nil {
		s.writeAPIError(w, http.StatusServiceUnavailable, "no project is open")
		return
	}

	// Evaluate the package meta
	// Use nix eval 'nixpkgs#<attr>.meta' to get metadata
	res, err := s.exec.RunNix("eval", "nixpkgs#"+attrPath+".meta", "--json")
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to evaluate package meta: "+err.Error())
		return
	}

	if res.ExitCode != 0 {
		s.writeAPIError(w, http.StatusNotFound, "package not found: "+attrPath)
		return
	}

	// Parse the meta JSON
	var meta struct {
		Description string `json:"description"`
		Homepage    string `json:"homepage"`
		Changelog   string `json:"changelog"`
		License     struct {
			FullName string `json:"fullName"`
			URL      string `json:"url"`
		} `json:"license"`
		Maintainers []struct {
			Name   string `json:"name"`
			GitHub string `json:"github"`
		} `json:"maintainers"`
		Platforms []string `json:"platforms"`
	}

	if err := json.Unmarshal([]byte(res.Stdout), &meta); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse package meta: "+err.Error())
		return
	}

	// Also get the version from the package
	verRes, _ := s.exec.RunNix("eval", "nixpkgs#"+attrPath+".version", "--json")
	version := ""
	if verRes != nil && verRes.ExitCode == 0 {
		// Remove quotes from the version string
		version = strings.Trim(strings.TrimSpace(verRes.Stdout), "\"")
	}

	// Also get the pname
	pnameRes, _ := s.exec.RunNix("eval", "nixpkgs#"+attrPath+".pname", "--json")
	pname := attrPath
	if pnameRes != nil && pnameRes.ExitCode == 0 {
		pname = strings.Trim(strings.TrimSpace(pnameRes.Stdout), "\"")
	}

	// Build maintainers list
	maintainers := make([]string, 0, len(meta.Maintainers))
	for _, m := range meta.Maintainers {
		if m.GitHub != "" {
			maintainers = append(maintainers, m.GitHub)
		} else if m.Name != "" {
			maintainers = append(maintainers, m.Name)
		}
	}

	s.writeAPI(w, http.StatusOK, NixpkgsPackageMeta{
		Name:        pname,
		AttrPath:    attrPath,
		Version:     version,
		Description: meta.Description,
		Homepage:    meta.Homepage,
		Changelog:   meta.Changelog,
		License:     meta.License.FullName,
		LicenseURL:  meta.License.URL,
		Maintainers: maintainers,
		Platforms:   meta.Platforms,
		NixpkgsURL:  nixpkgsSearchURL(attrPath),
	})
}

// getInstalledPackageSet returns a set of installed package names for fast lookup
func (s *Server) getInstalledPackageSet() map[string]bool {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	opts := nixeval.GetInstalledPackagesOptions{
		ProjectRoot:    s.config.ProjectRoot,
		ConfigJSONPath: s.exec.GetEnv("STACKPANEL_CONFIG_JSON"),
	}
	nameSet, err := nixeval.GetInstalledPackageNames(ctx, opts)
	if err != nil {
		// Fall back to empty set on error
		return make(map[string]bool)
	}

	return nameSet
}

// searchWithNixSearch shells out to `nix search nixpkgs --json` and post-processes
// the results: stripping the "legacyPackages.<system>." prefix from attr paths,
// marking installed packages, and sorting by relevance.
func (s *Server) searchWithNixSearch(query string, limit, offset int, installedSet map[string]bool) ([]NixpkgsPackage, int, error) {
	// Run nix search with JSON output
	res, err := s.exec.RunNix("search", "nixpkgs", query, "--json")
	if err != nil {
		return nil, 0, err
	}

	if res.ExitCode != 0 {
		stderr := strings.TrimSpace(res.Stderr)
		if stderr != "" {
			return nil, 0, &searchError{message: stderr}
		}
		return []NixpkgsPackage{}, 0, nil
	}

	stdout := strings.TrimSpace(res.Stdout)
	if stdout == "" || stdout == "{}" || stdout == "null" {
		return []NixpkgsPackage{}, 0, nil
	}

	// Parse JSON output
	var searchResults map[string]nixSearchResult
	if err := json.Unmarshal([]byte(stdout), &searchResults); err != nil {
		return nil, 0, &searchError{message: "failed to parse nix search output: " + err.Error()}
	}

	// Convert to our package format
	allPackages := make([]NixpkgsPackage, 0, len(searchResults))
	for attrPath, pkg := range searchResults {
		// Extract just the package name from the full attr path
		parts := strings.Split(attrPath, ".")
		shortAttr := attrPath
		if len(parts) >= 3 {
			shortAttr = strings.Join(parts[2:], ".")
		}

		// Check if installed (match by pname or attr path)
		installed := installedSet[strings.ToLower(pkg.Pname)] ||
			installedSet[strings.ToLower(shortAttr)]

		allPackages = append(allPackages, NixpkgsPackage{
			Name:        pkg.Pname,
			AttrPath:    shortAttr,
			Version:     pkg.Version,
			Description: pkg.Description,
			Installed:   installed,
			NixpkgsURL:  nixpkgsSearchURL(shortAttr),
		})
	}

	// Sort by relevance (installed first, then exact matches, then by name)
	queryLower := strings.ToLower(query)
	sort.Slice(allPackages, func(i, j int) bool {
		// Installed packages come first
		if allPackages[i].Installed != allPackages[j].Installed {
			return allPackages[i].Installed
		}

		iName := strings.ToLower(allPackages[i].Name)
		jName := strings.ToLower(allPackages[j].Name)

		// Exact match comes next
		iExact := iName == queryLower
		jExact := jName == queryLower
		if iExact != jExact {
			return iExact
		}

		// Starts with query
		iPrefix := strings.HasPrefix(iName, queryLower)
		jPrefix := strings.HasPrefix(jName, queryLower)
		if iPrefix != jPrefix {
			return iPrefix
		}

		// Alphabetical
		return iName < jName
	})

	total := len(allPackages)

	// Apply pagination
	if offset >= len(allPackages) {
		return []NixpkgsPackage{}, total, nil
	}

	endIdx := offset + limit
	if endIdx > len(allPackages) {
		endIdx = len(allPackages)
	}

	return allPackages[offset:endIdx], total, nil
}

// parseIntParam parses an integer from a string parameter
func parseIntParam(s string) (int, error) {
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0, &searchError{message: "invalid integer"}
		}
		n = n*10 + int(c-'0')
	}
	return n, nil
}

// npsNotInstalledError indicates that nps is not installed
type npsNotInstalledError struct{}

func (e *npsNotInstalledError) Error() string {
	return "nps is not installed. Add 'pkgs.nps' to your devenv.nix packages to enable package search."
}

// searchError wraps search errors
type searchError struct {
	message string
}

func (e *searchError) Error() string {
	return e.message
}

// nixpkgsSearchURL returns a link to the package on search.nixos.org
func nixpkgsSearchURL(attrPath string) string {
	return "https://search.nixos.org/packages?channel=unstable&show=" + attrPath
}
