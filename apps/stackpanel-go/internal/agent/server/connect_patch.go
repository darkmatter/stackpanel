package server

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"connectrpc.com/connect"
	gopb "github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
	nixser "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
	"github.com/rs/zerolog/log"
)

// PatchNixData updates a single value at a nested path within a Nix data entity.
//
// This enables editing individual fields from UI panels without replacing the
// entire entity. The path uses camelCase (matching the SpField/panel editPath
// convention). Path segments are converted to kebab-case when navigating the
// Nix data structure.
//
// Example: PatchNixData(entity="apps", key="web", path="go.mainPackage", value="\"./cmd/api\"")
// This reads .stackpanel/data/apps.nix, navigates to apps.web.go.main-package,
// sets it to "./cmd/api", and writes the file back.
func (s *AgentServiceServer) PatchNixData(
	ctx context.Context,
	req *connect.Request[gopb.PatchNixDataRequest],
) (*connect.Response[gopb.PatchNixDataResponse], error) {
	msg := req.Msg

	log.Info().
		Str("entity", msg.Entity).
		Str("key", msg.Key).
		Str("path", msg.Path).
		Str("valueType", msg.ValueType).
		Msg("PatchNixData: received request")

	// Validate entity
	entity := strings.TrimSpace(msg.Entity)
	if entity == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("entity is required"))
	}
	if err := validateEntityName(entity); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}
	if isExternalEntity(entity) {
		return nil, connect.NewError(connect.CodePermissionDenied, fmt.Errorf("external entities are read-only"))
	}

	// Validate path
	path := strings.TrimSpace(msg.Path)
	if path == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("path is required"))
	}

	// Parse the value from JSON
	parsedValue, err := parseValueJSON(msg.Value, msg.ValueType)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("invalid value: %w", err))
	}

	// Read existing data
	srv := s.server
	dataPath := srv.nixDataPath(entity)
	existing := make(map[string]any)

	if _, err := os.Stat(dataPath); err == nil {
		data, err := srv.readNixDataFile(entity)
		if err != nil {
			log.Error().Err(err).Str("entity", entity).Msg("PatchNixData: failed to read existing data")
			return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to read existing data: %w", err))
		}
		if dataMap, ok := data.(map[string]any); ok {
			existing = dataMap
		}
	}

	// Navigate to the target location and set the value
	// Path is camelCase from UI (e.g., "go.mainPackage")
	// Nix data uses kebab-case keys (e.g., "go.main-package")
	target := existing
	key := msg.Key

	// If key is specified, navigate into it first (for map entities like "apps")
	if key != "" {
		kebabKey := camelToKebab(key)
		child, ok := target[kebabKey]
		if !ok {
			// Key doesn't exist yet, create it
			target[kebabKey] = make(map[string]any)
			child = target[kebabKey]
		}
		childMap, ok := child.(map[string]any)
		if !ok {
			return nil, connect.NewError(connect.CodeFailedPrecondition,
				fmt.Errorf("key %q is not a map in entity %q", key, entity))
		}
		target = childMap
	}

	// Navigate the dot-separated path
	pathParts := strings.Split(path, ".")
	for i, part := range pathParts {
		kebabPart := camelToKebab(part)

		if i == len(pathParts)-1 {
			// Last segment: set the value
			target[kebabPart] = parsedValue
			log.Debug().
				Str("path", path).
				Str("kebabKey", kebabPart).
				Interface("value", parsedValue).
				Msg("PatchNixData: set value")
		} else {
			// Intermediate segment: navigate deeper
			child, ok := target[kebabPart]
			if !ok {
				// Create intermediate map
				target[kebabPart] = make(map[string]any)
				child = target[kebabPart]
			}
			childMap, ok := child.(map[string]any)
			if !ok {
				return nil, connect.NewError(connect.CodeFailedPrecondition,
					fmt.Errorf("path segment %q is not a map at %q", part, strings.Join(pathParts[:i+1], ".")))
			}
			target = childMap
		}
	}

	// Serialize and write
	nixExpr, err := nixser.SerializeIndented(existing, "  ")
	if err != nil {
		log.Error().Err(err).Msg("PatchNixData: failed to serialize to Nix")
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to serialize data to Nix: %w", err))
	}

	// Ensure data directory exists
	dataDir := srv.nixDataDir()
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to create data directory: %w", err))
	}

	if err := os.WriteFile(dataPath, []byte(nixExpr+"\n"), 0o644); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to write data file: %w", err))
	}

	log.Info().
		Str("entity", entity).
		Str("key", key).
		Str("path", path).
		Str("dataPath", dataPath).
		Msg("PatchNixData: successfully patched value")

	// Return the updated entity as JSON for cache invalidation
	updatedJSON, err := json.Marshal(existing)
	if err != nil {
		// Non-fatal: write succeeded, just can't return updated data
		log.Warn().Err(err).Msg("PatchNixData: failed to marshal updated data")
		return connect.NewResponse(&gopb.PatchNixDataResponse{
			Success: true,
		}), nil
	}

	// Emit config.changed SSE event so the UI can refresh
	srv.broadcastSSE(SSEEvent{
		Event: "config.changed",
		Data: map[string]any{
			"entity": entity,
			"key":    key,
			"path":   path,
			"source": "patch",
		},
	})

	return connect.NewResponse(&gopb.PatchNixDataResponse{
		Success:     true,
		UpdatedJson: string(updatedJSON),
	}), nil
}

// parseValueJSON parses a JSON-encoded value string with an optional type hint.
// Returns the Go value suitable for Nix serialization.
func parseValueJSON(value string, valueType string) (any, error) {
	if value == "" && valueType != "string" {
		return nil, fmt.Errorf("value is required")
	}

	switch valueType {
	case "string":
		// Value is a JSON string (e.g., "\"./cmd/api\"")
		var s string
		if err := json.Unmarshal([]byte(value), &s); err != nil {
			// If it's not valid JSON, treat the raw value as the string
			return value, nil
		}
		return s, nil

	case "bool":
		var b bool
		if err := json.Unmarshal([]byte(value), &b); err != nil {
			return nil, fmt.Errorf("invalid bool value: %s", value)
		}
		return b, nil

	case "number":
		var n json.Number
		if err := json.Unmarshal([]byte(value), &n); err != nil {
			return nil, fmt.Errorf("invalid number value: %s", value)
		}
		// Try int first, then float
		if i, err := n.Int64(); err == nil {
			return i, nil
		}
		if f, err := n.Float64(); err == nil {
			return f, nil
		}
		return nil, fmt.Errorf("invalid number value: %s", value)

	case "list":
		var list []any
		if err := json.Unmarshal([]byte(value), &list); err != nil {
			return nil, fmt.Errorf("invalid list value: %s", value)
		}
		return list, nil

	case "object":
		var obj map[string]any
		if err := json.Unmarshal([]byte(value), &obj); err != nil {
			return nil, fmt.Errorf("invalid object value: %s", value)
		}
		return obj, nil

	case "null":
		return nil, nil

	default:
		// Auto-detect type from JSON
		var parsed any
		if err := json.Unmarshal([]byte(value), &parsed); err != nil {
			// Not valid JSON, treat as raw string
			return value, nil
		}
		return parsed, nil
	}
}
