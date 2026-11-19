package server

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

const testUIStoreName = "00000000000000000000000000000000-demo"

func newUITestServer(t *testing.T) *Server {
	t.Helper()
	mgr, err := NewJWTManager()
	if err != nil {
		t.Fatal(err)
	}
	return &Server{
		jwtManager: mgr,
		config:     &config.Config{Port: 9876, AuthToken: "studio-credential"},
	}
}

func uiTestState() (state, panel, module map[string]any) {
	module = map[string]any{"id": "demo", "enabled": true}
	panel = map[string]any{
		"id": "inspector", "module": "demo", "enabled": true, "type": "PANEL_TYPE_CUSTOM",
		"uiBundle": map[string]any{
			"package": moduleStoreRoot + "/" + testUIStoreName, "entry": "site/index.html",
			"permissions": []any{"config:read"},
		},
		"apps": map[string]any{
			"web": map[string]any{"enabled": true, "config": map[string]any{"label": "demo"}},
			"api": map[string]any{
				"enabled": false,
				"config":  map[string]any{"label": "other"},
			},
		},
		// Must never grant a dev URL supplied by the project.
		"uiDevUrl": "https://example.com",
	}
	return map[string]any{
		"modulesListAll": []any{module},
		"apps":           map[string]any{"web": map[string]any{"enable": true}, "api": map[string]any{"enable": true}},
		"panelsList":     []any{panel},
	}, panel, module
}

func TestOpenModuleUIIssuesOnlyEvaluatedProjectGrants(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	s := newUITestServer(t)
	state, panel, mod := uiTestState()
	mod["settings"] = map[string]any{"label": "global"}
	panel["slot"] = "app:tab"
	root := t.TempDir()
	store := t.TempDir()
	bundle := filepath.Join(store, testUIStoreName)
	if err := os.MkdirAll(filepath.Join(bundle, "site"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(bundle, "site/index.html"),
		nil,
		0o600,
	); err != nil {
		t.Fatal(err)
	}
	panel["uiBundle"].(map[string]any)["package"] = bundle
	rt := &projectRuntime{
		root: root,
		evalModuleState: func(_ context.Context, project string) ([]byte, error) {
			if project != root {
				t.Fatalf("evaluated wrong project: %s", project)
			}
			return json.Marshal(state)
		},
	}
	ctx := context.WithValue(t.Context(), runtimeKey{}, rt)
	var launchGrant string
	open := func(app string) *agentv1.OpenModuleUIResponse {
		t.Helper()
		req := connect.NewRequest(
			&agentv1.OpenModuleUIRequest{ModuleId: "demo", PanelId: "inspector", AppId: app},
		)
		req.Msg.ReviewRevision = testReviewRevision(t, root, store, state, "demo", "inspector")
		req.Header().Set("Origin", "https://stackpanel.com")
		req.Header().Set("Authorization", "Bearer "+s.config.AuthToken)
		res, err := (&moduleService{s: s}).openModuleUI(ctx, req, store)
		if err != nil {
			t.Fatal(err)
		}
		if res.Msg.ReviewRevision != req.Msg.ReviewRevision {
			t.Fatal("missing or incorrect launch review revision")
		}
		grant := res.Header().Get(moduleUIGrantHeader)
		if grant == "" || strings.Contains(res.Msg.Url, grant) || s.isValidToken(grant) ||
			res.Header().Get(moduleUIExpiryHeader) == "" {
			t.Fatal("missing or misplaced host-only launch grant")
		}
		if _, ok := s.openUITicket(moduleUIBase("demo", "inspector"), grant); ok {
			t.Fatal("host grant accepted as asset ticket")
		}
		launchGrant = grant
		return res.Msg
	}
	res := open("web")
	if len(res.Permissions) != 1 || res.Permissions[0] != "config:read" ||
		res.Settings.AsMap()["label"] != "demo" ||
		res.DevUrl != "" {
		t.Fatalf("wrong bundle grants: %v", res)
	}
	bound := connect.NewRequest(
		&agentv1.OpenModuleUIRequest{ModuleId: "demo", PanelId: "inspector", AppId: "web"},
	)
	bound.Header().Set(moduleUIGrantHeader, launchGrant)
	refreshed, err := (&moduleService{s: s}).openModuleUI(ctx, bound, store)
	if err != nil || refreshed.Header().Get(moduleUIGrantHeader) != launchGrant ||
		refreshed.Msg.Url != "" || refreshed.Msg.DevUrl != "" || refreshed.Msg.ReviewRevision != res.ReviewRevision ||
		refreshed.Msg.GetSettings().AsMap()["label"] != "demo" {
		t.Fatal("app refresh lost its launch binding", err)
	}
	bound.Msg.AppId = "api"
	if _, err := (&moduleService{s: s}).openModuleUI(
		ctx,
		bound,
		store,
	); connect.CodeOf(
		err,
	) != connect.CodePermissionDenied {
		t.Fatal("grant could read another app", err)
	}
	bound.Msg.AppId = "web"
	prefix := moduleUIBase("demo", "inspector")
	if !strings.HasPrefix(res.Url, prefix+"_ticket/") ||
		!strings.HasSuffix(res.Url, "/site/index.html") ||
		strings.Contains(res.Url, s.config.AuthToken) ||
		strings.Contains(res.Url, "?") {
		t.Fatal("expected relative scoped path ticket")
	}
	ticket, _, _ := strings.Cut(strings.TrimPrefix(res.Url, prefix+"_ticket/"), "/")
	c, valid := s.openUITicket(prefix, ticket)
	if !valid || c.Project != userconfig.GenerateProjectID(root) || c.Package != bundle ||
		c.Parent != "https://stackpanel.com" ||
		s.isValidToken(ticket) {
		t.Fatal("invalid ticket binding")
	}
	if _, ok := newUITestServer(t).openUITicket(prefix, ticket); ok {
		t.Fatal("accepted a ticket from another agent")
	}
	if _, ok := s.openUITicket(prefix, ticket[1:]); ok {
		t.Fatal("accepted a tampered ticket")
	}
	deny := func(app, review string) {
		t.Helper()
		req := connect.NewRequest(&agentv1.OpenModuleUIRequest{ModuleId: "demo", PanelId: "inspector", AppId: app, ReviewRevision: review})
		got, err := (&moduleService{s: s}).openModuleUI(ctx, req, store)
		if got != nil || connect.CodeOf(err) != connect.CodePermissionDenied {
			t.Fatalf("unreviewed or ineligible launch succeeded: %v %v", got, err)
		}
	}
	deny("api", res.ReviewRevision)
	deny("", res.ReviewRevision)
	deny("web", "")
	panel["uiBundle"].(map[string]any)["permissions"] = []any{}
	deny("web", res.ReviewRevision)
	if _, err := (&moduleService{s: s}).openModuleUI(
		ctx,
		bound,
		store,
	); connect.CodeOf(
		err,
	) != connect.CodePermissionDenied {
		t.Fatal("revoked app grant accepted", err)
	}
	if open("web").Settings != nil {
		t.Fatal("app metadata disclosed without config:read")
	}
	panel["slot"] = "module"
	deny("web", testReviewRevision(t, root, store, state, "demo", "inspector"))
	panel["uiBundle"].(map[string]any)["permissions"] = []any{"config:read"}
	global := open("")
	if global.GetSettings().AsMap()["label"] != "global" {
		t.Fatal("module panel did not receive module settings")
	}
	mod["settings"] = map[string]any{"label": "changed"}
	bound.Msg.AppId = ""
	bound.Header().Set(moduleUIGrantHeader, launchGrant)
	refreshed, err = (&moduleService{s: s}).openModuleUI(ctx, bound, store)
	if err != nil || refreshed.Msg.GetSettings().AsMap()["label"] != "changed" || refreshed.Msg.ReviewRevision != global.ReviewRevision || refreshed.Msg.Url != "" {
		t.Fatal("module settings refresh lost its launch binding", err)
	}
	delete(mod, "settings")
	if got, err := (&moduleService{s: s}).openModuleUI(ctx, bound, store); got != nil || connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatal("refresh accepted a missing settings projection", err)
	}
	mod["settings"] = map[string]any{}
	if open("").Settings == nil {
		t.Fatal("explicit empty settings projection lost")
	}
	other, author := t.TempDir(), t.TempDir()
	for _, dir := range []string{root, other, author} {
		if err := os.WriteFile(
			filepath.Join(dir, "flake.nix"),
			[]byte("{}"),
			0o600,
		); err != nil {
			t.Fatal(err)
		}
	}
	mgr, err := userconfig.NewManager()
	if err != nil {
		t.Fatal(err)
	}
	link := userconfig.LinkedModule{Path: author, UIDevURL: "http://127.0.0.1:3100/ui/"}
	if err := mgr.SetLinkedModule(other, "demo", link); err != nil {
		t.Fatal(err)
	}
	if got := open("").DevUrl; got != "" {
		t.Fatal("disclosed other project's dev link")
	}
	productionReview := testReviewRevision(t, root, store, state, "demo", "inspector")
	if err := mgr.SetLinkedModule(root, "demo", link); err != nil {
		t.Fatal(err)
	}
	deny("", productionReview) // changing from production to HMR requires a new review
	if err := os.Remove(filepath.Join(bundle, "site/index.html")); err != nil {
		t.Fatal(err)
	}
	if got := open("").DevUrl; got != link.UIDevURL {
		t.Fatal("did not use scoped development link")
	}
	devLaunch := connect.NewRequest(&agentv1.OpenModuleUIRequest{ModuleId: "demo", PanelId: "inspector", ReviewRevision: testReviewRevision(t, root, store, state, "demo", "inspector")})
	t.Setenv("STACKPANEL_DISABLE_CUSTOM_UI", "1")
	if _, err := (&moduleService{s: s}).openModuleUI(ctx, devLaunch, store); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("opened disabled custom UI with a linked HMR server: %v", err)
	}
}

func TestModuleBundleMustBeAttributedAndEnabled(t *testing.T) {
	for _, tc := range []struct {
		field string
		value any
	}{
		{"module", "other"}, {"enabled", false}, {"type", "PANEL_TYPE_TABLE"}, {"id", "another-panel"}, {"uiBundle", nil},
	} {
		state, panel, _ := uiTestState()
		panel[tc.field] = tc.value
		if _, err := evaluatedModuleBundle(
			state,
			"demo",
			"inspector",
			moduleStoreRoot,
		); err == nil {
			t.Errorf("accepted mismatched %s", tc.field)
		}
	}
	state, _, module := uiTestState()
	module["enabled"] = false
	if _, err := evaluatedModuleBundle(
		state,
		"demo",
		"inspector",
		moduleStoreRoot,
	); err == nil {
		t.Fatal("accepted disabled module")
	}
	for _, p := range []string{"", ".", moduleStoreRoot, "/tmp/" + testUIStoreName, moduleStoreRoot + "/" + testUIStoreName + "/other", moduleStoreRoot + "/../" + testUIStoreName} {
		if validModulePackage(p, moduleStoreRoot) {
			t.Errorf("accepted non-package path %q", p)
		}
	}
}

func TestModuleCapabilityRoutesRequireAuthAndScope(t *testing.T) {
	s := newUITestServer(t)
	mux := http.NewServeMux()
	s.mountModuleCapabilities(mux)
	for _, endpoint := range []string{"services/db/proxy/state", "ui/inspector/index.html"} {
		for _, tc := range []struct {
			auth, origin, project, query string
			want                         int
		}{
			{"", "", "other", "", 401},
			{"", "", "", "?token=studio-credential", 401},
			{"Bearer studio-credential", "null", "other", "", 403},
			{"Bearer studio-credential", "", "", "", 400},
		} {
			r := httptest.NewRequest("GET", "/api/v1/modules/demo/"+endpoint+tc.query, nil)
			r.Header.Set("Authorization", tc.auth)
			r.Header.Set("Origin", tc.origin)
			r.Header.Set(projectHeader, tc.project)
			w := httptest.NewRecorder()
			mux.ServeHTTP(w, r)
			if w.Code != tc.want {
				t.Errorf("%s: got %d, want %d", endpoint, w.Code, tc.want)
			}
		}
	}
}

func TestUITicketServesRelativeAssetsAndRejectsEscapes(t *testing.T) {
	s := newUITestServer(t)
	store := t.TempDir()
	bundle := filepath.Join(store, testUIStoreName)
	if err := os.MkdirAll(filepath.Join(bundle, "site"), 0o700); err != nil {
		t.Fatal(err)
	}
	for name, body := range map[string]string{"site/index.html": `<script type="module" src="./main.js"></script>`, "site/main.js": "export default 1"} {
		if err := os.WriteFile(
			filepath.Join(bundle, name),
			[]byte(body),
			0o600,
		); err != nil {
			t.Fatal(err)
		}
	}
	outside := filepath.Join(store, "secret")
	if err := os.WriteFile(outside, []byte("outside-data"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(bundle, "escape")); err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc(
		"/api/v1/modules/{module}/ui/{panel}/_ticket/{ticket}/{rest...}",
		func(w http.ResponseWriter, r *http.Request) {
			s.serveTicketAsset(w, r, store)
		},
	)
	srv := httptest.NewServer(guardModuleCapabilityPaths(mux.ServeHTTP))
	defer srv.Close()
	srv.Client().CheckRedirect = func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }
	const prefix = "/api/v1/modules/demo/ui/inspector/"
	claim := uiTicketClaims{
		Project: "p1",
		Parent:  "https://stackpanel.com",
		Package: bundle,
		Expires: time.Now().Add(time.Minute).Unix(),
	}
	issue := func(c uiTicketClaims) string {
		t.Helper()
		tok, err := s.sealUITicket(prefix, c)
		if err != nil {
			t.Fatal(err)
		}
		return prefix + "_ticket/" + tok + "/"
	}
	base := issue(claim)
	fetch := func(method, path, origin, project, dest string, want int) (http.Header, string) {
		t.Helper()
		req, err := http.NewRequestWithContext(t.Context(), method, srv.URL+path, nil)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Origin", origin)
		req.Header.Set(projectHeader, project)
		req.Header.Set("Sec-Fetch-Dest", dest)
		res, err := srv.Client().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		body, err := io.ReadAll(res.Body)
		if err != nil || res.StatusCode != want ||
			strings.Contains(string(body), "outside-data") {
			t.Fatalf(
				"%s %s: status %d want %d, read %v",
				method,
				path,
				res.StatusCode,
				want,
				err,
			)
		}
		return res.Header, string(body)
	}
	entry, err := url.Parse(base + "site/index.html")
	if err != nil {
		t.Fatal(err)
	}
	h, body := fetch("GET", entry.Path, "", "", "iframe", 200)
	if !strings.Contains(body, `src="./main.js"`) ||
		h.Get("Referrer-Policy") != "no-referrer" ||
		h.Get("Cache-Control") != "no-store" ||
		h.Get("X-Content-Type-Options") != "nosniff" {
		t.Fatal("missing document or isolation headers")
	}
	for _, policy := range []string{"sandbox allow-scripts;", "connect-src 'none'", "base-uri 'none'", "default-src 'none'", "frame-ancestors 'self' https://stackpanel.com"} {
		if !strings.Contains(h.Get("Content-Security-Policy"), policy) {
			t.Errorf("missing policy: %s", policy)
		}
	}
	script := entry.ResolveReference(&url.URL{Path: "main.js"}).Path
	h, body = fetch("GET", script, "null", "", "script", 200)
	if h.Get("Access-Control-Allow-Origin") != "null" ||
		h.Get("Access-Control-Allow-Credentials") != "" ||
		body != "export default 1" {
		t.Fatal("opaque-origin subasset not isolated")
	}
	fetch("POST", script, "null", "", "", 405)
	fetch("OPTIONS", script, "null", "", "", 204)
	fetch("HEAD", script, "null", "", "", 200)
	fetch("GET", script, "https://other.invalid", "", "", 404)
	fetch("GET", script, "null", "p2", "", 404)
	fetch("GET", script, "null", "", "serviceworker", 404)
	fetch("GET", strings.Replace(script, "/demo/", "/other/", 1), "", "", "", 404)
	fetch("GET", strings.Replace(script, "/inspector/", "/other/", 1), "", "", "", 404)
	for _, path := range []string{"site", "escape", "site/../escape", "%2e%2e/secret", "site%2fmain.js", "%252e%252e/secret", "%5csecret"} {
		fetch("GET", base+path, "", "", "", 404)
	}
	claim.Expires = time.Now().Add(-time.Second).Unix()
	fetch("GET", issue(claim)+"site/main.js", "", "", "", 404)
	claim.Expires = time.Now().Add(time.Minute).Unix()
	claim.Package = filepath.Join(
		store,
		strings.Replace(testUIStoreName, "-demo", "-link", 1),
	)
	if err := os.Symlink(bundle, claim.Package); err != nil {
		t.Fatal(err)
	}
	fetch("GET", issue(claim)+"site/main.js", "", "", "", 404)
	t.Setenv("STACKPANEL_DISABLE_CUSTOM_UI", "1")
	fetch("GET", entry.Path, "", "", "iframe", 404)
	fetch("OPTIONS", script, "null", "", "", 404)
	fetch("GET", script, "null", "", "script", 404)
}

func TestLinkedUIOnlyAcceptsNonAgentLoopback(t *testing.T) {
	for _, u := range []string{"https://example.org/", "file:///etc/passwd", "http://127.0.0.1:9876/status", "http://localhost:09876/", "http://localhost:3100/?token=credential", "http://u:p@localhost:3100/"} {
		if validModuleDevURL(u, 9876) {
			t.Errorf("accepted %s", u)
		}
	}
	if !validModuleDevURL("http://127.0.0.1:3100/module/", 9876) {
		t.Error("rejected loopback dev server")
	}
}

func TestPairDoesNotMintForEmbeddedDocuments(t *testing.T) {
	// No token issuer or template. Every rejection must happen before either.
	s := &Server{config: &config.Config{}}
	for _, tc := range []struct{ dest, mode, origin string }{
		{"iframe", "navigate", "http://localhost:3100"},
		{"frame", "navigate", "http://localhost:3100"},
		{"empty", "cors", "http://localhost:3100"},
		{"script", "no-cors", "http://localhost:3100"},
		{"document", "navigate", "null"},
		{"document", "cors", "http://localhost:3100"},
	} {
		r := httptest.NewRequest(
			"POST",
			"/pair",
			strings.NewReader("state="+strings.Repeat("a", 64)),
		)
		r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		r.Header.Set("Sec-Fetch-Dest", tc.dest)
		r.Header.Set("Sec-Fetch-Mode", tc.mode)
		r.Header.Set("Origin", tc.origin)
		w := httptest.NewRecorder()
		s.handlePair(w, r)
		if w.Code != http.StatusForbidden ||
			w.Header().Get("Content-Security-Policy") != "frame-ancestors 'none'" ||
			w.Header().Get("X-Frame-Options") != "DENY" ||
			w.Header().Get("Cache-Control") != "no-store" {
			t.Errorf("pairing not isolated for %+v", tc)
		}
	}
}

func TestModuleProxyCannotRequestPairingCredentials(t *testing.T) {
	// Even if a second agent is listening on a declared service port, the
	// proxy cannot provide the query or Referer that starts a pairing flow.
	other := &Server{config: &config.Config{}}
	upstream := httptest.NewServer(http.HandlerFunc(other.handlePair))
	defer upstream.Close()
	proxy := moduleProxyTestAgent(t, upstream)
	for _, tc := range []struct {
		suffix string
		status int
	}{{"pair", 403}, {"pair?origin=http://localhost:3100", 400}} {
		r, err := http.NewRequestWithContext(
			t.Context(),
			"GET",
			proxy.URL+moduleProxyTestPrefix+tc.suffix,
			nil,
		)
		if err != nil {
			t.Fatal(err)
		}
		r.Header.Set("Referer", "http://localhost:3100/")
		res, err := proxy.Client().Do(r)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		if res.StatusCode != tc.status {
			t.Errorf("unexpected proxy status: %d", res.StatusCode)
		}
	}
}
