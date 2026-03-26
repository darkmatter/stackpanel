// connect_modules.go provides Connect-RPC handlers for enabling, disabling, and
// configuring stackpanel modules. Module changes are persisted to disk but only
// take effect after re-entering the devshell (Nix needs to re-evaluate).
// SSE events are broadcast on changes so connected UIs can update immediately.

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"connectrpc.com/connect"
	gopb "github.com/darkmatter/stackpanel/packages/proto/gen/gopb"
)

// EnableModule enables a module by updating the module config file.
func (s *AgentServiceServer) EnableModule(
	ctx context.Context,
	req *connect.Request[gopb.EnableModuleRequest],
) (*connect.Response[gopb.ModuleResponse], error) {
	moduleID := req.Msg.GetModuleId()
	if moduleID == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("module_id is required"))
	}

	// Load existing config or create new
	config, err := s.server.loadModuleConfig(moduleID)
	if err != nil && !os.IsNotExist(err) {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to load config: %w", err))
	}

	// Enable the module
	enabled := true
	config.Enable = &enabled

	// Apply initial settings if provided
	if len(req.Msg.GetSettings()) > 0 {
		if config.Settings == nil {
			config.Settings = make(map[string]any)
		}
		for k, v := range req.Msg.GetSettings() {
			config.Settings[k] = v
		}
	}

	// Save config
	if err := s.server.saveModuleConfig(moduleID, config); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to save config: %w", err))
	}

	// Broadcast change via SSE
	s.server.broadcastSSE(SSEEvent{
		Event: "module.enabled.changed",
		Data: map[string]any{
			"module":  moduleID,
			"enabled": true,
		},
	})

	msg := fmt.Sprintf("Module '%s' enabled. Re-enter your devshell to apply changes.", moduleID)
	return connect.NewResponse(&gopb.ModuleResponse{
		Success: true,
		Message: &msg,
		Module: &gopb.Module{
			Id:       moduleID,
			Enable:   true,
			Settings: req.Msg.GetSettings(),
		},
	}), nil
}

// DisableModule disables a module by updating the module config file.
func (s *AgentServiceServer) DisableModule(
	ctx context.Context,
	req *connect.Request[gopb.DisableModuleRequest],
) (*connect.Response[gopb.ModuleResponse], error) {
	moduleID := req.Msg.GetModuleId()
	if moduleID == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("module_id is required"))
	}

	// Load existing config or create new
	config, err := s.server.loadModuleConfig(moduleID)
	if err != nil && !os.IsNotExist(err) {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to load config: %w", err))
	}

	// Disable the module
	enabled := false
	config.Enable = &enabled

	// Save config
	if err := s.server.saveModuleConfig(moduleID, config); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to save config: %w", err))
	}

	// Broadcast change via SSE
	s.server.broadcastSSE(SSEEvent{
		Event: "module.enabled.changed",
		Data: map[string]any{
			"module":  moduleID,
			"enabled": false,
		},
	})

	msg := fmt.Sprintf("Module '%s' disabled. Re-enter your devshell to apply changes.", moduleID)
	return connect.NewResponse(&gopb.ModuleResponse{
		Success: true,
		Message: &msg,
		Module: &gopb.Module{
			Id:     moduleID,
			Enable: false,
		},
	}), nil
}

// UpdateModuleSettings updates the settings for a module.
func (s *AgentServiceServer) UpdateModuleSettings(
	ctx context.Context,
	req *connect.Request[gopb.UpdateModuleSettingsRequest],
) (*connect.Response[gopb.ModuleResponse], error) {
	moduleID := req.Msg.GetModuleId()
	if moduleID == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("module_id is required"))
	}

	// Load existing config or create new
	config, err := s.server.loadModuleConfig(moduleID)
	if err != nil && !os.IsNotExist(err) {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to load config: %w", err))
	}

	// Update settings
	if config.Settings == nil {
		config.Settings = make(map[string]any)
	}
	for k, v := range req.Msg.GetSettings() {
		config.Settings[k] = v
	}

	// Save config
	if err := s.server.saveModuleConfig(moduleID, config); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to save config: %w", err))
	}

	// Broadcast change via SSE
	s.server.broadcastSSE(SSEEvent{
		Event: "module.config.updated",
		Data: map[string]any{
			"module":   moduleID,
			"settings": req.Msg.GetSettings(),
		},
	})

	msg := fmt.Sprintf("Module '%s' settings updated. Re-enter your devshell to apply changes.", moduleID)
	return connect.NewResponse(&gopb.ModuleResponse{
		Success: true,
		Message: &msg,
		Module: &gopb.Module{
			Id:       moduleID,
			Enable:   true, // Assume module is enabled if we're updating settings
			Settings: req.Msg.GetSettings(),
		},
	}), nil
}

// moduleToProto converts an internal Module (from Nix evaluation) to the proto
// representation. This mapping is verbose because the proto schema mirrors the
// Nix module type system (meta, source, features, panels, per-app config).
func moduleToProto(m Module) *gopb.Module {
	pm := &gopb.Module{
		Id:     m.ID,
		Enable: m.Enabled,
		Meta: &gopb.ModuleMeta{
			Name:     m.Meta.Name,
			Category: categoryToProto(m.Meta.Category),
		},
		Source: &gopb.ModuleSource{
			Type: sourceTypeToProto(m.Source.Type),
		},
		Features: &gopb.ModuleFeatures{
			Files:        m.Features.Files,
			Scripts:      m.Features.Scripts,
			Tasks:        m.Features.Tasks,
			Healthchecks: m.Features.Healthchecks,
			Services:     m.Features.Services,
			Secrets:      m.Features.Secrets,
			Packages:     m.Features.Packages,
			AppModule:    m.Features.AppModule,
		},
		Requires:  m.Requires,
		Conflicts: m.Conflicts,
		Priority:  int32(m.Priority),
		Tags:      m.Tags,
	}

	// Optional fields
	if m.Meta.Description != nil {
		pm.Meta.Description = m.Meta.Description
	}
	if m.Meta.Icon != nil {
		pm.Meta.Icon = m.Meta.Icon
	}
	if m.Meta.Author != nil {
		pm.Meta.Author = m.Meta.Author
	}
	if m.Meta.Version != nil {
		pm.Meta.Version = m.Meta.Version
	}
	if m.Meta.Homepage != nil {
		pm.Meta.Homepage = m.Meta.Homepage
	}
	if m.ConfigSchema != nil {
		pm.ConfigSchema = m.ConfigSchema
	}
	if m.HealthModule != nil {
		pm.HealthcheckModule = m.HealthModule
	}

	// Source optional fields
	if m.Source.FlakeInput != nil {
		pm.Source.FlakeInput = m.Source.FlakeInput
	}
	if m.Source.Path != nil {
		pm.Source.Path = m.Source.Path
	}
	if m.Source.RegistryID != nil {
		pm.Source.RegistryId = m.Source.RegistryID
	}
	if m.Source.Ref != nil {
		pm.Source.Ref = m.Source.Ref
	}

	// Panels
	for _, p := range m.Panels {
		protoPanel := &gopb.ModulePanel{
			Id:    p.ID,
			Title: p.Title,
			Type:  panelTypeToProto(p.Type),
			Order: int32(p.Order),
		}
		if p.Description != nil {
			protoPanel.Description = p.Description
		}
		for _, f := range p.Fields {
			protoPanel.Fields = append(protoPanel.Fields, &gopb.ModulePanelField{
				Name:    f.Name,
				Type:    fieldTypeToProto(f.Type),
				Value:   f.Value,
				Options: f.Options,
			})
		}
		pm.Panels = append(pm.Panels, protoPanel)
	}

	// Apps
	if m.Apps != nil {
		pm.Apps = make(map[string]*gopb.ModuleAppData)
		for appName, appData := range m.Apps {
			if data, err := json.Marshal(appData); err == nil {
				var appConfig map[string]any
				if err := json.Unmarshal(data, &appConfig); err == nil {
					pm.Apps[appName] = &gopb.ModuleAppData{
						Enabled: true,
						Config:  stringMapFromAny(appConfig),
					}
				}
			}
		}
	}

	return pm
}

// stringMapFromAny flattens a map[string]any to map[string]string for proto.
// Non-string values are JSON-marshaled, which is lossy but sufficient for
// the UI which just displays config values as text.
func stringMapFromAny(m map[string]any) map[string]string {
	result := make(map[string]string)
	for k, v := range m {
		if s, ok := v.(string); ok {
			result[k] = s
		} else if data, err := json.Marshal(v); err == nil {
			result[k] = string(data)
		}
	}
	return result
}

func categoryToProto(cat string) gopb.ModuleCategory {
	switch cat {
	case "infrastructure":
		return gopb.ModuleCategory_MODULE_CATEGORY_INFRASTRUCTURE
	case "ci-cd":
		return gopb.ModuleCategory_MODULE_CATEGORY_CI_CD
	case "database":
		return gopb.ModuleCategory_MODULE_CATEGORY_DATABASE
	case "secrets":
		return gopb.ModuleCategory_MODULE_CATEGORY_SECRETS
	case "deployment":
		return gopb.ModuleCategory_MODULE_CATEGORY_DEPLOYMENT
	case "development":
		return gopb.ModuleCategory_MODULE_CATEGORY_DEVELOPMENT
	case "monitoring":
		return gopb.ModuleCategory_MODULE_CATEGORY_MONITORING
	case "integration":
		return gopb.ModuleCategory_MODULE_CATEGORY_INTEGRATION
	case "language":
		return gopb.ModuleCategory_MODULE_CATEGORY_LANGUAGE
	case "service":
		return gopb.ModuleCategory_MODULE_CATEGORY_SERVICE
	default:
		return gopb.ModuleCategory_MODULE_CATEGORY_UNSPECIFIED
	}
}

func sourceTypeToProto(t string) gopb.ModuleSourceType {
	switch t {
	case "builtin":
		return gopb.ModuleSourceType_MODULE_SOURCE_TYPE_BUILTIN
	case "local":
		return gopb.ModuleSourceType_MODULE_SOURCE_TYPE_LOCAL
	case "flake-input":
		return gopb.ModuleSourceType_MODULE_SOURCE_TYPE_FLAKE_INPUT
	case "registry":
		return gopb.ModuleSourceType_MODULE_SOURCE_TYPE_REGISTRY
	default:
		return gopb.ModuleSourceType_MODULE_SOURCE_TYPE_UNSPECIFIED
	}
}

func panelTypeToProto(t string) gopb.ModulePanelType {
	switch t {
	case "PANEL_TYPE_STATUS":
		return gopb.ModulePanelType_MODULE_PANEL_TYPE_STATUS
	case "PANEL_TYPE_APPS_GRID":
		return gopb.ModulePanelType_MODULE_PANEL_TYPE_APPS_GRID
	case "PANEL_TYPE_FORM":
		return gopb.ModulePanelType_MODULE_PANEL_TYPE_FORM
	case "PANEL_TYPE_TABLE":
		return gopb.ModulePanelType_MODULE_PANEL_TYPE_TABLE
	case "PANEL_TYPE_CUSTOM":
		return gopb.ModulePanelType_MODULE_PANEL_TYPE_CUSTOM
	default:
		return gopb.ModulePanelType_MODULE_PANEL_TYPE_UNSPECIFIED
	}
}

func fieldTypeToProto(t string) gopb.ModuleFieldType {
	switch t {
	case "FIELD_TYPE_STRING":
		return gopb.ModuleFieldType_MODULE_FIELD_TYPE_STRING
	case "FIELD_TYPE_NUMBER":
		return gopb.ModuleFieldType_MODULE_FIELD_TYPE_NUMBER
	case "FIELD_TYPE_BOOLEAN":
		return gopb.ModuleFieldType_MODULE_FIELD_TYPE_BOOLEAN
	case "FIELD_TYPE_SELECT":
		return gopb.ModuleFieldType_MODULE_FIELD_TYPE_SELECT
	case "FIELD_TYPE_MULTISELECT":
		return gopb.ModuleFieldType_MODULE_FIELD_TYPE_MULTISELECT
	case "FIELD_TYPE_APP_FILTER":
		return gopb.ModuleFieldType_MODULE_FIELD_TYPE_APP_FILTER
	case "FIELD_TYPE_COLUMNS":
		return gopb.ModuleFieldType_MODULE_FIELD_TYPE_COLUMNS
	case "FIELD_TYPE_JSON":
		return gopb.ModuleFieldType_MODULE_FIELD_TYPE_JSON
	default:
		return gopb.ModuleFieldType_MODULE_FIELD_TYPE_UNSPECIFIED
	}
}
