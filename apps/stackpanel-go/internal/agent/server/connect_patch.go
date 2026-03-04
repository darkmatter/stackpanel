package server

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"connectrpc.com/connect"
	gopb "github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
	"github.com/rs/zerolog/log"
)

// PatchNixData updates a single value at a nested path within the config.nix file.
//
// This enables editing individual fields from UI panels without replacing the
// entire config. The path uses camelCase (matching the SpField/panel editPath
// convention). Path segments are converted to kebab-case when navigating the
// Nix data structure.
//
// All patches now go to .stack/config.nix (the single source of truth).
//
// Example: PatchNixData(entity="config", path="stackpanel.deployment.fly.organization", value="\"my-org\"")
// This writes to .stack/config.nix at deployment.fly.organization
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

	srv := s.server

	// All patches now go to config.nix
	// For entity="config" with "stackpanel." prefix, strip the prefix
	// For other entities, prepend the entity name to the path
	if entity == "config" && strings.HasPrefix(path, "stackpanel.") {
		return s.patchConsolidatedConfig(srv, path, parsedValue)
	}

	// For entity-based patches (e.g., entity="apps", key="web", path="container.enable")
	// Construct the full path: apps.web.container.enable
	var fullPath string
	if msg.Key != "" && msg.Key != "_root" && msg.Key != "_global" {
		fullPath = entity + "." + msg.Key + "." + path
	} else {
		fullPath = entity + "." + path
	}
	return s.patchConsolidatedConfig(srv, "stackpanel."+fullPath, parsedValue)
}

// patchConsolidatedConfig handles patches to the consolidated config.nix file.
// Path format: "stackpanel.deployment.fly.organization" -> writes to config.nix at deployment.fly.organization
func (s *AgentServiceServer) patchConsolidatedConfig(
	srv *Server,
	fullPath string,
	value any,
) (*connect.Response[gopb.PatchNixDataResponse], error) {
	// Strip "stackpanel." prefix to get the path within config.nix
	configPath := parseConfigPath(fullPath)

	log.Info().
		Str("fullPath", fullPath).
		Str("configPath", configPath).
		Interface("value", value).
		Msg("PatchNixData: patching consolidated config.nix")

	// Patch the consolidated config file
	if err := srv.patchConsolidatedData(configPath, value); err != nil {
		log.Error().Err(err).Msg("PatchNixData: failed to patch consolidated config")
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to patch config: %w", err))
	}

	// Read back the updated data for cache invalidation
	updatedData, err := srv.readConsolidatedData()
	if err != nil {
		log.Warn().Err(err).Msg("PatchNixData: failed to read back updated config")
	}

	// Invalidate FlakeWatcher cache so next GetNixConfig returns fresh data
	if srv.flakeWatcher != nil {
		srv.flakeWatcher.InvalidateConfig()
		log.Debug().Msg("PatchNixData: invalidated FlakeWatcher config cache")
	}

	// Emit config.changed SSE event
	srv.broadcastSSE(SSEEvent{
		Event: "config.changed",
		Data: map[string]any{
			"entity": "config",
			"path":   fullPath,
			"source": "patch",
		},
	})

	log.Info().
		Str("path", fullPath).
		Str("file", srv.nixDataFilePath()).
		Msg("PatchNixData: successfully patched consolidated config.nix")

	// Return updated data as JSON
	var updatedJSON []byte
	if updatedData != nil {
		updatedJSON, _ = json.Marshal(updatedData)
	}

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
