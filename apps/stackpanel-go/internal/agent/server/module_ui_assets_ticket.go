package server

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hkdf"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io/fs"
	"mime"
	"net/http"
	"os"
	"path"
	"strings"
	"time"
	"unicode"
)

const uiTicketLifetime = 5 * time.Minute

// A snapshot grants only GET/HEAD of one immutable bundle. No lookup of a
// mutable current project, no local dev URL, and no agent credential. The
// authenticated associated data binds it to the issuing module and panel.
// Encrypt rather than merely sign: the URL is visible to untrusted scripts.
type uiTicketClaims struct {
	Project string `json:"p"`
	Package string `json:"b"`
	Parent  string `json:"o"`
	Expires int64  `json:"e"`
}

func (s *Server) uiTicketCipher() (cipher.AEAD, error) {
	return s.uiCapabilityCipher("stackpanel-ui-read-ticket-v1")
}

func (s *Server) uiCapabilityCipher(purpose string) (cipher.AEAD, error) {
	if s.jwtManager == nil || len(s.jwtManager.signingKey) == 0 {
		return nil, errors.New("UI ticket issuer unavailable")
	}
	key, err := hkdf.Key(sha256.New, s.jwtManager.signingKey, nil, purpose, 32)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCMWithRandomNonce(block)
}

func (s *Server) sealUITicket(prefix string, c uiTicketClaims) (string, error) {
	cipher, err := s.uiTicketCipher()
	if err != nil {
		return "", err
	}
	msg, err := json.Marshal(c)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(
		cipher.Seal(nil, nil, msg, []byte(prefix)),
	), nil
}

func (s *Server) openUITicket(prefix, ticket string) (c uiTicketClaims, valid bool) {
	if len(ticket) == 0 || len(ticket) > 2048 {
		return c, false
	}
	sealed, err := base64.RawURLEncoding.Strict().DecodeString(ticket)
	if err != nil {
		return c, false
	}
	cipher, err := s.uiTicketCipher()
	if err != nil || len(sealed) < cipher.Overhead() {
		return c, false
	}
	msg, err := cipher.Open(nil, nil, sealed, []byte(prefix))
	if err != nil || json.Unmarshal(msg, &c) != nil || c.Project == "" ||
		!validStudioOrigin(c.Parent) {
		return c, false
	}
	now := time.Now()
	return c, c.Expires > now.Unix() && c.Expires <= now.Add(uiTicketLifetime).Unix()
}

func validAssetPath(relative string) bool {
	return relative != "." && fs.ValidPath(relative) &&
		!strings.ContainsAny(relative, `\%?#`) &&
		strings.IndexFunc(relative, unicode.IsControl) == -1
}

// ServeMux normally redirects paths containing dot segments before dispatch.
// Do not redirect a request containing a scoped capability to a different URL.
func guardModuleCapabilityPaths(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/v1/modules/") {
			rel := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/"), "/")
			if !validAssetPath(rel) ||
				strings.Contains(strings.ToLower(r.URL.EscapedPath()), "%2f") {
				http.NotFound(w, r)
				return
			}
		}
		next(w, r)
	}
}

func (s *Server) handleModuleAsset(w http.ResponseWriter, r *http.Request) {
	module, panel := r.PathValue("module"), r.PathValue("panel")
	if !validAssetRequest(w, r, false) {
		return
	}
	bundle, err := requestModuleBundle(r.Context(), module, panel, moduleStoreRoot)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	serveModuleAsset(
		w,
		r,
		bundle.root,
		moduleUIBase(module, panel),
		r.Header.Get("Origin"),
	)
}

func (s *Server) handleTicketAsset(w http.ResponseWriter, r *http.Request) {
	s.serveTicketAsset(w, r, moduleStoreRoot)
}

func (s *Server) serveTicketAsset(
	w http.ResponseWriter,
	r *http.Request,
	storeRoot string,
) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	if !validAssetRequest(w, r, true) {
		return
	}
	module, panel, ticket := r.PathValue(
		"module",
	), r.PathValue(
		"panel",
	), r.PathValue(
		"ticket",
	)
	if !moduleRouteID.MatchString(module) || !moduleRouteID.MatchString(panel) {
		http.NotFound(w, r)
		return
	}
	prefix := moduleUIBase(module, panel)
	claim, ok := s.openUITicket(prefix, ticket)
	if !ok || !validModulePackage(claim.Package, storeRoot) ||
		(r.Header.Get(projectHeader) != "" && r.Header.Get(projectHeader) != claim.Project) {
		http.NotFound(w, r)
		return
	}
	// ES module imports/fonts from sandboxed frames have Origin: null. Limit
	// that exception to a valid ticket; never opt any agent API into null CORS.
	origin := r.Header.Get("Origin")
	if origin != "" && origin != "null" && origin != claim.Parent {
		http.NotFound(w, r)
		return
	}
	if origin != "" {
		w.Header().Set("Vary", "Origin")
		w.Header().Set("Access-Control-Allow-Origin", origin)
	}
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Methods", "GET, HEAD")
		w.Header().Set("Access-Control-Allow-Private-Network", "true")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	serveModuleAsset(w, r, claim.Package, prefix+"_ticket/"+ticket+"/", claim.Parent)
}

func validAssetRequest(w http.ResponseWriter, r *http.Request, ticket bool) bool {
	// Tickets outlive launch and do not ordinarily consult project state.
	// Enforce the machine policy here too, for both asset routes and preflight.
	if customUIDisabled() {
		http.NotFound(w, r)
		return false
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead &&
		!(ticket && r.Method == http.MethodOptions) {
		w.Header().Set("Allow", "GET, HEAD")
		w.WriteHeader(http.StatusMethodNotAllowed)
		return false
	}
	if !validAssetPath(r.PathValue("rest")) || !uiAuthority.MatchString(r.Host) ||
		r.Header.Get(
			"Service-Worker",
		) != "" || r.Header.Get("Sec-Fetch-Dest") == "serviceworker" {
		http.NotFound(w, r)
		return false
	}
	return true
}

func openBundleAsset(bundle, name string) (*os.File, os.FileInfo, error) {
	// The store is immutable. Reject a symlink at the output root itself;
	// os.Root then prevents races and symlink escapes within that directory.
	info, err := os.Lstat(bundle)
	if err != nil || !info.IsDir() {
		return nil, nil, fs.ErrNotExist
	}
	root, err := os.OpenRoot(bundle)
	if err != nil {
		return nil, nil, err
	}
	defer root.Close()
	info, err = root.Stat(name)
	if err != nil || !info.Mode().IsRegular() {
		return nil, nil, fs.ErrNotExist
	}
	f, err := root.Open(name)
	if err != nil {
		return nil, nil, err
	}
	info, err = f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		f.Close()
		return nil, nil, fs.ErrNotExist
	}
	return f, info, nil
}

func serveModuleAsset(
	w http.ResponseWriter,
	r *http.Request,
	bundle, prefix, parent string,
) {
	name := r.PathValue("rest")
	f, info, err := openBundleAsset(bundle, name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer f.Close()
	typeName := mime.TypeByExtension(path.Ext(name))
	if typeName == "" {
		typeName = "application/octet-stream"
	}
	h := w.Header()
	h.Set("Content-Type", typeName)
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("Cache-Control", "no-store")
	h.Set("Cross-Origin-Opener-Policy", "same-origin")
	h.Set("Cross-Origin-Embedder-Policy", "require-corp")
	h.Set("Cross-Origin-Resource-Policy", "cross-origin") // opaque frame subresources
	h.Set(
		"Permissions-Policy",
		"camera=(), microphone=(), geolocation=(), display-capture=(), payment=(), usb=(), serial=()",
	)
	ancestors := "'self'"
	if parent != "" && validStudioOrigin(parent) {
		ancestors += " " + parent
	}
	// A path source (rather than 'self') allows only the bundle, not the rest
	// of the agent origin. An explicit source also works with an opaque origin.
	scheme := "http://"
	if r.TLS != nil {
		scheme = "https://"
	}
	source := scheme + r.Host + prefix
	h.Set(
		"Content-Security-Policy",
		"sandbox allow-scripts; default-src 'none'; script-src "+source+"; style-src 'unsafe-inline' "+source+"; img-src data: "+source+"; font-src "+source+"; connect-src 'none'; worker-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors "+ancestors,
	)
	http.ServeContent(w, r, name, info.ModTime(), f)
}
