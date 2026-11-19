package registry

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

type transportFunc func(*http.Request) (*http.Response, error)

func (f transportFunc) RoundTrip(
	r *http.Request,
) (*http.Response, error) {
	return f(r)
}

func TestUnwritableCacheDoesNotDiscardValidatedCatalog(t *testing.T) {
	const src = "https://example.test/catalog"
	for _, status := range []int{http.StatusOK, http.StatusNotModified} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			root := filepath.Join(t.TempDir(), "xdg-cache")
			t.Setenv("XDG_CACHE_HOME", root)
			c := NewClient([]string{src}, nil, nil)
			body := manifest(t, module("valid"))
			if status == http.StatusNotModified {
				rec := cacheRecord{
					Checked: c.now().Add(-2 * cacheTTL),
					ETag:    `"v1"`,
					Body:    []byte(body),
				}
				if err := writeRecord(c.cachePath("catalog", src, nil), rec); err != nil {
					t.Fatal(err)
				}
			}
			c.http.Transport = transportFunc(func(r *http.Request) (*http.Response, error) {
				if status == http.StatusNotModified {
					if r.Header.Get("If-None-Match") != `"v1"` {
						t.Fatal("expected stale record to be revalidated")
					}
					if err := os.Rename(root, root+"-offline"); err != nil {
						t.Fatal(err)
					}
					body = ""
				}
				// A file in place of the cache directory blocks writes even as root.
				if err := os.WriteFile(root, nil, 0o600); err != nil {
					t.Fatal(err)
				}
				return response(status, `"v1"`, body)
			})
			got, err := c.List(t.Context())
			if err != nil || len(got) != 1 || got[0].ID != "valid" {
				t.Fatalf("List = %v, %v", got, err)
			}
		})
	}
}

func response(status int, etag, body string) (*http.Response, error) {
	h := http.Header{}
	if etag != "" {
		h.Set("ETag", etag)
	}
	return &http.Response{
		StatusCode: status,
		Header:     h,
		Body:       io.NopCloser(strings.NewReader(body)),
	}, nil
}

func module(id string) Module {
	return Module{
		ID:            id,
		Slug:          id,
		Name:          id,
		Description:   "Static analysis tooling",
		Category:      "tools",
		Icon:          "wrench",
		Author:        "Test",
		Tier:          "community",
		Features:      []string{"check"},
		UISlots:       []string{},
		Tags:          []string{"lint"},
		LatestVersion: "1.0.0",
		Versions: []Version{
			{Version: "1.0.0", FlakeURL: "github:example/" + id, FlakeInputs: []FlakeInput{}},
		},
	}
}

func manifest(t *testing.T, modules ...Module) string {
	t.Helper()
	b, err := json.Marshal(Catalog{SchemaVersion: 1, Modules: modules})
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestDiskTTLAndConditionalRefresh(t *testing.T) {
	const src = "https://example.test/catalog"
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	now := time.Unix(10000, 0)
	calls := 0
	// Construct a fresh client every time: hits and validators must survive
	// process restarts, and no test sleeps or depends on wall clock mtimes.
	list := func(want string, wantCalls int) {
		t.Helper()
		c := NewClient([]string{src}, nil, nil)
		c.now = func() time.Time { return now }
		c.http.Transport = transportFunc(func(r *http.Request) (*http.Response, error) {
			calls++
			switch calls {
			case 1:
				if r.Header.Get("If-None-Match") != "" {
					t.Fatal("unexpected validator on first request")
				}
				return response(200, `W/"one"`, manifest(t, module("one")))
			case 2:
				if got := r.Header.Get("If-None-Match"); got != `W/"one"` {
					t.Fatalf("If-None-Match = %q", got)
				}
				return response(304, `"two"`, "")
			case 3:
				if got := r.Header.Get("If-None-Match"); got != `"two"` {
					t.Fatalf("validator not refreshed: %q", got)
				}
				return response(200, `"three"`, manifest(t, module("two")))
			default:
				return response(503, "", "")
			}
		})
		got, err := c.List(t.Context())
		if err != nil || len(got) != 1 || got[0].ID != want || calls != wantCalls {
			t.Fatalf(
				"List = %v, %v after %d calls; want %s after %d",
				got,
				err,
				calls,
				want,
				wantCalls,
			)
		}
	}
	list("one", 1)
	now = now.Add(cacheTTL - time.Nanosecond)
	list("one", 1)
	now = now.Add(time.Nanosecond)
	list("one", 2)
	now = now.Add(cacheTTL - time.Nanosecond)
	list("one", 2)
	now = now.Add(time.Nanosecond)
	list("two", 3)
	now = now.Add(cacheTTL)
	list("two", 4) // a real, stale private response is safe on upstream outage
	list("two", 5) // stale use does not extend freshness
}

func TestOrderedSources(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	const a, b = "https://example.test/a", "https://example.test/b"
	first := module("project")
	first.Slug = "tool"
	bySlug := module("overlap")
	bySlug.Slug = first.Slug
	byID := module(first.ID)
	byID.Slug = "other"
	var sources []string
	c := NewClient([]string{a, a}, []string{a, b, b}, nil)
	c.http.Transport = transportFunc(func(r *http.Request) (*http.Response, error) {
		sources = append(sources, r.URL.String())
		switch r.URL.String() {
		case a:
			return response(200, "", manifest(t, first))
		case b:
			return response(200, "", manifest(t, bySlug, byID, module("machine")))
		}
		return nil, errors.New("unexpected source")
	})
	got, err := c.List(t.Context())
	if err != nil || !slices.Equal(sources, []string{a, b}) || len(got) != 2 ||
		got[0].Slug != "tool" ||
		got[0].ID != "project" ||
		got[1].ID != "machine" {
		t.Fatalf("List = %v, %v; sources = %v", got, err, sources)
	}
	if !got[0].Matches("stAtic", "Tools", "LINT") || got[0].Matches("", "other", "") ||
		got[0].Matches("", "", "other") {
		t.Fatal("incorrect query/category/tag filtering")
	}
}

func TestOfflineFallbackIsOfficialOnly(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	offline := transportFunc(
		func(*http.Request) (*http.Response, error) { return nil, errors.New("offline") },
	)
	c := NewClient(nil, nil, nil)
	c.http.Transport = offline
	modules, err := c.List(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	for _, slug := range []string{"rust", "astro", "nextjs", "remix", "nuxt", "oxlint", "playwright", "fly"} {
		i := slices.IndexFunc(modules, func(m Module) bool { return m.ID == slug })
		if i < 0 || modules[i].Slug != slug ||
			modules[i].Versions[0].FlakeURL != "github:darkmatter/stackpanel-registry?dir=modules/"+slug {
			t.Errorf("missing official module %s", slug)
		}
	}
	for _, urls := range [][]string{
		{"https://private.test/registry"},
		{OfficialURL, "https://private.test/registry"},
		{OfficialURL + "?private=1"},
		{"https://raw.githubusercontent.com/darkmatter/stackpanel-registry/main/modules.json"},
	} {
		c := NewClient(urls, nil, nil)
		c.http.Transport = offline
		if got, err := c.List(t.Context()); err == nil || got != nil {
			t.Fatalf("unavailable source %v: got %d modules, err=%v", urls, len(got), err)
		}
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := c.List(ctx); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancellation hidden by offline snapshot: %v", err)
	}
}

func TestReadmeAndCredentialScope(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	const index = "https://private.test/registry"
	const other = "https://private.test:8443/readme"
	const secret = "only-from-machine"
	headers := map[string]map[string]string{
		index: {"Authorization": "Bearer " + secret, "X-Machine-Key": secret},
	}
	c := NewClient(nil, []string{index}, headers)
	now := time.Unix(10000, 0)
	c.now = func() time.Time { return now }
	calls := 0
	c.http.Transport = transportFunc(func(r *http.Request) (*http.Response, error) {
		wantCreds := r.URL.Host == "private.test"
		if (r.Header.Get("X-Machine-Key") == secret) != wantCreds ||
			(r.Header.Get("Authorization") == "Bearer "+secret) != wantCreds {
			t.Fatal("incorrect credential scope for", r.URL)
		}
		switch r.URL.String() {
		case index:
			a, b, d := module("private"), module("external"), module("redirect")
			a.ReadmeURL, b.ReadmeURL, d.ReadmeURL = "https://private.test/readme", other, "https://private.test/redirect"
			return response(200, "", manifest(t, a, b, d))
		case "https://private.test/readme":
			calls++
			if calls == 1 {
				return response(200, `"v1"`, "# Private README")
			}
			if r.Header.Get("If-None-Match") != `"v1"` {
				t.Fatal("missing README validator")
			}
			return response(304, "", "")
		case other:
			return response(200, "", "public readme")
		case "https://private.test/redirect":
			resp, err := response(302, "", "")
			resp.Header.Set("Location", "https://untrusted.test/target")
			return resp, err
		default:
			t.Fatalf("redirect followed to %s", r.URL)
			return nil, nil
		}
	})
	mods, err := c.List(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	for i, advance := range []time.Duration{0, cacheTTL - time.Second, time.Second} {
		now = now.Add(advance)
		got, err := c.Readme(t.Context(), mods[0])
		if err != nil || got != "# Private README" || calls != []int{1, 1, 2}[i] {
			t.Fatalf("Readme() = %q, %v; calls %d", got, err, calls)
		}
	}
	if got, err := c.Readme(t.Context(), mods[1]); err != nil || got != "public readme" {
		t.Fatalf("external Readme() = %q, %v", got, err)
	}
	if _, err := c.Readme(t.Context(), mods[2]); err == nil {
		t.Fatal("redirect succeeded")
	}
	// Removing the machine credential must not reveal previously cached
	// private content, even if the project lists exactly the same URL.
	anon := NewClient([]string{index}, nil, nil)
	anon.now = c.now
	anon.http.Transport = transportFunc(func(r *http.Request) (*http.Response, error) {
		if len(r.Header) != 0 {
			t.Fatal("credentials reused")
		}
		return response(403, "", "")
	})
	if _, err := anon.List(t.Context()); err == nil {
		t.Fatal("private catalog visible without credential")
	}
	if _, err := anon.Readme(t.Context(), mods[0]); err == nil {
		t.Fatal("private README visible without credential")
	}
}

func TestInvalidResponseDoesNotPoisonCache(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	const src = "https://private.test/catalog"
	c := NewClient([]string{src}, nil, nil)
	now := time.Unix(10000, 0)
	c.now = func() time.Time { return now }
	body, status := manifest(t, module("real")), 200
	c.http.Transport = transportFunc(
		func(*http.Request) (*http.Response, error) { return response(status, `"ok"`, body) },
	)
	if _, err := c.List(t.Context()); err != nil {
		t.Fatal(err)
	}
	now = now.Add(cacheTTL)
	body = `{"schemaVersion":2,"modules":[]}`
	if _, err := c.List(t.Context()); err == nil {
		t.Fatal("invalid version masked by stale response")
	}
	status = 503
	if got, err := c.List(
		t.Context(),
	); err != nil || len(got) != 1 ||
		got[0].ID != "real" {
		t.Fatalf("lost good cache: %v, %v", got, err)
	}
	status = 403
	if _, err := c.List(t.Context()); err == nil {
		t.Fatal("denial masked by stale response")
	}
	status = 503
	if _, err := c.List(t.Context()); err == nil {
		t.Fatal("served cached response after denial")
	}
}

func TestCorruptDiskRecordForcesUnconditionalRefresh(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	const src = "https://example.test/catalog"
	c := NewClient([]string{src}, nil, nil)
	path := c.cachePath("catalog", src, nil)
	if err := writeRecord(
		path,
		cacheRecord{Checked: c.now(), ETag: `"bad"`, Body: []byte("not a catalog")},
	); err != nil {
		t.Fatal(err)
	}
	c.http.Transport = transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.Header.Get("If-None-Match") != "" {
			t.Fatal("used validator from invalid disk cache")
		}
		return response(200, "", manifest(t, module("recovered")))
	})
	got, err := c.List(t.Context())
	if err != nil || len(got) != 1 || got[0].ID != "recovered" {
		t.Fatalf("corruption recovery: %v, %v", got, err)
	}
	if info, err := os.Stat(path); err != nil || info.Mode().Perm()&0o077 != 0 {
		t.Fatal("cache not private", err)
	}
}
