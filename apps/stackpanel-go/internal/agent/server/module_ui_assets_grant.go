package server

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"maps"
	"net/http"
	"path/filepath"
	"slices"
	"time"

	"connectrpc.com/connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

// The host keeps this credential outside the frame. It supplements (never
// replaces) agent authentication. It is not interchangeable with an asset
// ticket and is never accepted by the static asset handler.
const (
	moduleUIGrantHeader   = "X-Stackpanel-UI-Grant"
	moduleUIExpiryHeader  = "X-Stackpanel-UI-Expires-At"
	moduleUIGrantLifetime = time.Hour
	moduleUIGrantPurpose  = "stackpanel-ui-operation-grant-v1"
	// Independent aggregate transport bound, including AEAD and base64;
	// reject oversized Unicode target sets rather than returning an unusable token.
	maxUIGrantBytes = 32 << 10
)

type moduleUIGrant struct {
	Spec           bool     `json:"s,omitempty"` // absent on iframe grants
	Module         string   `json:"m"`
	Panel          string   `json:"p"`
	App            string   `json:"a"`
	StatusAction   string   `json:"x,omitempty"`
	StatusApps     []string `json:"t,omitempty"`
	ReviewRevision string   `json:"v,omitempty"`
	Revision       [32]byte `json:"r"`
	Expires        int64    `json:"e"`
}

func uiGrantDenied() error {
	return connect.NewError(
		connect.CodePermissionDenied,
		errors.New("extension grant invalid or changed; reopen the panel"),
	)
}

// Encoding/json encodes string-keyed maps in sorted order. Include authority
// and resolved targets, not ordinary live settings or action results. Changing
// a value through the settings form need not revoke an otherwise unchanged UI.
func uiGrantRevision(
	root string,
	state map[string]any,
	id, panel, app string,
	b *moduleBundle,
	link userconfig.LinkedModule,
	profileBin string,
) ([32]byte, error) {
	if !validPanelApp(state, b.slot, app, b.apps) {
		return [32]byte{}, uiGrantDenied()
	}
	physicalRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return [32]byte{}, err
	}
	mod := b.module
	owned, _ := state["moduleOutputs"].(map[string]any)
	outputs, _ := owned[id].(map[string]any)
	services, _ := state["services"].(map[string]any)
	svcTargets := make(map[string]any)
	for k, v := range services {
		svc, _ := v.(map[string]any)
		if svc["module"] == id {
			svcTargets[k] = []any{svc["enable"], svc["proxy"]}
		}
	}
	actions, _ := mod["actions"].(map[string]any)
	actionTargets := make(map[string]any, len(b.actionIDs))
	for _, k := range b.actionIDs {
		actionTargets[k] = actions[k]
	}
	appDef, _ := b.apps[app].(map[string]any)
	public, err := b.writableApp(app)
	if err != nil {
		return [32]byte{}, err
	}
	var appSchema any
	if public != nil {
		appSchema = b.appSchemas[app]
	}
	// Only dirs.profile selects the action executable environment. dirs.config
	// can point into a new flake source path after an unrelated checkout edit.
	dirs, _ := state["dirs"].(map[string]any)
	data, err := json.Marshal([]any{
		root,
		physicalRoot,
		id,
		panel,
		app,
		appDef["enabled"],
		b.slot,
		appKeyShape(public),
		appSchema,
		link.Path,
		link.UIDevURL,
		b.root,
		b.entry,
		b.drv,
		b.permissions,
		mod["configPath"],
		mod["configSchema"],
		actionTargets,
		outputs["scripts"],
		dirs["profile"],
		profileBin,
		svcTargets,
	})
	if err != nil {
		return [32]byte{}, err
	}
	return sha256.Sum256(data), nil
}

func effectiveUIActions(
	selector any,
	module map[string]any,
	permissions []string,
) []string {
	if !slices.Contains(permissions, "actions:run") {
		return nil
	}
	actions, _ := module["actions"].(map[string]any)
	if selector == nil {
		return slices.Sorted(maps.Keys(actions))
	}
	allowed, _ := selector.([]any)
	var result []string
	for _, v := range allowed {
		if id, ok := v.(string); ok && actions[id] != nil {
			result = append(result, id)
		}
	}
	slices.Sort(result)
	return slices.Compact(result)
}

func (s *Server) encodeUIGrant(c moduleUIGrant) (string, error) {
	aead, err := s.uiCapabilityCipher(moduleUIGrantPurpose)
	if err != nil {
		return "", err
	}
	msg, err := json.Marshal(c)
	if err != nil {
		return "", err
	}
	if base64.RawURLEncoding.EncodedLen(len(msg)+aead.Overhead()) > maxUIGrantBytes {
		return "", uiGrantDenied()
	}
	return base64.RawURLEncoding.EncodeToString(aead.Seal(nil, nil, msg, nil)), nil
}

func (s *Server) decodeUIGrant(header http.Header) (moduleUIGrant, error) {
	var c moduleUIGrant
	v := header.Values(moduleUIGrantHeader)
	if len(v) != 1 || len(v[0]) > maxUIGrantBytes {
		return c, uiGrantDenied()
	}
	sealed, err := base64.RawURLEncoding.Strict().DecodeString(v[0])
	if err != nil {
		return c, uiGrantDenied()
	}
	aead, err := s.uiCapabilityCipher(moduleUIGrantPurpose)
	if err != nil || len(sealed) < aead.Overhead() {
		return c, uiGrantDenied()
	}
	msg, err := aead.Open(nil, nil, sealed, nil)
	if err != nil || json.Unmarshal(msg, &c) != nil || c.Expires <= time.Now().Unix() || (!c.Spec && customUIDisabled()) {
		return c, uiGrantDenied()
	}
	return c, nil
}

func (s *Server) checkModuleProxyGrant(
	header http.Header,
	rt *projectRuntime,
	state map[string]any,
	moduleID string,
) error {
	if _, present := header[http.CanonicalHeaderKey(moduleUIGrantHeader)]; !present {
		return nil
	}
	_, _, err := s.verifiedModuleUIGrant(header, rt, state, moduleID, "service:proxy")
	return err
}

func (s *Server) verifiedModuleUIGrant(
	header http.Header,
	rt *projectRuntime,
	state map[string]any,
	moduleID, operation string,
) (moduleUIGrant, *moduleBundle, error) {
	c, err := s.decodeUIGrant(header)
	if err != nil {
		return c, nil, err
	}
	if rt == nil {
		return c, nil, uiGrantDenied()
	}
	b, err := verifiedCustomBundle(c, rt, state, moduleID, operation, moduleActionProfile(rt.root, moduleStoreRoot, state))
	return c, b, err
}

func verifiedCustomBundle(c moduleUIGrant, rt *projectRuntime, state map[string]any, moduleID, operation, profileBin string) (*moduleBundle, error) {
	if c.Spec || rt == nil || c.Module != moduleID {
		return nil, uiGrantDenied()
	}
	b, err := evaluatedModuleBundle(state, moduleID, c.Panel, moduleStoreRoot)
	if err != nil || !slices.Contains(b.permissions, operation) {
		return nil, uiGrantDenied()
	}
	links, err := userconfig.LoadLinkedModules(rt.root)
	if err != nil {
		return nil, uiGrantDenied()
	}
	digest, err := uiGrantRevision(
		rt.root,
		state,
		moduleID,
		c.Panel,
		c.App,
		b,
		links[moduleID],
		profileBin,
	)
	if err != nil || digest != c.Revision {
		return nil, uiGrantDenied()
	}
	return b, nil
}
