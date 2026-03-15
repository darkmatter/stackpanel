package nixdata

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// ---------------------------------------------------------------------------
// Entity classification
// ---------------------------------------------------------------------------

func TestValidateEntityName(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{name: "simple", input: "apps", wantErr: false},
		{name: "with hyphen", input: "step-ca", wantErr: false},
		{name: "with underscore", input: "my_entity", wantErr: false},
		{name: "leading underscore", input: "_private", wantErr: false},
		{name: "alphanumeric", input: "v2apps", wantErr: false},
		{name: "empty", input: "", wantErr: true},
		{name: "starts with digit", input: "1apps", wantErr: true},
		{name: "starts with hyphen", input: "-apps", wantErr: true},
		{name: "contains space", input: "my apps", wantErr: true},
		{name: "contains dot", input: "my.apps", wantErr: true},
		{name: "contains slash", input: "my/apps", wantErr: true},
		{name: "too long", input: strings.Repeat("a", 65), wantErr: true},
		{name: "max length", input: strings.Repeat("a", 64), wantErr: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateEntityName(tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("ValidateEntityName(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			}
		})
	}
}

func TestIsExternalEntity(t *testing.T) {
	tests := []struct {
		input string
		want  bool
	}{
		{"external-github-collaborators", true},
		{"external-users", true},
		{"external-x", true},
		{"apps", false},
		{"variables", false},
		{"external", false},
		{"external-", false},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			if got := IsExternalEntity(tt.input); got != tt.want {
				t.Errorf("IsExternalEntity(%q) = %v, want %v", tt.input, got, tt.want)
			}
		})
	}
}

func TestIsMapEntity(t *testing.T) {
	mapEntities := []string{"apps", "variables", "users"}
	nonMapEntities := []string{"secrets", "dns", "theme", "onboarding", "config", "sst", "aws"}

	for _, entity := range mapEntities {
		if !IsMapEntity(entity) {
			t.Errorf("IsMapEntity(%q) = false, want true", entity)
		}
	}
	for _, entity := range nonMapEntities {
		if IsMapEntity(entity) {
			t.Errorf("IsMapEntity(%q) = true, want false", entity)
		}
	}
}

func TestIsEvaluatedEntity(t *testing.T) {
	if !IsEvaluatedEntity("variables") {
		t.Error("IsEvaluatedEntity(\"variables\") = false, want true")
	}
	for _, entity := range []string{"apps", "users", "secrets", "config"} {
		if IsEvaluatedEntity(entity) {
			t.Errorf("IsEvaluatedEntity(%q) = true, want false", entity)
		}
	}
}

func TestMapFieldNames(t *testing.T) {
	fields := MapFieldNames()

	required := []string{
		"aliases", "apps", "categories", "codegen", "collaborators",
		"commands", "databases", "env", "environments", "entries",
		"extensions", "masterKeys", "modules", "outputs", "scripts",
		"sites", "steps", "tasks", "users", "variables", "zones",
	}

	for _, name := range required {
		if _, ok := fields[name]; !ok {
			t.Errorf("MapFieldNames() missing required field %q", name)
		}
	}

	if len(fields) != len(required) {
		t.Errorf("MapFieldNames() has %d entries, want %d", len(fields), len(required))
	}
}

// ---------------------------------------------------------------------------
// Key transforms: individual strings
// ---------------------------------------------------------------------------

func TestKebabToCamel(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"variable-id", "variableId"},
		{"ca-url", "caUrl"},
		{"already", "already"},
		{"store-path", "storePath"},
		{"a-b-c", "aBC"},
		{"", ""},
		{"no-change", "noChange"},
		{"x", "x"},
		{"master-keys", "masterKeys"},
		{"binary-cache", "binaryCache"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			if got := KebabToCamel(tt.input); got != tt.want {
				t.Errorf("KebabToCamel(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestCamelToKebab(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"variableId", "variable-id"},
		{"caUrl", "ca-url"},
		{"already", "already"},
		{"storePath", "store-path"},
		{"masterKeys", "master-keys"},
		{"binaryCache", "binary-cache"},
		{"", ""},
		{"x", "x"},
		{"ABC", "a-b-c"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			if got := CamelToKebab(tt.input); got != tt.want {
				t.Errorf("CamelToKebab(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Key transforms: recursive JSON structures
// ---------------------------------------------------------------------------

func TestTransformKeysToCamel(t *testing.T) {
	t.Run("flat object", func(t *testing.T) {
		input := map[string]any{
			"store-path":  "/nix/store/abc",
			"variable-id": "web-port",
		}
		result := TransformKeysToCamel(input, MapFieldNames(), "").(map[string]any)

		assertKey(t, result, "storePath", "/nix/store/abc")
		assertKey(t, result, "variableId", "web-port")
	})

	t.Run("preserves map field keys", func(t *testing.T) {
		input := map[string]any{
			"variables": map[string]any{
				"/apps/web/port": map[string]any{
					"variable-id": "web-port",
					"env-ref":     "$WEB_PORT",
				},
			},
		}
		result := TransformKeysToCamel(input, MapFieldNames(), "").(map[string]any)

		vars := result["variables"].(map[string]any)
		// The key "/apps/web/port" should be preserved (parent is "variables", a map field).
		entry, ok := vars["/apps/web/port"]
		if !ok {
			t.Fatal("expected key /apps/web/port to be preserved in variables map")
		}
		inner := entry.(map[string]any)
		assertKey(t, inner, "variableId", "web-port")
		assertKey(t, inner, "envRef", "$WEB_PORT")
	})

	t.Run("arrays pass through", func(t *testing.T) {
		input := []any{
			map[string]any{"store-path": "a"},
			map[string]any{"store-path": "b"},
		}
		result := TransformKeysToCamel(input, MapFieldNames(), "").([]any)
		if len(result) != 2 {
			t.Fatalf("expected 2 items, got %d", len(result))
		}
		assertKey(t, result[0].(map[string]any), "storePath", "a")
	})

	t.Run("primitives unchanged", func(t *testing.T) {
		if got := TransformKeysToCamel("hello", MapFieldNames(), ""); got != "hello" {
			t.Errorf("expected string passthrough, got %v", got)
		}
		if got := TransformKeysToCamel(42.0, MapFieldNames(), ""); got != 42.0 {
			t.Errorf("expected number passthrough, got %v", got)
		}
		if got := TransformKeysToCamel(nil, MapFieldNames(), ""); got != nil {
			t.Errorf("expected nil passthrough, got %v", got)
		}
	})
}

func TestTransformKeysToKebab(t *testing.T) {
	t.Run("flat object", func(t *testing.T) {
		input := map[string]any{
			"storePath":  "/nix/store/abc",
			"variableId": "web-port",
		}
		result := TransformKeysToKebab(input, MapFieldNames(), "").(map[string]any)

		assertKey(t, result, "store-path", "/nix/store/abc")
		assertKey(t, result, "variable-id", "web-port")
	})

	t.Run("preserves map field keys", func(t *testing.T) {
		input := map[string]any{
			"variables": map[string]any{
				"/apps/web/port": map[string]any{
					"variableId": "web-port",
				},
			},
		}
		result := TransformKeysToKebab(input, MapFieldNames(), "").(map[string]any)

		vars := result["variables"].(map[string]any)
		entry, ok := vars["/apps/web/port"]
		if !ok {
			t.Fatal("expected key /apps/web/port to be preserved in variables map")
		}
		inner := entry.(map[string]any)
		assertKey(t, inner, "variable-id", "web-port")
	})
}

// ---------------------------------------------------------------------------
// Full JSON round-trip transforms
// ---------------------------------------------------------------------------

func TestNixJSONToCamelCase(t *testing.T) {
	t.Run("empty input", func(t *testing.T) {
		out, err := NixJSONToCamelCase(nil, MapFieldNames())
		if err != nil {
			t.Fatal(err)
		}
		if out != nil {
			t.Errorf("expected nil, got %s", out)
		}
	})

	t.Run("converts kebab keys", func(t *testing.T) {
		input := `{"store-path":"/nix/store/abc","is-stale":false}`
		out, err := NixJSONToCamelCase([]byte(input), MapFieldNames())
		if err != nil {
			t.Fatal(err)
		}

		var result map[string]any
		if err := json.Unmarshal(out, &result); err != nil {
			t.Fatal(err)
		}
		assertKey(t, result, "storePath", "/nix/store/abc")
		assertKey(t, result, "isStale", false)
	})
}

func TestCamelCaseToNixJSON(t *testing.T) {
	t.Run("empty input", func(t *testing.T) {
		out, err := CamelCaseToNixJSON(nil, MapFieldNames())
		if err != nil {
			t.Fatal(err)
		}
		if out != nil {
			t.Errorf("expected nil, got %s", out)
		}
	})

	t.Run("converts camel keys", func(t *testing.T) {
		input := `{"storePath":"/nix/store/abc","isStale":false}`
		out, err := CamelCaseToNixJSON([]byte(input), MapFieldNames())
		if err != nil {
			t.Fatal(err)
		}

		var result map[string]any
		if err := json.Unmarshal(out, &result); err != nil {
			t.Fatal(err)
		}
		assertKey(t, result, "store-path", "/nix/store/abc")
		assertKey(t, result, "is-stale", false)
	})
}

func TestRoundTripTransforms(t *testing.T) {
	// Nix JSON -> camelCase -> back to kebab should be identity.
	original := `{"store-path":"/nix/store/abc","binary-cache":{"url":"https://cache.example.com"}}`

	camel, err := NixJSONToCamelCase([]byte(original), MapFieldNames())
	if err != nil {
		t.Fatal(err)
	}

	back, err := CamelCaseToNixJSON(camel, MapFieldNames())
	if err != nil {
		t.Fatal(err)
	}

	var origMap, backMap map[string]any
	if err := json.Unmarshal([]byte(original), &origMap); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(back, &backMap); err != nil {
		t.Fatal(err)
	}

	origJSON, _ := json.Marshal(origMap)
	backJSON, _ := json.Marshal(backMap)
	if string(origJSON) != string(backJSON) {
		t.Errorf("round-trip mismatch:\n  original: %s\n  got:      %s", origJSON, backJSON)
	}
}

func TestSetKey(t *testing.T) {
	path := "/.stack/config.nix"
	root := os.Getenv("STACKPANEL_ROOT")
	curr, err := os.ReadFile(root + path)
	if err != nil {
		t.Fatal(err)
	}
	data := map[string]any{}

	if err := json.Unmarshal(curr, &data); err != nil {
		t.Fatal(err)
	}

	data["cowgoes"] = "moo"

	newCurr, err := os.ReadFile(root + path)
	if err != nil {
		t.Fatal(err)
	}

	if string(curr) == string(newCurr) {
		t.Error("key was not set")
	}
}

func TestTransformPreservesMapFieldKeysRoundTrip(t *testing.T) {
	// A variables map with user-defined keys that include special chars.
	original := `{"variables":{"/apps/web/port":{"variable-id":"web-port","env-ref":"$WEB_PORT"},"/db/url":{"variable-id":"db-url"}}}`

	camel, err := NixJSONToCamelCase([]byte(original), MapFieldNames())
	if err != nil {
		t.Fatal(err)
	}

	// Verify camel version preserves the variable keys.
	var camelMap map[string]any
	if err := json.Unmarshal(camel, &camelMap); err != nil {
		t.Fatal(err)
	}
	vars := camelMap["variables"].(map[string]any)
	if _, ok := vars["/apps/web/port"]; !ok {
		t.Error("variable key /apps/web/port was transformed when it should be preserved")
	}
	if _, ok := vars["/db/url"]; !ok {
		t.Error("variable key /db/url was transformed when it should be preserved")
	}

	// Inner field names should be camelCase.
	entry := vars["/apps/web/port"].(map[string]any)
	if _, ok := entry["variableId"]; !ok {
		t.Error("inner field 'variable-id' should have been transformed to 'variableId'")
	}

	// Round trip back.
	back, err := CamelCaseToNixJSON(camel, MapFieldNames())
	if err != nil {
		t.Fatal(err)
	}

	var origMap, backMap map[string]any
	if err := json.Unmarshal([]byte(original), &origMap); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(back, &backMap); err != nil {
		t.Fatal(err)
	}

	origJSON, _ := json.Marshal(origMap)
	backJSON, _ := json.Marshal(backMap)
	if string(origJSON) != string(backJSON) {
		t.Errorf("round-trip with map fields mismatch:\n  original: %s\n  got:      %s", origJSON, backJSON)
	}
}

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

func TestPaths(t *testing.T) {
	p := NewPaths("/home/user/myproject")

	if got := p.Dir(); got != "/home/user/myproject/.stack" {
		t.Errorf("Dir() = %q", got)
	}
	if got := p.ConfigFilePath(); got != "/home/user/myproject/.stack/config.nix" {
		t.Errorf("ConfigFilePath() = %q", got)
	}
	if got := p.LegacyDataDir(); got != "/home/user/myproject/.stack/data" {
		t.Errorf("LegacyDataDir() = %q", got)
	}
	if got := p.ExternalDataDir(); got != "/home/user/myproject/.stack/data" {
		t.Errorf("ExternalDataDir() = %q", got)
	}
	if got := p.ExternalEntityPath("external-github-collaborators"); got != "/home/user/myproject/.stack/data/github-collaborators.nix" {
		t.Errorf("ExternalEntityPath() = %q", got)
	}
}

func TestParseConfigPath(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"stackpanel.deployment.fly.organization", "deployment.fly.organization"},
		{"deployment.fly.organization", "deployment.fly.organization"},
		{"stackpanel.apps", "apps"},
		{"apps", "apps"},
		{"stackpanel.", ""},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			if got := ParseConfigPath(tt.input); got != tt.want {
				t.Errorf("ParseConfigPath(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestNormalizeConfigPathParts_PreservesMapKeys(t *testing.T) {
	got := NormalizeConfigPathParts("apps.web.environments.dev.env.PORT")
	want := []string{"apps", "web", "environments", "dev", "env", "PORT"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("NormalizeConfigPathParts() = %#v, want %#v", got, want)
	}
}

func TestNormalizeConfigPathParts_ConvertsRegularFields(t *testing.T) {
	got := NormalizeConfigPathParts("deployment.fly.organization")
	want := []string{"deployment", "fly", "organization"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("NormalizeConfigPathParts() = %#v, want %#v", got, want)
	}
}

func TestEscapeConfigPathSegment(t *testing.T) {
	got := EscapeConfigPathSegment(`/dev/foo.bar\baz`)
	want := `/dev/foo\.bar\\baz`
	if got != want {
		t.Fatalf("EscapeConfigPathSegment() = %q, want %q", got, want)
	}
}

func TestSplitConfigPath_EscapedDots(t *testing.T) {
	got := SplitConfigPath(`variables./dev/foo\.bar.value`)
	want := []string{"variables", "/dev/foo.bar", "value"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("SplitConfigPath() = %#v, want %#v", got, want)
	}
}

func TestNormalizeConfigPathParts_PreservesEscapedDots(t *testing.T) {
	got := NormalizeConfigPathParts(`variables./dev/foo\.bar.value`)
	want := []string{"variables", "/dev/foo.bar", "value"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("NormalizeConfigPathParts() = %#v, want %#v", got, want)
	}
}

func TestSetKey_ConsolidatedConfigEscapesDots(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, ".stack")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatalf("mkdir .stack: %v", err)
	}
	configPath := filepath.Join(configDir, "config.nix")
	initial := `{ config, ... }: {
  variables = {};
}
`
	if err := os.WriteFile(configPath, []byte(initial), 0o644); err != nil {
		t.Fatalf("write config.nix: %v", err)
	}

	store := NewStore(root, nil)
	if _, err := store.SetKey("variables", "/dev/foo.bar", map[string]any{"value": "hello"}); err != nil {
		t.Fatalf("SetKey() error = %v", err)
	}

	updated, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config.nix: %v", err)
	}
	text := string(updated)
	variablesIndex := strings.Index(text, `variables = {`)
	keyIndex := strings.Index(text, `"/dev/foo.bar" = {`)
	if variablesIndex == -1 || keyIndex == -1 || variablesIndex > keyIndex {
		t.Fatalf("expected variable binding nested under variables attrset, got:\n%s", text)
	}
	if !strings.Contains(text, `"/dev/foo.bar" = {`) {
		t.Fatalf("expected escaped variable binding, got:\n%s", text)
	}
	if !strings.Contains(text, `value = "hello";`) {
		t.Fatalf("expected value binding, got:\n%s", text)
	}
}

func TestDeleteKey_ConsolidatedConfigEscapesDots(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, ".stack")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatalf("mkdir .stack: %v", err)
	}
	configPath := filepath.Join(configDir, "config.nix")
	initial := `{ config, ... }: {
  variables = {
    "/dev/foo.bar" = {
      value = "hello";
    };
  };
}
`
	if err := os.WriteFile(configPath, []byte(initial), 0o644); err != nil {
		t.Fatalf("write config.nix: %v", err)
	}

	store := NewStore(root, nil)
	if _, err := store.DeleteKey("variables", "/dev/foo.bar"); err != nil {
		t.Fatalf("DeleteKey() error = %v", err)
	}

	updated, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config.nix: %v", err)
	}
	if strings.Contains(string(updated), `"/dev/foo.bar"`) {
		t.Fatalf("expected variable binding to be removed, got:\n%s", string(updated))
	}
}

func TestSectionHeaders(t *testing.T) {
	headers := SectionHeaders()

	// Spot-check a few expected entries.
	expected := map[string]string{
		"apps":      "Apps",
		"variables": "Variables",
		"users":     "Users",
		"secrets":   "Secrets",
		"aws":       "AWS",
		"sst":       "SST",
		"step-ca":   "Step CA",
	}

	for key, wantValue := range expected {
		if got, ok := headers[key]; !ok {
			t.Errorf("SectionHeaders() missing key %q", key)
		} else if got != wantValue {
			t.Errorf("SectionHeaders()[%q] = %q, want %q", key, got, wantValue)
		}
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func assertKey(t *testing.T, m map[string]any, key string, want any) {
	t.Helper()
	got, ok := m[key]
	if !ok {
		t.Errorf("missing key %q in %v", key, m)
		return
	}
	// json.Unmarshal decodes numbers as float64, so compare accordingly.
	switch w := want.(type) {
	case bool:
		if got != w {
			t.Errorf("key %q = %v (%T), want %v (%T)", key, got, got, w, w)
		}
	case string:
		if got != w {
			t.Errorf("key %q = %v, want %v", key, got, w)
		}
	case float64:
		if got != w {
			t.Errorf("key %q = %v, want %v", key, got, w)
		}
	default:
		gotJSON, _ := json.Marshal(got)
		wantJSON, _ := json.Marshal(want)
		if string(gotJSON) != string(wantJSON) {
			t.Errorf("key %q = %s, want %s", key, gotJSON, wantJSON)
		}
	}
}
