package registry

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"
	"unicode/utf8"
)

const (
	cacheTTL   = time.Hour
	maxCatalog = 4 << 20
	maxReadme  = 1 << 20
)

type Client struct {
	sources  []string
	headers  map[string]map[string]string
	cacheDir string
	http     *http.Client
	now      func() time.Time
}

// NewClient searches the configured project sources followed by machine
// sources. With no explicit sources the sole source is the official index.
// Only pass headers from machine configuration, keyed by exact index URL.
func NewClient(
	projectURLs, machineURLs []string,
	machineHeaders map[string]map[string]string,
) *Client {
	c := &Client{
		headers: make(map[string]map[string]string),
		http: &http.Client{
			Timeout: 10 * time.Second,
			// Custom auth headers are not among net/http's stripped headers.
			// Require direct URLs rather than forwarding any requests on redirects.
			CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse },
		},
		now: time.Now,
	}
	root := os.Getenv("XDG_CACHE_HOME")
	if !filepath.IsAbs(root) {
		if home, err := os.UserHomeDir(); err == nil {
			root = filepath.Join(home, ".cache")
		}
	}
	if filepath.IsAbs(root) {
		c.cacheDir = filepath.Join(root, "stackpanel", "registry")
	}
	seen := make(map[string]bool)
	for _, group := range [][]string{projectURLs, machineURLs} {
		for _, src := range group {
			if !seen[src] {
				c.sources = append(c.sources, src)
				seen[src] = true
			}
		}
	}
	if len(c.sources) == 0 {
		c.sources = []string{OfficialURL}
	}
	for _, src := range machineURLs {
		if h := machineHeaders[src]; len(h) > 0 {
			c.headers[src] = maps.Clone(h)
		}
	}
	return c
}

func httpURL(raw string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" ||
		u.User != nil ||
		u.Fragment != "" {
		return nil, errors.New("expected absolute HTTP(S) URL without userinfo or fragment")
	}
	return u, nil
}

// List fails rather than letting a lower-priority source silently supply a
// different module if the authoritative catalog is malformed or unavailable.
func (c *Client) List(ctx context.Context) ([]Module, error) {
	result := make([]Module, 0)
	seen := make(map[string]bool)
	for _, src := range c.sources {
		u, err := httpURL(src)
		if err != nil {
			return nil, fmt.Errorf("invalid registry source: %w", err)
		}
		var fallback []byte
		if src == OfficialURL {
			fallback = snapshot
		}
		modules, err := fetch(
			ctx,
			c,
			u,
			c.headers[src],
			"catalog",
			maxCatalog,
			decodeCatalog,
			fallback,
		)
		if err != nil {
			return nil, fmt.Errorf("registry %s%s: %w", u.Host, u.EscapedPath(), err)
		}
		for _, m := range modules {
			if seen[m.ID] || seen[m.Slug] {
				continue
			}
			seen[m.ID], seen[m.Slug] = true, true
			m.source = src
			result = append(result, m)
		}
	}
	return result, nil
}

// Readme fetches the optional README as untrusted Markdown. An index's
// machine credentials are never attached to another origin, even if that
// origin is itself configured as a registry.
func (c *Client) Readme(ctx context.Context, m Module) (string, error) {
	if m.ReadmeURL == "" {
		return "", nil
	}
	u, err := httpURL(m.ReadmeURL)
	if err != nil {
		return "", fmt.Errorf("invalid README URL: %w", err)
	}
	source, err := httpURL(m.source)
	if err != nil {
		return "", errors.New("README module has no registry source")
	}
	var headers map[string]string
	if u.Host == source.Host && u.Scheme == source.Scheme {
		headers = c.headers[m.source]
	}
	return fetch(ctx, c, u, headers, "readme", maxReadme, decodeReadme, nil)
}

func decodeReadme(data []byte) (string, error) {
	if !utf8.Valid(data) {
		return "", errors.New("README is not UTF-8 text")
	}
	return string(data), nil
}

func allowCredentials(u *url.URL) bool {
	return u.Scheme == "https" || u.Hostname() == "localhost" ||
		net.ParseIP(u.Hostname()).IsLoopback()
}
