package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/http/httptrace"
	"net/textproto"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gorilla/websocket"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

const moduleProxyTestPrefix = "/api/v1/modules/demo/services/api/proxy/"

func moduleProxyTestState(port int) map[string]any {
	return map[string]any{
		"modulesListAll": []map[string]any{{"id": "demo", "enabled": true}},
		"services": map[string]any{"api": map[string]any{
			"module": "demo",
			"enable": true,
			"proxy":  map[string]any{"enable": true, "port": port},
		}},
	}
}

func moduleProxyTestRuntime(
	t *testing.T,
	root string,
	state map[string]any,
) *projectRuntime {
	t.Helper()
	data, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	return &projectRuntime{
		root: root,
		evalModuleState: func(_ context.Context, got string) ([]byte, error) {
			if got != root {
				return nil, fmt.Errorf("wrong evaluation root")
			}
			return data, nil
		},
	}
}

func moduleProxyTestAgent(t *testing.T, upstream *httptest.Server) *httptest.Server {
	t.Helper()
	root := t.TempDir()
	moduleProxyRegister(t, root)
	port := moduleProxyManagedPort(t, root, upstream.Listener.Addr().String())
	state, panel, _ := uiTestState()
	panel["uiBundle"].(map[string]any)["permissions"] = []any{"service:proxy"}
	state["services"] = moduleProxyTestState(port)["services"]
	rt := moduleProxyTestRuntime(t, root, state)
	s := newUITestServer(t)
	grant, err := s.issueModuleUIGrant(
		root,
		state,
		"demo",
		"inspector",
		"",
		moduleStoreRoot,
		userconfig.LinkedModule{},
	)
	if err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc(
		"/api/v1/modules/{module}/services/{service}/proxy/{rest...}",
		func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get(moduleUIGrantHeader) == "" {
				r.Header.Set(moduleUIGrantHeader, grant)
			}
			w.Header().Set("Access-Control-Allow-Origin", "https://studio.example")
			s.handleModuleProxy(
				w,
				r.WithContext(context.WithValue(r.Context(), runtimeKey{}, rt)),
			)
		},
	)
	agent := httptest.NewServer(mux)
	t.Cleanup(agent.Close)
	return agent
}

func TestModuleProxyHTTP(t *testing.T) {
	payload := []byte{0, 0xff, 1, 2}
	var calls atomic.Int32
	service := httptest.NewServer(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			calls.Add(1)
			if !strings.HasPrefix(r.Host, "127.0.0.1:") ||
				r.URL.RequestURI() != "/items/v1.2" {
				t.Errorf("unexpected service target: %s %s", r.Host, r.URL.RequestURI())
			}
			if r.Header.Get("Content-Type") != "application/octet-stream" ||
				r.Header.Get("Accept") != "application/json" {
				t.Error("missing representation headers")
			}
			for _, k := range []string{moduleUIGrantHeader, "Authorization", "Cookie", "Origin", projectHeader, "X-Stackpanel-Token", "Proxy-Authorization", "X-Forwarded-Host", "Forwarded", "X-HTTP-Method-Override", "Referer"} {
				if r.Header.Get(k) != "" {
					t.Errorf("relayed request header %s", k)
				}
			}
			got, err := io.ReadAll(r.Body)
			want := payload
			if r.Method == "GET" || r.Method == "HEAD" {
				want = nil
			}
			if err != nil || !bytes.Equal(got, want) {
				t.Errorf("unexpected %s request body: %x, %v", r.Method, got, err)
			}
			w.Header().Set("Set-Cookie", "from=service")
			w.Header().Set("X-Stackpanel-Service-Response", "untrusted")
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Location", "https://unused.invalid/")
			w.Header().Set("Refresh", "0")
			w.Header().Set("Link", "</private>; rel=preload")
			w.WriteHeader(http.StatusEarlyHints)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusCreated)
			_, _ = w.Write([]byte(r.Method))
		}),
	)
	defer service.Close()
	agent := moduleProxyTestAgent(t, service)
	for _, method := range []string{"GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"} {
		t.Run(method, func(t *testing.T) {
			ctx := httptrace.WithClientTrace(
				t.Context(),
				&httptrace.ClientTrace{Got1xxResponse: func(int, textproto.MIMEHeader) error {
					return fmt.Errorf("upstream informational headers escaped")
				}},
			)
			var body io.Reader
			if method != "GET" && method != "HEAD" {
				body = bytes.NewReader(payload)
			}
			req, err := http.NewRequestWithContext(
				ctx,
				method,
				agent.URL+moduleProxyTestPrefix+"items/v1.2",
				body,
			)
			if err != nil {
				t.Fatal(err)
			}
			req.Host = "virtual-host.invalid:12345"
			req.Header.Set("Origin", "https://studio.example")
			req.Header.Set("Content-Type", "application/octet-stream")
			req.Header.Set("Accept", "application/json")
			for _, k := range []string{"Authorization", "Cookie", projectHeader, "X-Stackpanel-Token", "Proxy-Authorization", "X-Forwarded-Host", "Forwarded", "X-HTTP-Method-Override", "Referer"} {
				req.Header.Set(k, "private")
			}
			res, err := agent.Client().Do(req)
			if err != nil {
				t.Fatal(err)
			}
			defer res.Body.Close()
			got, err := io.ReadAll(res.Body)
			want := method
			if method == "HEAD" {
				want = ""
			}
			if err != nil || res.StatusCode != http.StatusCreated || string(got) != want {
				t.Fatalf("response: %d %q %v", res.StatusCode, got, err)
			}
			if res.Header.Get("X-Stackpanel-Service-Response") != "1" {
				t.Fatal("service response metadata did not come from agent")
			}
			if res.Header.Get("Content-Type") != "application/json" ||
				res.Header.Get("Access-Control-Allow-Origin") != "https://studio.example" ||
				!strings.Contains(res.Header.Get("Content-Security-Policy"), "sandbox") ||
				res.Header.Get("Cache-Control") != "no-store" {
				t.Errorf("unexpected response policy: %v", res.Header)
			}
			for _, k := range []string{"Set-Cookie", "Location", "Refresh", "Link"} {
				if res.Header.Get(k) != "" {
					t.Errorf("relayed service header %s", k)
				}
			}
		})
	}
	if n := calls.Load(); n != 6 {
		t.Errorf("service handled %d requests; want 6", n)
	}
}

func TestModuleProxyWebSocket(t *testing.T) {
	service := httptest.NewServer(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.RequestURI() != "/ws" || !strings.HasPrefix(r.Host, "127.0.0.1:") {
				t.Error("wrong websocket target")
			}
			for _, k := range []string{moduleUIGrantHeader, "Origin", "Authorization", "Cookie", projectHeader, "Sec-WebSocket-Extensions"} {
				if r.Header.Get(k) != "" {
					t.Errorf("relayed handshake header %s", k)
				}
			}
			upgrader := websocket.Upgrader{}
			c, err := upgrader.Upgrade(
				w,
				r,
				http.Header{
					"Set-Cookie":                  {"service=secret"},
					"Access-Control-Allow-Origin": {"*"},
				},
			)
			if err != nil {
				t.Error(err)
				return
			}
			defer c.Close()
			kind, data, err := c.ReadMessage()
			if err != nil || kind != websocket.BinaryMessage ||
				!bytes.Equal(data, []byte{0, 0xff}) {
				t.Errorf("service received %d %x %v", kind, data, err)
				return
			}
			if err := c.WriteMessage(websocket.TextMessage, []byte("reply")); err != nil {
				t.Error(err)
			}
		}),
	)
	defer service.Close()
	agent := moduleProxyTestAgent(t, service)
	dialer := websocket.Dialer{EnableCompression: true, HandshakeTimeout: 5 * time.Second}
	c, resp, err := dialer.DialContext(
		t.Context(),
		"ws"+strings.TrimPrefix(agent.URL, "http")+moduleProxyTestPrefix+"ws",
		http.Header{
			"Origin": {
				"https://studio.example",
			},
			"Authorization": {"Bearer private"},
			"Cookie":        {"agent=session"},
			projectHeader:   {"demo"},
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if resp.Header.Get("Set-Cookie") != "" ||
		resp.Header.Get("Access-Control-Allow-Origin") == "*" ||
		resp.Header.Get("Sec-WebSocket-Extensions") != "" {
		t.Errorf("relayed upstream handshake: %v", resp.Header)
	}
	_ = c.SetReadDeadline(time.Now().Add(5 * time.Second))
	if err := c.WriteMessage(websocket.BinaryMessage, []byte{0, 0xff}); err != nil {
		t.Fatal(err)
	}
	kind, data, err := c.ReadMessage()
	if err != nil || kind != websocket.TextMessage || string(data) != "reply" {
		t.Errorf("client received %d %q %v", kind, data, err)
	}
}

func TestModuleProxyRejectsUntrustedServiceResponses(t *testing.T) {
	service := httptest.NewServer(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			switch r.URL.Path {
			case "/redirect":
				http.Redirect(w, r, "/never", http.StatusTemporaryRedirect)
			case "/trailers":
				w.Header().Set("Trailer", "X-End")
				_, _ = w.Write([]byte("private"))
				w.Header().Set("X-End", "private")
			case "/late-trailers":
				w.(http.Flusher).Flush()
				_, _ = w.Write([]byte("private"))
				w.Header().Set(http.TrailerPrefix+"X-End", "private")
			case "/excess":
				w.Header().Set("Content-Length", fmt.Sprint(moduleProxyResponseLimit+1))
			default:
				t.Errorf("unexpected service request: %s", r.URL.Path)
			}
		}),
	)
	defer service.Close()
	agent := moduleProxyTestAgent(t, service)
	for _, rest := range []string{"redirect", "trailers", "late-trailers", "excess"} {
		res, err := agent.Client().Get(agent.URL + moduleProxyTestPrefix + rest)
		if err != nil {
			t.Fatal(err)
		}
		b, err := io.ReadAll(res.Body)
		res.Body.Close()
		if err != nil || res.StatusCode != http.StatusBadGateway ||
			res.Header.Get("Location") != "" ||
			len(res.Trailer) > 0 ||
			bytes.Contains(b, []byte("private")) {
			t.Errorf(
				"%s: %d %v %v %q %v",
				rest,
				res.StatusCode,
				res.Header,
				res.Trailer,
				b,
				err,
			)
		}
	}
}

func TestModuleProxyRejectsInvalidUIGrant(t *testing.T) {
	service := httptest.NewServer(
		http.HandlerFunc(
			func(http.ResponseWriter, *http.Request) { t.Error("invalid grant reached service") },
		),
	)
	defer service.Close()
	agent := moduleProxyTestAgent(t, service)
	req, err := http.NewRequestWithContext(
		t.Context(),
		http.MethodGet,
		agent.URL+moduleProxyTestPrefix,
		nil,
	)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(moduleUIGrantHeader, "not-a-grant")
	resp, err := agent.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden {
		t.Errorf("invalid grant: %d", resp.StatusCode)
	}
}

func TestModuleProxyFailsClosed(t *testing.T) {
	var dials atomic.Int32
	service := httptest.NewServer(
		http.HandlerFunc(func(http.ResponseWriter, *http.Request) { dials.Add(1) }),
	)
	defer service.Close()
	port := service.Listener.Addr().(*net.TCPAddr).Port
	s := &Server{config: &config.Config{Port: 9876, ProjectRoot: "/current"}}
	for _, name := range []string{
		"unscoped", "different project", "unknown module", "unknown service", "disabled module", "disabled service", "other owner", "no opt in",
		"no proxy port", "string port", "fractional port", "port overflow", "zero port", "configured self", "listener self",
		"shared primary port", "shared proxy port",
		"query", "empty query", "absolute uri", "dot segment", "empty segment", "leading slash", "encoded slash", "double escape", "backslash", "scheme",
		"method", "get body", "trailer", "connection nomination", "alternate upgrade", "incomplete websocket", "subprotocol", "large body",
	} {
		t.Run(name, func(t *testing.T) {
			state := moduleProxyTestState(port)
			svc := state["services"].(map[string]any)["api"].(map[string]any)
			proxy := svc["proxy"].(map[string]any)
			r := httptest.NewRequest("GET", moduleProxyTestPrefix+"items", nil)
			r.SetPathValue("module", "demo")
			r.SetPathValue("service", "api")
			r.SetPathValue("rest", "items")
			want := http.StatusBadRequest
			switch name {
			case "unscoped":
				want = http.StatusForbidden
			case "different project":
				// Current project declarations cannot fill gaps in the scoped runtime.
				delete(state, "services")
				r.Header.Set(projectHeader, s.config.ProjectRoot)
				want = http.StatusForbidden
			case "unknown module":
				r.SetPathValue("module", "absent")
				want = http.StatusForbidden
			case "unknown service":
				r.SetPathValue("service", "absent")
				want = http.StatusForbidden
			case "disabled module":
				state["modulesListAll"].([]map[string]any)[0]["enabled"] = false
				want = http.StatusForbidden
			case "disabled service":
				svc["enable"], want = false, http.StatusForbidden
			case "other owner":
				svc["module"], want = "other", http.StatusForbidden
			case "no opt in":
				proxy["enable"], want = false, http.StatusForbidden
			case "no proxy port":
				svc["port"] = port // must not fall back to the primary service port
				delete(proxy, "port")
				want = http.StatusForbidden
			case "string port":
				proxy["port"], want = fmt.Sprint(port), http.StatusForbidden
			case "fractional port":
				proxy["port"], want = float64(port)+0.5, http.StatusForbidden
			case "port overflow":
				proxy["port"], want = 65536, http.StatusForbidden
			case "zero port":
				proxy["port"], want = 0, http.StatusForbidden
			case "configured self":
				proxy["port"], want = s.config.Port, http.StatusForbidden
			case "listener self":
				r = r.WithContext(
					context.WithValue(
						r.Context(),
						http.LocalAddrContextKey,
						service.Listener.Addr(),
					),
				)
				want = http.StatusForbidden
			case "shared primary port":
				state["services"].(map[string]any)["other"] = map[string]any{
					"enable": true,
					"port":   port,
				}
				want = http.StatusForbidden
			case "shared proxy port":
				state["services"].(map[string]any)["other"] = map[string]any{
					"enable": true,
					"proxy":  map[string]any{"enable": true, "port": port},
				}
				want = http.StatusForbidden
			case "query":
				r.URL.RawQuery = "token=private"
			case "empty query":
				r.URL.ForceQuery = true
			case "absolute uri":
				r.URL.Scheme, r.URL.Host = "http", "unused.invalid"
			case "dot segment":
				r.SetPathValue("rest", "items/../other")
			case "empty segment":
				r.SetPathValue("rest", "items//other")
			case "leading slash":
				r.SetPathValue("rest", "/other")
			case "encoded slash":
				r.URL.Path, r.URL.RawPath = moduleProxyTestPrefix+"items/one", moduleProxyTestPrefix+"items%2fone"
				r.SetPathValue("rest", "items/one")
			case "double escape":
				r.SetPathValue("rest", "items%2fone")
			case "backslash":
				r.SetPathValue("rest", `items\other`)
			case "scheme":
				r.SetPathValue("rest", "http://unused.invalid")
			case "method":
				r.Method, want = http.MethodConnect, http.StatusMethodNotAllowed
			case "get body":
				r.Body, r.ContentLength = io.NopCloser(strings.NewReader("data")), 4
			case "trailer":
				r.Method, r.Trailer = http.MethodPost, http.Header{"X-End": nil}
			case "connection nomination":
				r.Header.Set("Connection", "Content-Type")
			case "alternate upgrade":
				r.Header.Set("Upgrade", "other")
				r.Header.Set("Connection", "Upgrade")
			case "incomplete websocket":
				r.Header.Set("Upgrade", "websocket")
			case "subprotocol":
				r.Header.Set("Upgrade", "websocket")
				r.Header.Set("Connection", "Upgrade")
				r.Header.Set("Sec-WebSocket-Version", "13")
				r.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
				r.Header.Set("Sec-WebSocket-Protocol", "private")
			case "large body":
				r.Method, r.ContentLength, want = "POST", moduleProxyRequestLimit+1, http.StatusRequestEntityTooLarge
			}
			if name != "unscoped" {
				r = r.WithContext(
					context.WithValue(
						r.Context(),
						runtimeKey{},
						moduleProxyTestRuntime(t, "/selected", state),
					),
				)
			}
			w := httptest.NewRecorder()
			s.handleModuleProxy(w, r)
			if w.Code != want {
				t.Errorf("status %d, want %d", w.Code, want)
			}
		})
	}
	if n := dials.Load(); n != 0 {
		t.Errorf("service received %d denied requests", n)
	}
}
