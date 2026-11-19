package server

import (
	"crypto/sha256"
	"encoding/json"
	"maps"
	"net/http"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/structpb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
)

const maxStatusApps = 128

var specKeyPattern = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$`)

func reservedUIName(key string) bool {
	switch key {
	case "prototype", "constructor", "__proto__", "__defineGetter__", "__defineSetter__",
		"__lookupGetter__", "__lookupSetter__", "hasOwnProperty", "isPrototypeOf",
		"propertyIsEnumerable", "toLocaleString", "toString", "valueOf":
		return true
	}
	return false
}

func validSpecKey(key string) bool {
	return specKeyPattern.MatchString(key) && !reservedUIName(key)
}

func validStatusID(id string) bool {
	// These are values on stdin, not paths, object keys, or URL segments.
	if id == "" || len(id) > 128*utf8.UTFMax || !utf8.ValidString(id) || utf8.RuneCountInString(id) > 128 || strings.TrimSpace(id) != id || reservedUIName(id) {
		return false
	}
	for _, r := range id {
		if unicode.IsOneOf([]*unicode.RangeTable{unicode.Cc, unicode.Cf, unicode.Zl, unicode.Zp}, r) {
			return false
		}
	}
	return true
}

func specReference(raw any, directive, prefix string) (string, bool) {
	ref, _ := raw.(map[string]any)
	path, _ := ref[directive].(string)
	key, ok := strings.CutPrefix(path, prefix)
	return key, len(ref) == 1 && ok && validSpecKey(key)
}

type statusTargets map[string]bool // "" represents {}, never {app:""}

func pickerTargets(props, state map[string]any) (string, statusTargets, bool) {
	key, ok := specReference(props["value"], "$bindState", "/local/")
	if !ok {
		return "", nil, false
	}
	local, _ := state["local"].(map[string]any)
	initial, ok := local[key].(string)
	if !ok {
		return "", nil, false
	}
	raw := props["apps"]
	if _, ref := raw.(map[string]any); ref {
		dataKey, ok := specReference(raw, "$state", "/data/")
		if !ok {
			return "", nil, false
		}
		data, _ := state["data"].(map[string]any)
		raw = data[dataKey]
	}
	apps, ok := raw.([]any)
	if !ok || len(apps) > maxStatusApps {
		return "", nil, false
	}
	targets := make(statusTargets, len(apps))
	for _, raw := range apps {
		app, _ := raw.(string)
		if !validStatusID(app) || targets[app] {
			return "", nil, false
		}
		targets[app] = true
	}
	return key, targets, initial == "" || targets[initial]
}

func statusViewTargets(props map[string]any, pickers map[string]statusTargets) (statusTargets, bool) {
	raw, present := props["app"]
	if !present {
		return statusTargets{"": true}, true
	}
	if app, ok := raw.(string); ok {
		if app == "" {
			return nil, true // an empty selection is not an argument-less view
		}
		return statusTargets{app: true}, validStatusID(app)
	}
	key, ok := specReference(raw, "$state", "/local/")
	targets, exists := pickers[key]
	return targets, ok && exists
}

// Walk only explicit child references. Each view offers its own targets:
// two views of the same action do not authorize the union of their choices.
func statusOffers(spec, actions map[string]any) (map[string][]statusTargets, error) {
	root, _ := spec["root"].(string)
	elements, _ := spec["elements"].(map[string]any)
	if root == "" || len(elements) == 0 || len(elements) > 64 {
		return nil, invalidModuleState("invalid spec element tree")
	}
	seen := make(map[string]bool, len(elements))
	state, _ := spec["state"].(map[string]any)
	pickers := make(map[string]statusTargets)
	var views []map[string]any
	var visit func(string, int) bool
	visit = func(key string, depth int) bool {
		node, _ := elements[key].(map[string]any)
		kind, _ := node["type"].(string)
		props, ok := node["props"].(map[string]any)
		if !validSpecKey(key) || depth > 16 || seen[key] || kind == "" || !ok {
			return false
		}
		seen[key] = true
		switch kind {
		case "StatusView":
			views = append(views, props)
		case "AppPicker":
			key, targets, ok := pickerTargets(props, state)
			if _, present := pickers[key]; !ok || present {
				return false
			}
			pickers[key] = targets
		}
		if raw, present := node["children"]; present {
			// Only the host's containers expose child slots. Do not infer
			// reachability through a leaf or a future unknown component.
			children, ok := raw.([]any)
			if !ok || len(children) > len(elements) || (len(children) > 0 && kind != "Stack" && kind != "Section") {
				return false
			}
			for _, child := range children {
				id, ok := child.(string)
				if !ok || !visit(id, depth+1) {
					return false
				}
			}
		}
		return true
	}
	if !visit(root, 1) || len(seen) != len(elements) {
		return nil, invalidModuleState("invalid spec element tree or app picker")
	}
	offers := make(map[string][]statusTargets)
	for _, props := range views {
		id, _ := props["action"].(string)
		targets, ok := statusViewTargets(props, pickers)
		if !validStatusID(id) || !ok {
			return nil, invalidModuleState("invalid status action or app reference")
		}
		if action, ok := actions[id].(map[string]any); ok && (action["confirm"] == nil || action["confirm"] == "") {
			offers[id] = append(offers[id], targets)
		}
	}
	return offers, nil
}

func statusActionIDs(spec, actions map[string]any) ([]string, error) {
	offers, err := statusOffers(spec, actions)
	if err != nil {
		return nil, err
	}
	return slices.Sorted(maps.Keys(offers)), nil
}

func (targets statusTargets) offers(apps []string) bool {
	if len(apps) == 0 {
		return targets[""]
	}
	for _, app := range apps {
		if !targets[app] {
			return false
		}
	}
	return true
}

func checkStatusReview(mod, panel map[string]any, c moduleUIGrant) error {
	if !validStatusID(c.StatusAction) || len(c.StatusApps) > maxStatusApps ||
		(c.App != "" && (len(c.StatusApps) != 1 || c.StatusApps[0] != c.App)) {
		return uiGrantDenied()
	}
	seen := make(map[string]bool, len(c.StatusApps))
	for _, app := range c.StatusApps {
		if !validStatusID(app) || seen[app] {
			return uiGrantDenied()
		}
		seen[app] = true
	}
	spec, _ := panel["spec"].(map[string]any)
	actions, _ := mod["actions"].(map[string]any)
	offers, err := statusOffers(spec, actions)
	if err != nil {
		return err
	}
	if !slices.ContainsFunc(offers[c.StatusAction], func(targets statusTargets) bool { return targets.offers(c.StatusApps) }) {
		return uiGrantDenied()
	}
	// Use the normal runner's compiler and ref policy, once for all reviewed
	// targets. Dispatch still validates its actual stdin via moduleActionInput.
	action := actions[c.StatusAction].(map[string]any)
	schema, err := compileModuleActionSchema(action["argsSchema"])
	if err != nil {
		return err
	}
	args := map[string]any{}
	if len(c.StatusApps) == 0 && schema.Validate(args) != nil {
		return uiGrantDenied()
	}
	for _, app := range c.StatusApps {
		args["app"] = app
		if schema.Validate(args) != nil {
			return uiGrantDenied()
		}
	}
	return nil
}

func specGrantRevision(root, profileBin string, state, mod, p map[string]any, c moduleUIGrant) ([32]byte, error) {
	var empty [32]byte
	spec, ok := p["spec"].(map[string]any)
	if p["type"] != "PANEL_TYPE_SPEC" || !ok || p["uiBundle"] != nil {
		return empty, uiGrantDenied()
	}
	slot, validSlot := p["slot"].(string)
	apps, validApps := p["apps"].(map[string]any)
	if p["slot"] != nil && !validSlot || p["apps"] != nil && !validApps || !validPanelApp(state, slot, c.App, apps) {
		return empty, uiGrantDenied()
	}
	app, _ := apps[c.App].(map[string]any)
	actions, _ := mod["actions"].(map[string]any)
	action, ok := actions[c.StatusAction].(map[string]any)
	if !ok {
		return empty, uiGrantDenied()
	}
	script, _ := action["script"].(string)
	physicalRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return empty, err
	}
	// The sealed claims already restrict action and arguments. Bind them to
	// the exact graph and executable under which that subset was approved.
	dirs, _ := state["dirs"].(map[string]any)
	body, err := json.Marshal([]any{"spec", root, physicalRoot, c.Module, c.Panel, c.App, slot, app["enabled"],
		spec, c.StatusAction, action, declaredActionTarget(script, state, c.Module), dirs["profile"], profileBin})
	if err != nil {
		return empty, err
	}
	return sha256.Sum256(body), nil
}

func (m *moduleService) openSpecUI(root, profileBin string, state map[string]any, req *connect.Request[agentv1.OpenModuleUIRequest], mod, panel map[string]any) (*connect.Response[agentv1.OpenModuleUIResponse], error) {
	if _, bound := req.Header()[http.CanonicalHeaderKey(moduleUIGrantHeader)]; bound {
		return nil, uiGrantDenied() // no refresh or transfer, even at the same revision
	}
	c := moduleUIGrant{
		Spec: true, Module: req.Msg.GetModuleId(), Panel: req.Msg.GetPanelId(), App: req.Msg.GetAppId(),
		StatusAction: req.Msg.GetStatusAction(), StatusApps: req.Msg.GetStatusApps(), Expires: time.Now().Add(moduleUIGrantLifetime).Unix(),
	}
	if err := checkStatusReview(mod, panel, c); err != nil {
		return nil, err
	}
	revision, err := specGrantRevision(root, profileBin, state, mod, panel, c)
	if err != nil {
		return nil, err
	}
	c.Revision = revision
	token, err := m.s.encodeUIGrant(c)
	if err != nil {
		return nil, uiGrantDenied()
	}
	return moduleUIResponse(&agentv1.OpenModuleUIResponse{
		Permissions: []string{"actions:run"}, ActionIds: []string{c.StatusAction}, ReviewRevision: req.Msg.GetReviewRevision(),
	}, mod, token, c.Expires)
}

// Native calls have no UI credential. With any grant header present we must
// authorize the original grant or deny, never retry as a native action.
func (s *Server) checkActionGrant(h http.Header, rt *projectRuntime, state map[string]any, msg *agentv1.RunModuleActionRequest, profileBin string) error {
	if _, present := h[http.CanonicalHeaderKey(moduleUIGrantHeader)]; !present {
		return nil
	}
	c, err := s.decodeUIGrant(h)
	if err != nil || c.Module != msg.GetModuleId() {
		return uiGrantDenied()
	}
	if !c.Spec {
		b, err := verifiedCustomBundle(c, rt, state, c.Module, "actions:run", profileBin)
		if err != nil || !slices.Contains(b.actionIDs, msg.GetActionId()) {
			return uiGrantDenied()
		}
		return nil
	}
	if rt == nil || c.StatusAction == "" || c.StatusAction != msg.GetActionId() || !validStatusArgs(msg.GetArgs(), c) {
		return uiGrantDenied()
	}
	mod, p, err := evaluatedUIPanel(state, c.Module, c.Panel)
	if err != nil {
		return uiGrantDenied()
	}
	revision, err := specGrantRevision(rt.root, profileBin, state, mod, p, c)
	if err != nil || revision != c.Revision {
		return uiGrantDenied()
	}
	return nil
}

func validStatusArgs(args *structpb.Struct, c moduleUIGrant) bool {
	fields := args.GetFields()
	if len(fields) == 0 {
		return c.App == "" && len(c.StatusApps) == 0
	}
	app, ok := fields["app"].GetKind().(*structpb.Value_StringValue)
	return len(fields) == 1 && ok && (c.App == "" || app.StringValue == c.App) && slices.Contains(c.StatusApps, app.StringValue)
}
