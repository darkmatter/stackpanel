package registry

import (
	"net/http"
	"strings"
	"testing"
)

func TestCatalogValidation(t *testing.T) {
	valid := manifest(t, module("tool"))
	if _, err := decodeCatalog([]byte(valid)); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ name, before, after string }{
		{"unknown version", `"schemaVersion":1`, `"schemaVersion":2`},
		{"missing slug", `"slug":"tool",`, ``},
		{"unknown property", `"slug":"tool"`, `"slug":"tool","extra":true`},
		{"tier", `"tier":"community"`, `"tier":"staff"`},
		{"local flake", `github:example/tool`, `path:/private`},
		{"input expression", `"flakeInputs":[]`, `"flakePath":"x; abort 1","flakeInputs":[]`},
		{"missing latest", `"latestVersion":"1.0.0"`, `"latestVersion":"9"`},
		{"wrong boolean type", `"followsNixpkgs":false`, `"followsNixpkgs":"false"`},
		{"input name collision", `"flakeInputs":[]`, `"flakeInputs":[{"name":"tool","url":"github:example/dependency","followsNixpkgs":false}]`},
		{"credentials in URL", `"slug":"tool"`, `"slug":"tool","readmeUrl":"https://a:b@example.test/a"`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			data := strings.Replace(valid, tc.before, tc.after, 1)
			if data == valid {
				t.Fatal("test did not modify fixture")
			}
			if _, err := decodeCatalog([]byte(data)); err == nil {
				t.Fatal("accepted invalid catalog")
			}
		})
	}
	m := module("tool")
	m.Versions = append(m.Versions, m.Versions[0])
	if _, err := decodeCatalog([]byte(manifest(t, m))); err == nil {
		t.Fatal("accepted duplicate version")
	}
	m = module("other")
	m.Slug = "tool"
	if _, err := decodeCatalog([]byte(manifest(t, m, module("tool")))); err == nil {
		t.Fatal("accepted ambiguous identity within one catalog")
	}
}

func TestCredentialsBoundToExactIndex(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	const private = "https://example.test/org/catalog"
	const project = "https://example.test/org/catalog?fork=1"
	c := NewClient(
		[]string{project},
		[]string{private},
		map[string]map[string]string{private: {"X-Api-Key": "value"}},
	)
	calls := 0
	c.http.Transport = transportFunc(func(r *http.Request) (*http.Response, error) {
		calls++
		if (r.URL.String() == private) != (r.Header.Get("X-Api-Key") == "value") {
			t.Fatal("incorrect credential scope")
		}
		return response(200, "", `{"schemaVersion":1,"modules":[]}`)
	})
	if _, err := c.List(t.Context()); err != nil || calls != 2 {
		t.Fatalf("List made %d requests: %v", calls, err)
	}
	for _, src := range []string{"https://user:password@example.test/catalog", "http://example.test/catalog", "file:///etc/config"} {
		c := NewClient(
			nil,
			[]string{src},
			map[string]map[string]string{src: {"X-Api-Key": "value"}},
		)
		c.http.Transport = transportFunc(func(*http.Request) (*http.Response, error) {
			t.Fatal("insecure registry requested")
			return nil, nil
		})
		if _, err := c.List(
			t.Context(),
		); err == nil ||
			strings.Contains(err.Error(), "password") {
			t.Fatalf("insecure URL not safely rejected: %v", err)
		}
	}
}
