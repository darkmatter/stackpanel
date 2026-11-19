package server

import (
	"math"
	"net/http"
	"slices"
	"strings"
	"unicode"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/santhosh-tekuri/jsonschema/v6"
)

func appPanelSlot(slot string) bool {
	switch slot {
	case "app:runtime", "app:framework", "app:container", "app:deployment", "app:tab":
		return true
	}
	return false
}

// Visibility applies to every capability, not just writable settings. A
// missing panel-specific filter means any enabled app in THIS project, not
// an arbitrary app string, and a module-global panel never accepts an app.
func validPanelApp(state map[string]any, slot, app string, panelApps map[string]any) bool {
	if !strings.HasPrefix(slot, "app:") {
		return app == ""
	}
	if !appPanelSlot(slot) || !validStatusID(app) {
		return false
	}
	apps, _ := state["apps"].(map[string]any)
	projectApp, _ := apps[app].(map[string]any)
	entry, _ := panelApps[app].(map[string]any)
	return projectApp["enable"] == true && (len(panelApps) == 0 || entry["enabled"] == true)
}

// Return a writable projection only for the authenticated grant's exact app.
// The typed namespace values come from uiBundle.appSettings, never from
// display strings. Both projections must explicitly name each writable field.
func (b *moduleBundle) writableApp(app string) (map[string]any, error) {
	if !slices.Contains(b.permissions, "config:patch") {
		return nil, nil
	}
	if app == "" && !strings.HasPrefix(b.slot, "app:") {
		return nil, nil // module-global panel
	}
	if !appPanelSlot(b.slot) || nixdata.ValidateEntityName(app) != nil {
		return nil, uiGrantDenied()
	}
	entry, _ := b.apps[app].(map[string]any)
	fields, _ := entry["config"].(map[string]any)
	public, _ := b.appSettings[app].(map[string]any)
	moduleID, _ := b.module["id"].(string)
	if entry["enabled"] != true || !publicAppKey(moduleID) || len(public) == 0 {
		return nil, uiGrantDenied()
	}
	for k, v := range public {
		if _, declared := fields[k].(string); !declared || !publicAppKey(k) ||
			!portableAppValue(v) {
			return nil, uiGrantDenied()
		}
	}
	if !validWritableAppSchema(b.appSchemas[app], public) {
		return nil, uiGrantDenied()
	}
	return public, nil
}

// A writable grant requires the declared option schema, not an inferred
// schema from today's values (an empty list says nothing about item type).
func validWritableAppSchema(raw any, public map[string]any) bool {
	schema, _ := raw.(map[string]any)
	properties, _ := schema["properties"].(map[string]any)
	if schema["type"] != "object" || schema["additionalProperties"] != false ||
		len(properties) != len(public) ||
		!moduleActionLocalRefs(schema) {
		return false
	}
	for k := range public {
		if !typedAppOption(properties[k]) {
			return false
		}
	}
	const resource = "urn:stackpanel:app-options"
	c := jsonschema.NewCompiler()
	c.UseLoader(nil)
	if err := c.AddResource(resource, schema); err != nil {
		return false
	}
	compiled, err := c.Compile(resource)
	return err == nil && compiled.Validate(public) == nil
}

func typedAppOption(raw any) bool {
	schema, _ := raw.(map[string]any)
	if enum, _ := schema["enum"].([]any); len(enum) != 0 {
		return true
	}
	if alternatives, _ := schema["anyOf"].([]any); len(alternatives) != 0 {
		for _, branch := range alternatives {
			if !typedAppOption(branch) {
				return false
			}
		}
		return true
	}
	switch v := schema["type"].(type) {
	case string:
		if v == "array" {
			return typedAppOption(schema["items"])
		}
		return v != "" // The compiler checks the JSON Schema type name.
	case []any:
		if slices.Contains(v, any("array")) {
			return typedAppOption(schema["items"])
		}
		return len(v) != 0
	}
	return false
}

func publicAppKey(k string) bool {
	switch k {
	case "",
		"constructor",
		"prototype",
		"env",
		"envs",
		"environments",
		"variables",
		"secrets",
		"imports",
		"outPath":
		return false
	}
	return !strings.HasPrefix(k, "_") && !strings.ContainsFunc(k, unicode.IsControl)
}

func portableAppValue(v any) bool {
	switch x := v.(type) {
	case nil, bool:
		return true
	case float64:
		return !math.IsNaN(x) && !math.IsInf(x, 0) &&
			(math.Trunc(x) != x || math.Abs(x) <= 9007199254740991)
	case string:
		return !strings.HasPrefix(x, moduleStoreRoot+"/")
	case []any:
		for _, item := range x {
			if !portableAppValue(item) {
				return false
			}
		}
	case map[string]any:
		for k, item := range x {
			if !publicAppKey(k) || !portableAppValue(item) {
				return false
			}
		}
	default:
		return false
	}
	return true
}

// Object keys are the relative patch surface. JSON sorts map keys during
// revision hashing; no current setting value belongs in this fingerprint.
func appKeyShape(value any) map[string]any {
	fields, ok := value.(map[string]any)
	if !ok || fields == nil {
		return nil
	}
	shape := make(map[string]any, len(fields))
	for k, v := range fields {
		shape[k] = appKeyShape(v)
	}
	return shape
}

func (s *Server) moduleUIConfigPatchScope(
	h http.Header,
	rt *projectRuntime,
	state map[string]any,
	id string,
) ([]string, map[string]any, error) {
	if _, present := h[http.CanonicalHeaderKey(moduleUIGrantHeader)]; !present {
		return nil, nil, nil
	}
	c, b, err := s.verifiedModuleUIGrant(h, rt, state, id, "config:patch")
	if err != nil {
		return nil, nil, err
	}
	if c.App == "" {
		return nil, nil, nil
	}
	// verifiedModuleUIGrant checked this exact projection while computing the
	// revision. Never fall through to the module config path for an app grant.
	public := b.appSettings[c.App].(map[string]any)
	return []string{"apps", c.App, c.Module}, public, nil
}
