package server

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/structpb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

const moduleStoreRoot = "/nix/store"

var (
	moduleRouteID = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$`)
	// The package must be a single Nix output, not a path into another output.
	moduleStoreName = regexp.MustCompile(
		`^[0-9abcdfghijklmnpqrsvwxyz]{32}-[a-zA-Z0-9+._?=-]+$`,
	)
	uiAuthority = regexp.MustCompile(
		`^([a-zA-Z0-9.-]+|\[[a-fA-F0-9:]+\])(:[0-9]{1,5})?$`,
	)
)

func (s *Server) mountModuleCapabilities(mux *http.ServeMux) {
	const base = "/api/v1/modules/{module}/"
	mux.HandleFunc(
		base+"services/{service}/proxy/{rest...}",
		s.withModuleProject(s.handleModuleProxy),
	)
	mux.HandleFunc(base+"ui/{panel}/{rest...}", s.withModuleProject(s.handleModuleAsset))
	// The ticket route intentionally does not enter the agent auth/CORS stack:
	// an opaque iframe presents a bundle-read capability, never an agent credential.
	mux.HandleFunc(base+"ui/{panel}/_ticket/{ticket}/{rest...}", s.handleTicketAsset)
}

func (s *Server) withModuleProject(next http.HandlerFunc) http.HandlerFunc {
	return s.withCORS(s.withAllowedOrigin(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if err := (authInterceptor{valid: s.isValidToken}).check("", r.Header); err != nil {
			s.writeAPIError(w, http.StatusUnauthorized, "valid bearer credential required")
			return
		}
		id := strings.TrimSpace(r.Header.Get(projectHeader))
		if id == "" || len(r.Header.Values(projectHeader)) != 1 {
			s.writeAPIError(w, http.StatusBadRequest, "explicit project required")
			return
		}
		rt, err := s.requestRuntime(r.Header)
		if err != nil {
			s.writeAPIError(w, http.StatusNotFound, "project unavailable")
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), runtimeKey{}, rt)))
	}))
}

type moduleBundle struct {
	root, entry, drv string
	permissions      []string
	actionIDs        []string
	apps             map[string]any
	module           map[string]any
	slot             string
	appSettings      map[string]any
	appSchemas       map[string]any
}

func customUIDisabled() bool { return os.Getenv("STACKPANEL_DISABLE_CUSTOM_UI") == "1" }

// Resolve ownership and visibility from the same current project snapshot used
// for dispatch. A request never supplies the document, package, or executable.
func evaluatedUIPanel(state map[string]any, module, panel string) (mod, p map[string]any, err error) {
	unavailable := connect.NewError(
		connect.CodeNotFound,
		errors.New("module panel unavailable"),
	)
	if !moduleRouteID.MatchString(module) || !moduleRouteID.MatchString(panel) {
		return nil, nil, unavailable
	}
	mod, err = findModule(state, module)
	if err != nil || mod["enabled"] != true {
		return nil, nil, unavailable
	}
	panels, _ := state["panelsList"].([]any)
	for _, item := range panels {
		entry, _ := item.(map[string]any)
		if entry["id"] != panel {
			continue
		}
		if p != nil || entry["module"] != module || entry["enabled"] != true {
			return nil, nil, unavailable
		}
		p = entry
	}
	if p == nil {
		return nil, nil, unavailable
	}
	return mod, p, nil
}

func evaluatedModuleBundle(state map[string]any, module, panel, storeRoot string) (*moduleBundle, error) {
	mod, p, err := evaluatedUIPanel(state, module, panel)
	if err != nil {
		return nil, err
	}
	return customModuleBundle(mod, p, storeRoot)
}

func customModuleBundle(mod, p map[string]any, storeRoot string) (*moduleBundle, error) {
	if p["type"] != "PANEL_TYPE_CUSTOM" {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("custom panel unavailable"))
	}
	if customUIDisabled() {
		return nil, connect.NewError(connect.CodePermissionDenied, errors.New("custom UI disabled by agent operator"))
	}
	bundle, _ := p["uiBundle"].(map[string]any)
	root, _ := bundle["package"].(string)
	entry, _ := bundle["entry"].(string)
	if !validModulePackage(root, storeRoot) || !validAssetPath(entry) {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("invalid UI bundle declaration"),
		)
	}
	result := &moduleBundle{root: root, entry: entry, module: mod}
	result.drv, _ = bundle["drvPath"].(string)
	apps, validApps := p["apps"].(map[string]any)
	slot, validSlot := p["slot"].(string)
	if p["apps"] != nil && !validApps || p["slot"] != nil && !validSlot {
		return nil, uiGrantDenied()
	}
	result.apps, result.slot = apps, slot
	result.appSettings, _ = bundle["appSettings"].(map[string]any)
	result.appSchemas, _ = bundle["appSchemas"].(map[string]any)
	grants, _ := bundle["permissions"].([]any)
	for _, grant := range grants {
		switch grant {
		case "config:read", "config:patch", "actions:run", "service:proxy":
			result.permissions = append(result.permissions, grant.(string))
		}
	}
	result.actionIDs = effectiveUIActions(bundle["actionIds"], mod, result.permissions)
	return result, nil
}

func validModulePackage(root, storeRoot string) bool {
	return root == filepath.Join(storeRoot, filepath.Base(root)) &&
		moduleStoreName.MatchString(filepath.Base(root))
}

func requestModuleBundle(
	ctx context.Context,
	module, panel, storeRoot string,
) (*moduleBundle, error) {
	rt := runtimeFor(ctx)
	if rt == nil {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("project required"),
		)
	}
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return nil, err
	}
	return evaluatedModuleBundle(state, module, panel, storeRoot)
}

func (m *moduleService) OpenModuleUI(
	ctx context.Context,
	req *connect.Request[agentv1.OpenModuleUIRequest],
) (*connect.Response[agentv1.OpenModuleUIResponse], error) {
	return m.openModuleUI(ctx, req, moduleStoreRoot)
}

func (m *moduleService) openModuleUI(
	ctx context.Context,
	req *connect.Request[agentv1.OpenModuleUIRequest],
	storeRoot string,
) (*connect.Response[agentv1.OpenModuleUIResponse], error) {
	module, panel := req.Msg.GetModuleId(), req.Msg.GetPanelId()
	rt := runtimeFor(ctx)
	state, err := loadModuleState(ctx, rt)
	if err != nil {
		return nil, err
	}
	mod, p, err := evaluatedUIPanel(state, module, panel)
	if err != nil {
		return nil, err
	}
	root := rt.root
	origin := req.Header().Get("Origin")
	if !validStudioOrigin(origin) {
		return nil, connect.NewError(
			connect.CodePermissionDenied,
			errors.New("invalid embedding origin"),
		)
	}
	// Recompute the host's displayed review against this fresh evaluation.
	// No package realization, ticket issuance, HMR launch or authority before
	// this check. Only an already sealed config-read grant can refresh below.
	var profileBin string
	var links map[string]userconfig.LinkedModule
	_, bound := req.Header()[http.CanonicalHeaderKey(moduleUIGrantHeader)]
	if bound {
		if p["type"] != "PANEL_TYPE_CUSTOM" || req.Msg.GetReviewRevision() != "" {
			return nil, uiGrantDenied()
		}
		links, err = userconfig.LoadLinkedModules(root)
		if err != nil {
			return nil, uiGrantDenied()
		}
		profileBin = moduleActionProfile(root, storeRoot, state)
	} else {
		if req.Msg.GetReviewRevision() == "" {
			return nil, uiGrantDenied()
		}
		snapshot := newUIReviewSnapshot(root, storeRoot, state, m.s.config.Port)
		profileBin, links = snapshot.profileBin, snapshot.links
		review, _ := snapshot.review(mod, p)
		if review == "" || review != req.Msg.GetReviewRevision() {
			return nil, uiGrantDenied()
		}
	}
	if p["type"] == "PANEL_TYPE_SPEC" {
		return m.openSpecUI(root, profileBin, state, req, mod, p)
	}
	if req.Msg.GetStatusAction() != "" || len(req.Msg.GetStatusApps()) != 0 {
		return nil, uiGrantDenied()
	}
	bundle, err := customModuleBundle(mod, p, storeRoot)
	if err != nil {
		return nil, err
	}
	// Use only machine-local linked state for this project and module. HMR
	// intentionally does not require a prebuilt production bundle.
	appID := req.Msg.GetAppId()
	revision, err := uiGrantRevision(
		root,
		state,
		module,
		panel,
		appID,
		bundle,
		links[module],
		profileBin,
	)
	if err != nil {
		return nil, uiGrantDenied()
	}
	grant := moduleUIGrant{
		Module:         module,
		ReviewRevision: req.Msg.GetReviewRevision(),
		Panel:          panel,
		App:            appID,
		Revision:       revision,
		Expires:        time.Now().Add(moduleUIGrantLifetime).Unix(),
	}
	var token string
	if bound {
		// Refreshing settings reads the original grant only. Never extend
		// its lifetime or transfer a previous frame to the new revision.
		previous, err := m.s.decodeUIGrant(req.Header())
		if err != nil || previous.Spec || previous.ReviewRevision == "" || previous.Revision != revision || previous.Module != module ||
			previous.Panel != panel ||
			previous.App != appID ||
			!slices.Contains(bundle.permissions, "config:read") {
			return nil, uiGrantDenied()
		}
		grant, token = previous, req.Header().Get(moduleUIGrantHeader)
	} else {
		token, err = m.s.encodeUIGrant(grant)
		if err != nil {
			return nil, uiGrantDenied()
		}
	}
	res := &agentv1.OpenModuleUIResponse{
		ReviewRevision: grant.ReviewRevision,
		Permissions:    bundle.permissions,
		ActionIds:      bundle.actionIDs,
	}
	if slices.Contains(bundle.permissions, "config:read") {
		var settings map[string]any
		if appID == "" {
			settings, _ = mod["settings"].(map[string]any)
		} else if slices.Contains(bundle.permissions, "config:patch") {
			// uiGrantRevision validated the writable projection for this exact app.
			settings, _ = bundle.appSettings[appID].(map[string]any)
		} else {
			app, _ := bundle.apps[appID].(map[string]any)
			settings, _ = app["config"].(map[string]any)
		}
		if settings == nil {
			return nil, invalidModuleState("panel settings projection missing")
		}
		res.Settings, err = structpb.NewStruct(settings)
		if err != nil {
			return nil, invalidModuleState("invalid panel settings")
		}
	}
	if !bound {
		res.Url, res.DevUrl, err = m.launchCustomBundle(ctx, root, origin, module, panel, bundle, links[module])
		if err != nil {
			return nil, err
		}
	}
	return moduleUIResponse(res, bundle.module, token, grant.Expires)
}

func (m *moduleService) launchCustomBundle(ctx context.Context, root, origin, module, panel string, bundle *moduleBundle, link userconfig.LinkedModule) (string, string, error) {
	var devURL string
	if link.Path != "" && link.UIDevURL != "" {
		if !validModuleDevURL(link.UIDevURL, m.s.config.Port) {
			return "", "", connect.NewError(connect.CodeFailedPrecondition, errors.New("invalid linked UI server"))
		}
		devURL = link.UIDevURL
	} else {
		if bundle.drv != "" {
			if err := ensureModuleOutput(ctx, root, bundle.root, bundle.drv); err != nil {
				return "", "", connect.NewError(connect.CodeFailedPrecondition, err)
			}
		}
		entry, _, err := openBundleAsset(bundle.root, bundle.entry)
		if err != nil {
			return "", "", connect.NewError(connect.CodeFailedPrecondition, errors.New("UI bundle entry is not realized or is outside its package"))
		}
		entry.Close()
	}
	claims := uiTicketClaims{
		Project: userconfig.GenerateProjectID(root), Package: bundle.root, Parent: origin,
		Expires: time.Now().Add(uiTicketLifetime).Unix(),
	}
	prefix := moduleUIBase(module, panel)
	ticket, err := m.s.sealUITicket(prefix, claims)
	if err != nil {
		return "", "", connect.NewError(connect.CodeInternal, errors.New("cannot issue UI ticket"))
	}
	return prefix + "_ticket/" + ticket + "/" + (&url.URL{Path: bundle.entry}).EscapedPath(), devURL, nil
}

func moduleUIResponse(res *agentv1.OpenModuleUIResponse, mod map[string]any, token string, expires int64) (*connect.Response[agentv1.OpenModuleUIResponse], error) {
	if len(res.ActionIds) != 0 {
		actions, _ := mod["actions"].(map[string]any)
		res.Actions = make(map[string]*agentv1.ModuleAction, len(res.ActionIds))
		for _, id := range res.ActionIds {
			action := &agentv1.ModuleAction{}
			if err := decodeModuleProjection(actions[id], action); err != nil {
				return nil, err
			}
			res.Actions[id] = action
		}
	}
	response := connect.NewResponse(res)
	response.Header().Set("Cache-Control", "no-store")
	response.Header().Set(moduleUIGrantHeader, token)
	response.Header().Set(moduleUIExpiryHeader, strconv.FormatInt(expires, 10))
	return response, nil
}

func moduleUIBase(module, panel string) string {
	return "/api/v1/modules/" + module + "/ui/" + panel + "/"
}

func validStudioOrigin(origin string) bool {
	if origin == "" {
		return true
	}
	u, err := url.Parse(origin)
	return err == nil && (u.Scheme == "http" || u.Scheme == "https") &&
		uiAuthority.MatchString(u.Host) &&
		origin == u.Scheme+"://"+u.Host
}

func validModuleDevURL(raw string, agentPort int) bool {
	if userconfig.ValidateUIDevURL(raw) != nil {
		return false
	}
	u, err := url.Parse(raw)
	if err != nil || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" {
		return false
	}
	port := 80
	if u.Scheme == "https" {
		port = 443
	}
	if u.Port() != "" {
		port, err = strconv.Atoi(u.Port())
	}
	return err == nil && port > 0 && port <= 65535 && port != agentPort
}
