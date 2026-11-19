package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"connectrpc.com/connect"
	"github.com/santhosh-tekuri/jsonschema/v6"
	"google.golang.org/protobuf/types/known/structpb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
)

func (m *moduleService) RunModuleAction(
	ctx context.Context,
	req *connect.Request[agentv1.RunModuleActionRequest],
	stream *connect.ServerStream[agentv1.RunModuleActionResponse],
) error {
	return m.runModuleActionWithHeader(ctx, moduleStoreRoot, req.Header(), req.Msg, stream.Send)
}

func (m *moduleService) runModuleAction(
	ctx context.Context,
	msg *agentv1.RunModuleActionRequest,
	send func(*agentv1.RunModuleActionResponse) error,
) error {
	return m.runModuleActionWithHeader(ctx, moduleStoreRoot, nil, msg, send)
}

func (m *moduleService) runModuleActionWithHeader(
	ctx context.Context,
	store string,
	header http.Header,
	msg *agentv1.RunModuleActionRequest,
	send func(*agentv1.RunModuleActionResponse) error,
) error {
	rt := runtimeFor(ctx)
	if rt == nil || !filepath.IsAbs(rt.root) {
		return connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("module action requires a project runtime"),
		)
	}
	if msg.GetModuleId() == "" || msg.GetActionId() == "" {
		return connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("module_id and action_id are required"),
		)
	}
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return err
	}
	// Pin the same immutable environment for the grant check and execution;
	// do not resolve the project's mutable profile symlink again after approval.
	profileBin := moduleActionProfile(rt.root, store, state)
	if err := m.s.checkActionGrant(header, rt, state, msg, profileBin); err != nil {
		return err
	}
	return runEvaluatedModuleAction(ctx, rt.root, store, profileBin, state, msg, send)
}

func runEvaluatedModuleAction(
	ctx context.Context,
	root, store, profileBin string,
	state map[string]any,
	msg *agentv1.RunModuleActionRequest,
	send func(*agentv1.RunModuleActionResponse) error,
) error {
	id := msg.GetModuleId()
	module, err := findModule(state, id)
	if err != nil {
		return err
	}
	if enabled, _ := module["enabled"].(bool); !enabled {
		return connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("module is not enabled"),
		)
	}
	actions, _ := module["actions"].(map[string]any)
	action, ok := actions[msg.GetActionId()].(map[string]any)
	if !ok {
		return connect.NewError(
			connect.CodeNotFound,
			errors.New("module action not declared"),
		)
	}
	mode, _ := action["outputMode"].(string)
	if mode != "stream" && mode != "json" {
		return connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("invalid action outputMode"),
		)
	}
	stdin, err := moduleActionInput(action["argsSchema"], msg.GetArgs())
	if err != nil {
		return err
	}

	script, _ := action["script"].(string)
	if drvPath, _ := action["scriptDrvPath"].(string); drvPath != "" &&
		inModuleActionStore(script, store) {
		name, _, _ := strings.Cut(strings.TrimPrefix(script, store+"/"), "/")
		if err := ensureModuleOutput(
			ctx,
			root,
			filepath.Join(store, name),
			drvPath,
		); err != nil {
			if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
				return err
			}
			return connect.NewError(connect.CodeFailedPrecondition, err)
		}
	}
	path, err := moduleActionExecutable(script, store, profileBin, state, id)
	if err != nil {
		return connect.NewError(connect.CodeFailedPrecondition, err)
	}
	return execModuleAction(ctx, root, path, profileBin, mode, stdin, send)
}

// Resolve the Nix buildEnv link that devshell/profile.nix installs in this
// project's state directory. Do not consult the agent's current devshell.
func moduleActionProfile(root, store string, state map[string]any) string {
	dir := ".stack/profile"
	if dirs, ok := state["dirs"].(map[string]any); ok {
		if v, ok := dirs["profile"].(string); ok {
			dir = v
		}
	}
	if !filepath.IsLocal(dir) {
		return ""
	}
	bin, err := filepath.EvalSymlinks(filepath.Join(root, dir, "profile", "bin"))
	if err != nil || !inModuleActionStore(bin, store) ||
		strings.ContainsRune(bin, os.PathListSeparator) {
		return ""
	}
	return bin
}

func inModuleActionStore(path, store string) bool {
	rel, ok := strings.CutPrefix(path, store+string(filepath.Separator))
	name, _, _ := strings.Cut(rel, string(filepath.Separator))
	return ok && filepath.Clean(path) == path && moduleStoreName.MatchString(name)
}

func moduleActionExecutable(
	script, store, profileBin string,
	state map[string]any,
	moduleID string,
) (string, error) {
	declared := declaredActionTarget(script, state, moduleID)
	if !inModuleActionStore(declared, store) {
		return "", errors.New("action script has no declared Nix store executable")
	}
	path, err := filepath.EvalSymlinks(declared)
	if err != nil || !inModuleActionStore(path, store) {
		return "", errors.New("action executable is not realized in the Nix store")
	}
	if !filepath.IsAbs(script) {
		if profileBin == "" {
			return "", errors.New("project profile is not realized")
		}
		linked, err := filepath.EvalSymlinks(filepath.Join(profileBin, script))
		if err != nil || linked != path {
			return "", errors.New(
				"project profile does not contain the evaluated module script",
			)
		}
	}
	fi, err := os.Stat(path)
	if err != nil || !fi.Mode().IsRegular() || fi.Mode().Perm()&0o111 == 0 {
		return "", errors.New("declared action target is not an executable file")
	}
	// Execute the immutable target, never the mutable project symlink.
	return path, nil
}

// A bare script name must resolve through this module's own evaluated outputs.
// Use precisely the same declaration to fingerprint and select the executable.
func declaredActionTarget(script string, state map[string]any, moduleID string) string {
	if filepath.IsAbs(script) {
		return script
	}
	if script == "" || script == "." || script == ".." || filepath.Base(script) != script {
		return ""
	}
	outputs, _ := state["moduleOutputs"].(map[string]any)
	owned, _ := outputs[moduleID].(map[string]any)
	scripts, _ := owned["scripts"].([]any)
	for _, item := range scripts {
		entry, _ := item.(map[string]any)
		if entry["name"] == script {
			path, _ := entry["binPath"].(string)
			return path
		}
	}
	return ""
}

// Check the whole document, not just eagerly compiled branches: references
// can target arbitrary subschemas by JSON pointer. A loader alone would
// still allow URL references to embedded metaschemas or sibling $id values.
func moduleActionLocalRefs(v any) bool {
	switch obj := v.(type) {
	case map[string]any:
		for k, child := range obj {
			switch k {
			case "$ref", "$dynamicRef", "$recursiveRef":
				if ref, ok := child.(string); ok && ref != "" && !strings.HasPrefix(ref, "#") {
					return false
				}
			}
			if !moduleActionLocalRefs(child) {
				return false
			}
		}
	case []any:
		for _, child := range obj {
			if !moduleActionLocalRefs(child) {
				return false
			}
		}
	}
	return true
}

func compileModuleActionSchema(rawSchema any) (*jsonschema.Schema, error) {
	schema, ok := rawSchema.(map[string]any)
	if !ok {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("invalid action argsSchema"),
		)
	}
	if !moduleActionLocalRefs(schema) {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("external refs are not permitted in action argsSchema"),
		)
	}
	const resource = "urn:stackpanel:action-args"
	compiler := jsonschema.NewCompiler()
	compiler.UseLoader(
		nil,
	) // local fragments and built-in metaschemas only; no file/network I/O
	if err := compiler.AddResource(resource, schema); err != nil {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			fmt.Errorf("invalid action argsSchema: %w", err),
		)
	}
	compiled, err := compiler.Compile(resource)
	if err != nil {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			fmt.Errorf("invalid action argsSchema: %w", err),
		)
	}
	return compiled, nil
}

func moduleActionInput(rawSchema any, args *structpb.Struct) ([]byte, error) {
	compiled, err := compileModuleActionSchema(rawSchema)
	if err != nil {
		return nil, err
	}
	obj := args.AsMap() // an omitted Struct becomes the empty object
	if err := compiled.Validate(obj); err != nil {
		return nil, connect.NewError(
			connect.CodeInvalidArgument,
			fmt.Errorf("invalid action arguments: %w", err),
		)
	}
	b, err := json.Marshal(obj)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}
	return append(b, '\n'), nil
}
