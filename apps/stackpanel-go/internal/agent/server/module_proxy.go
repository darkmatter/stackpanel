package server

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	moduleProxyRequestLimit  = 1 << 20
	moduleProxyResponseLimit = 8 << 20
)

var errModuleProxyIdentity = errors.New("service identity unavailable")

func (s *Server) handleModuleProxy(w http.ResponseWriter, r *http.Request) {
	// These responses are data, not pages or scripts served by the agent.
	w.Header().
		Set("Content-Security-Policy", "sandbox; default-src 'none'; frame-ancestors 'none'")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "no-store")
	rt := runtimeFor(r.Context())
	if rt == nil || rt.root == "" {
		http.Error(w, "project scope required", http.StatusForbidden)
		return
	}
	switch r.Method {
	case http.MethodGet,
		http.MethodHead,
		http.MethodPost,
		http.MethodPut,
		http.MethodPatch,
		http.MethodDelete:
	default:
		w.Header().Set("Allow", "GET, HEAD, POST, PUT, PATCH, DELETE")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	module, service, rest := r.PathValue(
		"module",
	), r.PathValue(
		"service",
	), r.PathValue(
		"rest",
	)
	if !moduleProxySegment(module) || !moduleProxySegment(service) || !moduleProxyPath(rest) ||
		r.URL.IsAbs() || r.URL.Host != "" || r.URL.Opaque != "" || r.URL.User != nil || r.URL.Fragment != "" ||
		r.URL.ForceQuery ||
		r.URL.RawQuery != "" ||
		strings.Contains(r.URL.EscapedPath(), "%") {
		http.Error(w, "invalid proxy path", http.StatusBadRequest)
		return
	}
	upgrade, ok := moduleProxyHandshake(r)
	if !ok || len(r.Trailer) != 0 || len(r.Header.Values("Trailer")) != 0 ||
		len(r.Header.Values("Te")) != 0 ||
		len(r.Header.Values("Expect")) != 0 ||
		len(r.Header.Values("Content-Encoding")) != 0 ||
		len(r.Header.Values("Content-Type")) > 1 ||
		((r.Method == http.MethodGet || r.Method == http.MethodHead) && r.ContentLength != 0) {
		http.Error(w, "unsupported request framing", http.StatusBadRequest)
		return
	}
	if r.ContentLength > moduleProxyRequestLimit {
		http.Error(w, "request too large", http.StatusRequestEntityTooLarge)
		return
	}
	state, err := loadModuleState(r.Context(), rt)
	if err != nil {
		http.Error(w, "project state unavailable", http.StatusServiceUnavailable)
		return
	}
	if err := s.checkModuleProxyGrant(r.Header, rt, state, module); err != nil {
		http.Error(w, "service not available", http.StatusForbidden)
		return
	}
	port := moduleProxyPort(state, module, service)
	if port == 0 || s.isModuleProxySelf(r, port) {
		http.Error(w, "service not available", http.StatusForbidden)
		return
	}
	if err := moduleProxyCheckPort(
		rt.root,
		service,
		port,
		state,
		moduleStoreRoot,
	); err != nil {
		status := http.StatusForbidden
		if err == errModuleProxyInventory {
			status = http.StatusServiceUnavailable
		}
		http.Error(w, err.Error(), status)
		return
	}
	target := url.URL{
		Scheme: "http",
		Host:   net.JoinHostPort("127.0.0.1", strconv.Itoa(port)),
		Path:   "/" + rest,
	}
	peer, err := newModuleProxyPeer(rt.root, module, service, target.Host)
	if err != nil {
		http.Error(w, "service identity unavailable", http.StatusForbidden)
		return
	}
	if upgrade {
		target.Scheme = "ws"
		s.serveModuleProxyWebSocket(w, r, target, peer)
		return
	}
	serveModuleProxyHTTP(w, r, target, peer)
}

func moduleProxyPort(state map[string]any, module, name string) int {
	mod, err := findModule(state, module)
	if err != nil || mod["enabled"] != true {
		return 0
	}
	services, _ := state["services"].(map[string]any)
	svc, _ := services[name].(map[string]any)
	proxy, _ := svc["proxy"].(map[string]any)
	if svc["module"] != module || svc["enable"] != true || proxy["enable"] != true {
		return 0
	}
	port, ok := proxy["port"].(float64) // json.Unmarshal of the evaluated Nix state
	if !ok || !(1 <= port && port <= 65535) || port != float64(int(port)) {
		return 0
	}
	return int(port)
}

func (s *Server) isModuleProxySelf(r *http.Request, port int) bool {
	if s.config != nil && port == s.config.Port {
		return true
	}
	// LocalAddr also covers ephemeral listeners. Never trust r.Host for this.
	addr, _ := r.Context().Value(http.LocalAddrContextKey).(*net.TCPAddr)
	return addr != nil && addr.Port == port
}

func moduleProxySegment(segment string) bool {
	if segment == "" || segment == "." || segment == ".." {
		return false
	}
	for _, c := range segment {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || strings.ContainsRune("-._~", c)) {
			return false
		}
	}
	return true
}

func moduleProxyPath(rest string) bool {
	// Empty rest is the root. Allow a trailing slash, but not empty interior
	// segments, escaping, scheme/authority syntax, or path normalization.
	for rest != "" {
		var segment string
		segment, rest, _ = strings.Cut(rest, "/")
		if !moduleProxySegment(segment) {
			return false
		}
	}
	return true
}

func serveModuleProxyHTTP(
	w http.ResponseWriter,
	r *http.Request,
	target url.URL,
	peer moduleProxyPeer,
) {
	// Finish validating unknown-length bodies (including undeclared trailers)
	// before sending even the first byte of a mutating request to the service.
	var body []byte
	if r.Body != nil && r.Body != http.NoBody {
		var err error
		body, err = io.ReadAll(http.MaxBytesReader(w, r.Body, moduleProxyRequestLimit))
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			http.Error(w, "request too large", http.StatusRequestEntityTooLarge)
			return
		}
		if err != nil || len(r.Trailer) != 0 {
			http.Error(w, "invalid request body", http.StatusBadRequest)
			return
		}
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	out, err := http.NewRequestWithContext(
		ctx,
		r.Method,
		target.String(),
		bytes.NewReader(body),
	)
	if err != nil {
		http.Error(w, "invalid proxy request", http.StatusBadRequest)
		return
	}
	// Build from scratch: never forward bearer, cookies, Origin, project,
	// Forwarded, method override, or arbitrary extension headers.
	for _, key := range []string{"Accept", "Content-Type"} {
		if v := r.Header.Get(key); v != "" {
			out.Header.Set(key, v)
		}
	}
	// No proxy environment, redirects, cookies or reusable TCP connections.
	transport := http.Transport{
		DialContext: peer.dial, DisableKeepAlives: true, DisableCompression: true,
		MaxResponseHeaderBytes: 32 << 10, ResponseHeaderTimeout: 10 * time.Second,
	}
	resp, err := transport.RoundTrip(out)
	if err != nil {
		http.Error(w, "service unavailable", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 && resp.StatusCode < 400 || resp.StatusCode > 599 ||
		len(resp.Trailer) != 0 ||
		len(resp.Header.Values("Trailer")) != 0 ||
		resp.Header.Get("Content-Encoding") != "" ||
		(r.Method != http.MethodHead && resp.ContentLength > moduleProxyResponseLimit) {
		http.Error(w, "unsupported service response", http.StatusBadGateway)
		return
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, moduleProxyResponseLimit+1))
	if err != nil || len(data) > moduleProxyResponseLimit || len(resp.Trailer) != 0 {
		http.Error(w, "invalid service response", http.StatusBadGateway)
		return
	}
	// Keep outer middleware's CORS policy; do not relay cookies, redirects,
	// refreshes, hop-by-hop metadata or upstream authentication challenges.
	mediaType := resp.Header.Get("Content-Type")
	if mediaType == "" || moduleProxyConnectionNames(resp.Header, "Content-Type") {
		mediaType = "application/octet-stream"
	}
	w.Header().Set("Content-Type", mediaType)
	w.Header().Set("Content-Disposition", "attachment")
	// Studio must distinguish an upstream 401/403 from an agent rejecting its
	// document grant. This marker is set here, never copied from the service.
	w.Header().Set("X-Stackpanel-Service-Response", "1")
	w.Header().Add("Access-Control-Expose-Headers", "X-Stackpanel-Service-Response")
	if r.Method == http.MethodHead && resp.ContentLength >= 0 {
		w.Header().Set("Content-Length", strconv.FormatInt(resp.ContentLength, 10))
	}
	w.WriteHeader(resp.StatusCode)
	if len(data) != 0 {
		_, _ = w.Write(data)
	}
}

func moduleProxyConnectionNames(header http.Header, name string) bool {
	for _, list := range header.Values("Connection") {
		for token := range strings.SplitSeq(list, ",") {
			if strings.EqualFold(strings.TrimSpace(token), name) {
				return true
			}
		}
	}
	return false
}
