package server

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"maps"
	"net/netip"
	"net/url"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

// A review is a comparison value, not a credential. GetNixConfig and Open
// each build one snapshot from their own evaluation. projectConfig inherits
// modulesListAll (including script/scriptDrvPath), moduleOutputs (including
// scripts[].binPath), and panelsList *verbatim* from projectState. Do not
// substitute the protobuf ListModules projection or do a second eval here.
// The two evaluations differ for apps/services: select only common authority
// fields, not the full editor config with private service/app environments.
type uiReviewSnapshot struct {
	profileBin string
	links      map[string]userconfig.LinkedModule // nil iff the load failed
	storeRoot  string
	agentPort  int
	project    string // hash of inputs shared by every panel
	owners     map[string]*uiReviewOwner
	panels     map[string]map[string]any
}

type uiReviewOwner struct {
	module   map[string]any
	outputs  map[string]any
	services map[string]any
	// Computed only for owners of executable panels. Reuse across their panels.
	digest      string
	scriptPaths map[string]string
}

// encoding/json sorts string-keyed maps, including nested evaluated records.
// Keep list order: declaredActionTarget, for example, uses the first match.
func uiReviewHash(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		return ""
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func newUIReviewSnapshot(root, storeRoot string, state map[string]any, agentPort int) *uiReviewSnapshot {
	links, err := userconfig.LoadLinkedModules(root)
	if err == nil && links == nil {
		links = map[string]userconfig.LinkedModule{}
	}
	s := &uiReviewSnapshot{
		links: links, profileBin: moduleActionProfile(root, storeRoot, state), storeRoot: storeRoot, agentPort: agentPort,
		owners: make(map[string]*uiReviewOwner), panels: make(map[string]map[string]any),
	}
	physicalRoot, err := filepath.EvalSymlinks(root)
	if err != nil || !filepath.IsAbs(physicalRoot) {
		return s
	}
	dirs, _ := state["dirs"].(map[string]any)
	apps, _ := state["apps"].(map[string]any)
	enabledApps := make(map[string]bool, len(apps))
	for id, raw := range apps {
		app, _ := raw.(map[string]any)
		enabledApps[id] = app["enable"] == true
	}
	s.project = uiReviewHash([]any{"stackpanel-ui-review-v1", root, physicalRoot, dirs["profile"], s.profileBin, enabledApps})

	outputs, _ := state["moduleOutputs"].(map[string]any)
	modules, _ := state["modulesListAll"].([]any)
	for _, raw := range modules {
		mod, _ := raw.(map[string]any)
		id, _ := mod["id"].(string)
		if _, duplicate := s.owners[id]; duplicate || mod["enabled"] != true || !moduleRouteID.MatchString(id) {
			s.owners[id] = nil
			continue
		}
		owned, _ := outputs[id].(map[string]any)
		s.owners[id] = &uiReviewOwner{module: mod, outputs: owned}
	}
	services, _ := state["services"].(map[string]any)
	for name, raw := range services {
		svc, _ := raw.(map[string]any)
		id, _ := svc["module"].(string)
		if owner := s.owners[id]; owner != nil {
			if owner.services == nil {
				owner.services = make(map[string]any)
			}
			proxy, _ := svc["proxy"].(map[string]any)
			owner.services[name] = []any{svc["enable"] == true, proxy["enable"] == true, proxy["port"]}
		}
	}
	panels, _ := state["panelsList"].([]any)
	for _, raw := range panels {
		p, _ := raw.(map[string]any)
		id, _ := p["id"].(string)
		if _, duplicate := s.panels[id]; duplicate || p["enabled"] != true || !moduleRouteID.MatchString(id) {
			s.panels[id] = nil
			continue
		}
		s.panels[id] = p
	}
	return s
}

// Absolute declarations need not have been realized yet. Bare executable names
// must have an actual binPath in this owner's outputs, not just a label or a
// script of the same name elsewhere in the project. Mirror the first-declared
// rule in declaredActionTarget, indexing once rather than scanning per action.
func (o *uiReviewOwner) hasTarget(script, store string) bool {
	if !filepath.IsAbs(script) {
		if script == "" || script == "." || script == ".." || filepath.Base(script) != script {
			return false
		}
		if o.scriptPaths == nil {
			scripts, _ := o.outputs["scripts"].([]any)
			o.scriptPaths = make(map[string]string, len(scripts))
			for _, raw := range scripts {
				entry, _ := raw.(map[string]any)
				name, _ := entry["name"].(string)
				if _, seen := o.scriptPaths[name]; !seen {
					o.scriptPaths[name], _ = entry["binPath"].(string)
				}
			}
		}
		script = o.scriptPaths[script]
	}
	return inModuleActionStore(script, store)
}

// Report the browser origin only, never the author-supplied path. Bind the
// complete URL separately: moving /one to /two must invalidate the review.
func reviewedDevOrigin(link userconfig.LinkedModule, agentPort int) (string, bool) {
	if link.UIDevURL == "" {
		return "", true
	}
	if link.Path == "" || !validModuleDevURL(link.UIDevURL, agentPort) {
		return "", false
	}
	u, err := url.Parse(link.UIDevURL)
	if err != nil || !uiAuthority.MatchString(u.Host) {
		return "", false
	}
	host := strings.ToLower(u.Hostname())
	if strings.HasPrefix(u.Host, "[") {
		// A browser rejects bracketed IPv4/localhost. Only literal IPv6
		// loopback is a valid bracketed extension development origin.
		if addr, err := netip.ParseAddr(host); err != nil || addr.String() != "::1" {
			return "", false
		}
		host = "[::1]"
	}
	if rawPort := u.Port(); rawPort != "" {
		port, _ := strconv.Atoi(rawPort) // validModuleDevURL checked range
		if !(u.Scheme == "http" && port == 80 || u.Scheme == "https" && port == 443) {
			host += ":" + strconv.Itoa(port)
		}
	}
	return u.Scheme + "://" + host, true
}

func (s *uiReviewSnapshot) review(mod, p map[string]any) (revision, devOrigin string) {
	id, _ := mod["id"].(string)
	panelID, _ := p["id"].(string)
	owner := s.owners[id]
	p = s.panels[panelID] // Only the actual unique, enabled evaluated panel.
	if owner == nil || p == nil || p["module"] != id || s.project == "" {
		return "", ""
	}
	actions, _ := owner.module["actions"].(map[string]any)
	var ids []string
	var link userconfig.LinkedModule
	switch p["type"] {
	case "PANEL_TYPE_SPEC":
		spec, _ := p["spec"].(map[string]any)
		if p["uiBundle"] != nil || spec == nil {
			return "", ""
		}
		var err error
		ids, err = statusActionIDs(spec, actions)
		if err != nil || len(ids) == 0 {
			return "", ""
		}
	case "PANEL_TYPE_CUSTOM":
		bundle, err := customModuleBundle(owner.module, p, s.storeRoot)
		if err != nil || s.links == nil {
			return "", ""
		}
		link = s.links[id]
		var ok bool
		devOrigin, ok = reviewedDevOrigin(link, s.agentPort)
		if !ok {
			return "", ""
		}
		ids = bundle.actionIDs
	default:
		return "", ""
	}
	for _, k := range ids {
		action, _ := actions[k].(map[string]any)
		script, _ := action["script"].(string)
		if !owner.hasTarget(script, s.storeRoot) {
			return "", ""
		}
	}
	if owner.digest == "" {
		owner.digest = uiReviewHash([]any{owner.module, owner.outputs, owner.services})
		if owner.digest == "" {
			return "", ""
		}
	}
	p = withoutUIReview(p)
	revision = uiReviewHash([]any{s.project, owner.digest, p, ids, link, devOrigin})
	if revision == "" {
		return "", ""
	}
	return revision, devOrigin
}

func withoutUIReview(p map[string]any) map[string]any {
	if _, forged := p["uiReview"]; forged {
		p = maps.Clone(p)
		delete(p, "uiReview")
	}
	return p
}

// Don't resolve filesystem/machine authority, hash documents or walk action
// schemas just to serve a project of ordinary declarative layouts. This cheap
// filter is not authorization; review checks the real reachable action set.
func mayReviewPanel(p map[string]any) bool {
	if p["enabled"] != true {
		return false
	}
	switch p["type"] {
	case "PANEL_TYPE_CUSTOM":
		return true
	case "PANEL_TYPE_SPEC":
		spec, _ := p["spec"].(map[string]any)
		elements, _ := spec["elements"].(map[string]any)
		if p["uiBundle"] == nil && len(elements) <= 64 {
			for _, raw := range elements {
				node, _ := raw.(map[string]any)
				if node["type"] == "StatusView" {
					return true
				}
			}
		}
	}
	return false
}

// Annotate only panelsList. Never mutate the watcher's cached response.
func configWithUIReviews(root, store string, state map[string]any, port int) map[string]any {
	var snapshot *uiReviewSnapshot
	panels, _ := state["panelsList"].([]any)
	var updated []any
	for i, raw := range panels {
		p, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		var marker map[string]any
		if mayReviewPanel(p) {
			if snapshot == nil {
				snapshot = newUIReviewSnapshot(root, store, state, port)
			}
			id, _ := p["module"].(string)
			if owner := snapshot.owners[id]; owner != nil {
				if rev, origin := snapshot.review(owner.module, p); rev != "" {
					marker = map[string]any{"revision": rev}
					if origin != "" {
						marker["devOrigin"] = origin
					}
				}
			}
		}
		if _, forged := p["uiReview"]; marker == nil && !forged {
			continue
		}
		if updated == nil {
			updated = slices.Clone(panels)
		}
		p = maps.Clone(p)
		updated[i] = p
		if marker == nil {
			delete(p, "uiReview")
		} else {
			p["uiReview"] = marker
		}
	}
	if updated == nil {
		return state
	}
	result := maps.Clone(state)
	result["panelsList"] = updated
	return result
}
