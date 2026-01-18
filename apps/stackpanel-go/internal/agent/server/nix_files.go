package server

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/rs/zerolog/log"
)

// GeneratedFile represents metadata about a generated file
// Field names match proto schema (snake_case for JSON)
type GeneratedFile struct {
	Path        string  `json:"path"`
	Type        string  `json:"type"`
	Mode        *string `json:"mode,omitempty"`
	Source      *string `json:"source,omitempty"`
	Description *string `json:"description,omitempty"`
	StorePath   *string `json:"store_path,omitempty"`
	Text        *string `json:"text,omitempty"`
	Enable      bool    `json:"enable"`
	// Runtime status fields (added by agent, not from proto)
	ExistsOnDisk bool    `json:"existsOnDisk"`
	IsStale      bool    `json:"isStale"`
	Size         *int64  `json:"size,omitempty"`
	ContentHash  *string `json:"contentHash,omitempty"`
}

// GeneratedFilesResponse is the response for /api/nix/files
type GeneratedFilesResponse struct {
	Files        []GeneratedFile `json:"files"`
	TotalCount   int             `json:"totalCount"`
	StaleCount   int             `json:"staleCount"`
	EnabledCount int             `json:"enabledCount"`
	LastUpdated  string          `json:"lastUpdated"`
}

// nixFilesOutput is the parsed result from evaluating stackpanel.files
type nixFilesOutput struct {
	Enable  bool                    `json:"enable"`
	Entries map[string]nixFileEntry `json:"entries"`
}

type nixFileEntry struct {
	Path        string  `json:"path"`
	Type        string  `json:"type"`
	Mode        *string `json:"mode"`
	Source      *string `json:"source"`
	Description *string `json:"description"`
	Enable      bool    `json:"enable"`
	StorePath   *string `json:"store_path"`
	Text        *string `json:"text"`
}

// handleNixFiles returns metadata about generated files from stackpanel.files.entries
// GET /api/nix/files
func (s *Server) handleNixFiles(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Evaluate stackpanel.files from the user's config
	filesData, err := s.evaluateStackpanelFiles()
	if err != nil {
		log.Error().Err(err).Msg("Failed to evaluate stackpanel files")
		s.writeAPIError(w, http.StatusInternalServerError, "failed to evaluate files config: "+err.Error())
		return
	}

	// Build the response with disk status
	response := s.buildFilesResponse(filesData)

	s.writeAPI(w, http.StatusOK, response)
}

// evaluateStackpanelFiles evaluates stackpanel.files from the user's flake config
// by running a nix expression that extracts serializable metadata
func (s *Server) evaluateStackpanelFiles() (*nixFilesOutput, error) {
	// Nix expression that tries multiple paths to find the stackpanel config:
	// 1. devShells.<system>.default.passthru.stackpanelConfig (user projects consuming stackpanel)
	// 2. stackpanelFullConfig flake output (stackpanel repo itself)
	// 3. stackpanelConfig flake output (fallback)
	//
	// Use git+file:// protocol to avoid copying untracked files (node_modules, etc.)
	nixExpr := fmt.Sprintf(`
let
  system = builtins.currentSystem;
  flake = builtins.getFlake "git+file://%s";

  # Try to get stackpanel config from various paths
  # Priority 1: devshell passthru (for user projects consuming stackpanel)
  devshell = flake.devShells.${system}.default or null;
  passthruConfig = if devshell != null then devshell.passthru.stackpanelConfig or null else null;

  # Priority 2: stackpanelFullConfig flake output (for stackpanel repo itself)
  fullConfig = flake.stackpanelFullConfig or null;

  # Priority 3: stackpanelConfig flake output (serialized version)
  serializedConfig = flake.stackpanelConfig or null;

  # Use first available config
  stackpanelCfg =
    if passthruConfig != null then passthruConfig
    else if fullConfig != null then fullConfig
    else serializedConfig;

  filesCfg = if stackpanelCfg != null then stackpanelCfg.files or null else null;

  # Convert a file entry to serializable form
  mkSerializable = path: entry: {
    inherit path;
    type = entry.type or "text";
    mode = entry.mode or null;
    source = entry.source or null;
    description = entry.description or null;
    enable = entry.enable or true;
    # For derivations, get the store path as string
    storePath = if entry.type == "derivation" && entry.drv != null
                then builtins.toString entry.drv
                else null;
    # For text, include the content (truncated if too large)
    text = if entry.type == "text" && entry.text != null
           then (if builtins.stringLength entry.text <= 10000 then entry.text else null)
           else null;
  };

  entries = if filesCfg != null && filesCfg.entries != null
            then builtins.mapAttrs mkSerializable filesCfg.entries
            else {};
in
{
  enable = if filesCfg != null then filesCfg.enable or true else false;
  entries = entries;
}
`, s.config.ProjectRoot)

	args := []string{"eval", "--impure", "--json", "--expr", nixExpr}

	res, err := s.exec.RunNix(args...)
	if err != nil {
		return nil, fmt.Errorf("nix eval failed: %w", err)
	}

	if res.ExitCode != 0 {
		// Try a simpler fallback for repos without full devshell setup
		return s.evaluateStackpanelFilesSimple()
	}

	var output nixFilesOutput
	if err := json.Unmarshal([]byte(res.Stdout), &output); err != nil {
		return nil, fmt.Errorf("failed to parse nix output: %w", err)
	}

	return &output, nil
}

// evaluateStackpanelFilesSimple is a fallback that tries alternative attribute paths
func (s *Server) evaluateStackpanelFilesSimple() (*nixFilesOutput, error) {
	// Fallback: try additional paths to find the files config
	// This handles edge cases where the main evaluation failed
	nixExpr := fmt.Sprintf(`
let
  system = builtins.currentSystem;
  flake = builtins.getFlake "git+file://%s";

  # Try various paths to find the files config
  devshell = flake.devShells.${system}.default or null;

  tryPaths = [
    # User project: devshell passthru
    (if devshell != null then (devshell.passthru.stackpanelConfig.files or null) else null)
    # Stackpanel repo: flake outputs
    (flake.stackpanelFullConfig.files or null)
    (flake.stackpanelConfig.files or null)
  ];

  findFirst = list:
    let filtered = builtins.filter (x: x != null) list;
    in if filtered == [] then null else builtins.head filtered;

  filesCfg = findFirst tryPaths;

  mkSerializable = path: entry: {
    inherit path;
    type = entry.type or "text";
    mode = entry.mode or null;
    source = entry.source or null;
    description = entry.description or null;
    enable = entry.enable or true;
    storePath = if entry.type == "derivation" && entry.drv != null
                then builtins.toString entry.drv
                else null;
    text = if entry.type == "text" && entry.text != null
           then (if builtins.stringLength entry.text <= 10000 then entry.text else null)
           else null;
  };

  entries = if filesCfg != null && filesCfg.entries != null
            then builtins.mapAttrs mkSerializable filesCfg.entries
            else {};
in
{
  enable = if filesCfg != null then filesCfg.enable or true else false;
  entries = entries;
}
`, s.config.ProjectRoot)

	args := []string{"eval", "--impure", "--json", "--expr", nixExpr}

	res, err := s.exec.RunNix(args...)
	if err != nil {
		return nil, fmt.Errorf("nix eval failed: %w", err)
	}

	if res.ExitCode != 0 {
		// Return empty result if we can't evaluate files
		log.Debug().Str("stderr", res.Stderr).Msg("Could not evaluate stackpanel.files, returning empty")
		return &nixFilesOutput{
			Enable:  false,
			Entries: make(map[string]nixFileEntry),
		}, nil
	}

	var output nixFilesOutput
	if err := json.Unmarshal([]byte(res.Stdout), &output); err != nil {
		return nil, fmt.Errorf("failed to parse nix output: %w", err)
	}

	return &output, nil
}

// buildFilesResponse converts nixFilesOutput to GeneratedFilesResponse
// and checks disk status for each file
func (s *Server) buildFilesResponse(data *nixFilesOutput) *GeneratedFilesResponse {
	files := make([]GeneratedFile, 0, len(data.Entries))
	staleCount := 0
	enabledCount := 0

	for path, entry := range data.Entries {
		file := GeneratedFile{
			Path:        path,
			Type:        entry.Type,
			Mode:        entry.Mode,
			Source:      entry.Source,
			Description: entry.Description,
			StorePath:   entry.StorePath,
			Text:        entry.Text,
			Enable:      entry.Enable,
		}

		if entry.Enable {
			enabledCount++
		}

		// Check if file exists on disk and compute staleness
		diskPath := filepath.Join(s.config.ProjectRoot, path)
		if info, err := os.Stat(diskPath); err == nil {
			file.ExistsOnDisk = true
			size := info.Size()
			file.Size = &size

			// Compute content hash of disk file
			if diskHash, err := hashFile(diskPath); err == nil {
				file.ContentHash = &diskHash

				// Check staleness by comparing with expected content
				isStale := s.checkFileStale(entry, diskPath, diskHash)
				file.IsStale = isStale
				if isStale && entry.Enable {
					staleCount++
				}
			}
		} else {
			file.ExistsOnDisk = false
			// If file should exist but doesn't, it's stale
			if entry.Enable {
				file.IsStale = true
				staleCount++
			}
		}

		files = append(files, file)
	}

	return &GeneratedFilesResponse{
		Files:        files,
		TotalCount:   len(files),
		StaleCount:   staleCount,
		EnabledCount: enabledCount,
		LastUpdated:  time.Now().Format(time.RFC3339),
	}
}

// checkFileStale determines if a file on disk differs from its expected content
func (s *Server) checkFileStale(entry nixFileEntry, diskPath, diskHash string) bool {
	// For text entries, we can compare directly
	if entry.Type == "text" && entry.Text != nil {
		expectedHash := hashString(*entry.Text)
		return diskHash != expectedHash
	}

	// For derivation entries, compare with store path content
	if entry.Type == "derivation" && entry.StorePath != nil {
		storeHash, err := hashFile(*entry.StorePath)
		if err != nil {
			log.Debug().Err(err).Str("storePath", *entry.StorePath).Msg("Failed to hash store path")
			return true // Assume stale if we can't check
		}
		return diskHash != storeHash
	}

	// Can't determine staleness
	return false
}

// hashFile computes SHA256 hash of a file
func hashFile(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return hashBytes(data), nil
}

// hashString computes SHA256 hash of a string
func hashString(s string) string {
	return hashBytes([]byte(s))
}

// hashBytes computes SHA256 hash of bytes
func hashBytes(data []byte) string {
	hash := sha256.Sum256(data)
	return hex.EncodeToString(hash[:])
}
