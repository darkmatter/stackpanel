package server

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// --- HTTP response helpers ---

func (s *Server) writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *Server) writeAPI(w http.ResponseWriter, status int, data any) {
	s.writeJSON(w, status, apiResponse{Success: true, Data: data})
}

func (s *Server) writeAPIError(w http.ResponseWriter, status int, message string) {
	s.writeJSON(w, status, apiResponse{Success: false, Error: message})
}

// readJSON decodes a JSON request body with a 2 MiB size limit. Unknown fields
// are rejected to catch typos in API requests early.
func (s *Server) readJSON(body io.ReadCloser, v any) error {
	defer body.Close()
	dec := json.NewDecoder(io.LimitReader(body, 2<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return fmt.Errorf("invalid json: %w", err)
	}
	return nil
}

// generateToken returns a URL-safe base64 token of n random bytes.
func generateToken(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err == nil {
		return base64.RawURLEncoding.EncodeToString(b)
	}
	// Extremely unlikely, but ensure we still generate something.
	fallback := []byte(fmt.Sprintf("stackpanel-%d", time.Now().UnixNano()))
	return base64.RawURLEncoding.EncodeToString(fallback)
}

// safeJoin resolves rel within root, rejecting absolute paths and directory
// traversals (..) to prevent path escape attacks on file operations.
func safeJoin(root string, rel string) (string, error) {
	rel = strings.TrimSpace(rel)
	if rel == "" {
		return "", errors.New("empty path")
	}
	if filepath.IsAbs(rel) {
		return "", errors.New("absolute paths not allowed")
	}
	clean := filepath.Clean(rel)
	if clean == "." {
		return root, nil
	}
	if clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
		return "", errors.New("path escapes project root")
	}
	full := filepath.Join(root, clean)
	rel2, err := filepath.Rel(root, full)
	if err != nil {
		return "", err
	}
	if rel2 == ".." || strings.HasPrefix(rel2, ".."+string(os.PathSeparator)) {
		return "", errors.New("path escapes project root")
	}
	return full, nil
}

// buildNixEvalArgs constructs `nix eval` arguments from user input, using
// heuristics to distinguish between:
//   - Raw Nix expressions (contains whitespace, starts with { or ()  → --expr
//   - Full flake references (contains #)                              → as-is
//   - Bare attribute paths                                            → prepends .#
//
// Always uses --impure because Nix config often reads env vars and local files.
func buildNixEvalArgs(expression string) []string {
	expr := strings.TrimSpace(expression)

	if looksLikeNixExpr(expr) {
		return []string{"eval", "--impure", "--json", "--expr", expr}
	}

	if strings.Contains(expr, "#") {
		return []string{"eval", "--impure", "--json", expr}
	}

	return []string{"eval", "--impure", "--json", ".#" + expr}
}

// looksLikeNixExpr uses a rough heuristic to detect raw Nix expressions vs attr paths.
func looksLikeNixExpr(s string) bool {
	if strings.ContainsAny(s, " \t\n") {
		return true
	}
	return strings.HasPrefix(s, "{") || strings.HasPrefix(s, "(") || strings.HasPrefix(s, "let")
}

// normalizeEnv maps environment name aliases to their canonical forms.
// Accepts: "dev"/"development", "staging", "prod"/"production".
func normalizeEnv(env string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(env)) {
	case "dev", "development":
		return "dev", nil
	case "staging":
		return "staging", nil
	case "prod", "production":
		return "prod", nil
	default:
		return "", fmt.Errorf("invalid env: %s", env)
	}
}

// secretsUser was used for the legacy users.yaml format - now deprecated.
// Users are read from .stack/data/users.nix via Nix evaluation.

// setSopsSecret encrypts a key-value pair into the environment's SOPS YAML file
// (.stack/secrets/{env}.yaml). It decrypts the existing file, merges the new value,
// then re-encrypts with all configured AGE recipients. Returns the relative path
// of the written secrets file.
func (s *Server) setSopsSecret(env string, key string, value string) (string, error) {
	// Get recipients from Nix config.
	recipients, err := s.getAgenixRecipients(nil)
	if err != nil || len(recipients) == 0 {
		// Fall back to recipients resolved from the serialized secrets config
		recipients = s.getAgeRecipients()
	}
	if len(recipients) == 0 {
		return "", errors.New("no recipients found - configure stackpanel.secrets.recipients or stackpanel.users public-keys")
	}

	secretsRel := fmt.Sprintf(".stack/secrets/%s.yaml", env)
	secretsPath, err := safeJoin(s.config.ProjectRoot, secretsRel)
	if err != nil {
		return "", err
	}

	plain := map[string]any{}
	if _, err := os.ReadFile(secretsPath); err == nil {
		// Decrypt existing secrets file.
		res, execErr := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, "--decrypt", secretsRel)
		if execErr != nil {
			return "", execErr
		}
		if res.ExitCode != 0 {
			return "", fmt.Errorf("sops decrypt failed: %s", strings.TrimSpace(res.Stderr))
		}
		if err := yaml.Unmarshal([]byte(res.Stdout), &plain); err != nil {
			return "", fmt.Errorf("failed to parse decrypted secrets yaml: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}

	plain[key] = value
	plainBytes, err := yaml.Marshal(plain)
	if err != nil {
		return "", fmt.Errorf("failed to marshal secrets yaml: %w", err)
	}

	tmp, err := os.CreateTemp("", "stackpanel-secrets-*.yaml")
	if err != nil {
		return "", err
	}
	tmpPath := tmp.Name()
	_ = tmp.Close()
	defer os.Remove(tmpPath)

	if err := os.WriteFile(tmpPath, plainBytes, 0o600); err != nil {
		return "", err
	}

	// Encrypt with explicit --age recipients instead of relying on .sops.yaml,
	// which may not exist or be configured for this project.
	args := []string{"--encrypt", "--input-type", "yaml", "--output-type", "yaml", "--age", strings.Join(recipients, ",")}
	args = append(args, tmpPath)

	enc, execErr := s.exec.RunWithOptions("sops", s.config.ProjectRoot, nil, args...)
	if execErr != nil {
		return "", execErr
	}
	if enc.ExitCode != 0 {
		return "", fmt.Errorf("sops encrypt failed: %s", strings.TrimSpace(enc.Stderr))
	}

	if err := os.MkdirAll(filepath.Dir(secretsPath), 0o755); err != nil {
		return "", err
	}
	if err := os.WriteFile(secretsPath, []byte(enc.Stdout), 0o600); err != nil {
		return "", err
	}

	return secretsRel, nil
}
