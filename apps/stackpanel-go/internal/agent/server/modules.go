package server

import (
	"context"
	"encoding/json"
	"errors"
	"strings"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// loadModuleState is shared by metadata, actions, UI and registry services.
// Never fall back to the daemon's shell/profile or a previously selected project.
func loadModuleState(ctx context.Context, rt *projectRuntime) (map[string]any, error) {
	if rt == nil || rt.root == "" {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("no project selected"),
		)
	}
	eval := rt.evalModuleState
	if eval == nil {
		eval = nixeval.EvalModuleState
	}
	data, err := eval(ctx, rt.root)
	if err != nil {
		return nil, moduleEvalError(ctx, err)
	}
	var state map[string]any
	if err := json.Unmarshal(data, &state); err != nil || state == nil {
		return nil, invalidModuleState("invalid stackpanelSerializable result")
	}
	return state, nil
}

func moduleEvalError(ctx context.Context, err error) error {
	if errors.Is(err, context.DeadlineExceeded) ||
		errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return connect.NewError(connect.CodeDeadlineExceeded, context.DeadlineExceeded)
	}
	if errors.Is(err, context.Canceled) || errors.Is(ctx.Err(), context.Canceled) {
		return connect.NewError(connect.CodeCanceled, context.Canceled)
	}
	// Nix stderr can include snippets of private project configuration.
	return invalidModuleState(
		"module evaluation failed; check the project's flake configuration",
	)
}

func invalidModuleState(message string) error {
	return connect.NewError(connect.CodeFailedPrecondition, errors.New(message))
}

func evaluatedModules(state map[string]any) ([]any, error) {
	list, ok := state["modulesListAll"].([]any)
	if !ok {
		return nil, invalidModuleState("project does not expose modulesListAll")
	}
	return list, nil
}

func findModule(state map[string]any, id string) (map[string]any, error) {
	if strings.TrimSpace(id) == "" {
		return nil, connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("module_id is required"),
		)
	}
	list, err := evaluatedModules(state)
	if err != nil {
		return nil, err
	}
	for _, item := range list {
		m, ok := item.(map[string]any)
		if !ok {
			return nil, invalidModuleState("invalid modulesListAll entry")
		}
		if m["id"] == id {
			return m, nil
		}
	}
	return nil, connect.NewError(
		connect.CodeNotFound,
		errors.New("module not found in project"),
	)
}

func moduleOptionPath(module map[string]any, field string) ([]string, error) {
	id, _ := module["id"].(string)
	declared, ok := module[field].(string)
	if !ok || declared == "" || strings.HasPrefix(declared, "stackpanel.") {
		return nil, invalidModuleState("invalid module option path")
	}
	parts := strings.Split(declared, ".")
	for _, p := range parts {
		if nixdata.ValidateEntityName(p) != nil || p == "imports" ||
			strings.HasPrefix(p, "_") {
			return nil, invalidModuleState("invalid declared module option path")
		}
	}
	switch parts[0] {
	case "variables", "secrets", "users", "apps", "registries":
		// The owner can toggle its declared boolean enable switch. Neither its
		// settings RPC nor another module can select data within this namespace.
		if field == "enablePath" && len(parts) == 2 && parts[0] == id &&
			parts[1] == "enable" {
			break
		}
		return nil, invalidModuleState("module option path targets a protected namespace")
	case "modules":
		if len(parts) < 3 || parts[1] != id {
			return nil, invalidModuleState("module option path is outside this module")
		}
	}
	return parts, nil
}

// decodeModuleProjection only exposes fields in the public protobuf schema.
// Unknown Nix metadata (including executable paths) stays on the agent.
func decodeModuleProjection(data any, target proto.Message) error {
	b, err := json.Marshal(data)
	if err == nil {
		err = (protojson.UnmarshalOptions{DiscardUnknown: true}).Unmarshal(b, target)
	}
	if err != nil {
		return invalidModuleState("invalid evaluated module metadata")
	}
	return nil
}

func moduleOutputData(
	ctx context.Context,
	rt *projectRuntime,
	id string,
) (map[string]any, error) {
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return nil, err
	}
	if _, err := findModule(state, id); err != nil {
		return nil, err
	}
	outputs, _ := state["moduleOutputs"].(map[string]any)
	out, ok := outputs[id].(map[string]any)
	if !ok {
		return nil, invalidModuleState(
			"project does not expose this module's attributed outputs",
		)
	}
	out["moduleId"] = id
	// Only expose whether a proxy is offered, not its internal port or URL.
	services, _ := out["services"].([]any)
	for _, item := range services {
		svc, ok := item.(map[string]any)
		if !ok {
			return nil, invalidModuleState("invalid attributed service")
		}
		proxy, _ := svc["proxy"].(map[string]any)
		svc["proxyEnabled"], _ = proxy["enable"].(bool)
	}
	return out, nil
}
