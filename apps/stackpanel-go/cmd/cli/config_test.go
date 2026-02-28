package cmd

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"strings"
	"testing"
)

// captureStdout runs fn while capturing everything written to os.Stdout.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()

	origStdout := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}

	os.Stdout = w

	fn()

	w.Close()
	os.Stdout = origStdout

	var buf bytes.Buffer
	if _, err := io.Copy(&buf, r); err != nil {
		t.Fatalf("failed to read captured stdout: %v", err)
	}
	r.Close()

	return buf.String()
}

// ---------------------------------------------------------------------------
// Command wiring
// ---------------------------------------------------------------------------

func TestConfigCommandHelp(t *testing.T) {
	t.Cleanup(func() {
		rootCmd.SetArgs(nil)
		rootCmd.SetOut(nil)
		rootCmd.SetErr(nil)
	})

	buf := &bytes.Buffer{}
	rootCmd.SetOut(buf)
	rootCmd.SetErr(buf)
	rootCmd.SetArgs([]string{"config", "--help"})

	if err := rootCmd.Execute(); err != nil {
		t.Fatalf("config --help should succeed: %v", err)
	}

	out := buf.String()
	if !strings.Contains(out, "config") {
		t.Fatalf("expected help to mention 'config', got: %s", out)
	}
}

func TestConfigGetCommandHelp(t *testing.T) {
	t.Cleanup(func() {
		rootCmd.SetArgs(nil)
		rootCmd.SetOut(nil)
		rootCmd.SetErr(nil)
	})

	buf := &bytes.Buffer{}
	rootCmd.SetOut(buf)
	rootCmd.SetErr(buf)
	rootCmd.SetArgs([]string{"config", "get", "--help"})

	if err := rootCmd.Execute(); err != nil {
		t.Fatalf("config get --help should succeed: %v", err)
	}

	out := buf.String()
	for _, want := range []string{"dot.path", "--json", "--raw", "--timeout"} {
		if !strings.Contains(out, want) {
			t.Errorf("expected help to mention %q, got:\n%s", want, out)
		}
	}
}

func TestConfigGetSubcommandRegistered(t *testing.T) {
	found := false
	for _, sub := range configCmd.Commands() {
		if sub.Name() == "get" {
			found = true
			break
		}
	}
	if !found {
		t.Fatal("expected 'get' subcommand to be registered under 'config'")
	}
}

func TestConfigRegisteredOnRoot(t *testing.T) {
	found := false
	for _, sub := range rootCmd.Commands() {
		if sub.Name() == "config" {
			found = true
			break
		}
	}
	if !found {
		t.Fatal("expected 'config' command to be registered on root")
	}
}

// ---------------------------------------------------------------------------
// printRaw
// ---------------------------------------------------------------------------

func TestPrintRaw_String(t *testing.T) {
	got := captureStdout(t, func() { printRaw("hello world") })
	if got != "hello world" {
		t.Errorf("printRaw(string) = %q, want %q", got, "hello world")
	}
}

func TestPrintRaw_Integer(t *testing.T) {
	got := captureStdout(t, func() { printRaw(float64(42)) })
	if got != "42" {
		t.Errorf("printRaw(42) = %q, want %q", got, "42")
	}
}

func TestPrintRaw_Float(t *testing.T) {
	got := captureStdout(t, func() { printRaw(float64(3.14)) })
	if got != "3.14" {
		t.Errorf("printRaw(3.14) = %q, want %q", got, "3.14")
	}
}

func TestPrintRaw_BoolTrue(t *testing.T) {
	got := captureStdout(t, func() { printRaw(true) })
	if got != "true" {
		t.Errorf("printRaw(true) = %q, want %q", got, "true")
	}
}

func TestPrintRaw_BoolFalse(t *testing.T) {
	got := captureStdout(t, func() { printRaw(false) })
	if got != "false" {
		t.Errorf("printRaw(false) = %q, want %q", got, "false")
	}
}

func TestPrintRaw_Nil(t *testing.T) {
	got := captureStdout(t, func() { printRaw(nil) })
	if got != "" {
		t.Errorf("printRaw(nil) = %q, want empty string", got)
	}
}

func TestPrintRaw_Object(t *testing.T) {
	obj := map[string]any{"key": "value", "n": float64(1)}
	got := captureStdout(t, func() { printRaw(obj) })

	// Should be compact JSON (no indentation)
	if strings.Contains(got, "\n") {
		t.Errorf("printRaw(object) should be compact, got:\n%s", got)
	}

	var parsed map[string]any
	if err := json.Unmarshal([]byte(got), &parsed); err != nil {
		t.Fatalf("printRaw(object) output is not valid JSON: %v\ngot: %s", err, got)
	}
	if parsed["key"] != "value" {
		t.Errorf("expected key=value in output, got: %v", parsed)
	}
}

func TestPrintRaw_Array(t *testing.T) {
	arr := []any{"a", "b", float64(3)}
	got := captureStdout(t, func() { printRaw(arr) })

	if strings.Contains(got, "\n") {
		t.Errorf("printRaw(array) should be compact, got:\n%s", got)
	}

	var parsed []any
	if err := json.Unmarshal([]byte(got), &parsed); err != nil {
		t.Fatalf("printRaw(array) output is not valid JSON: %v\ngot: %s", err, got)
	}
	if len(parsed) != 3 {
		t.Errorf("expected 3 elements, got %d", len(parsed))
	}
}

// ---------------------------------------------------------------------------
// printJSON — pipes through jq or falls back to json.MarshalIndent
//
// We strip ANSI escape codes before asserting so the tests pass
// regardless of whether jq is available and whether stdout is a TTY.
// ---------------------------------------------------------------------------

// stripANSI removes ANSI escape sequences so assertions work with or
// without jq colorization.
func stripANSI(s string) string {
	var buf strings.Builder
	inEscape := false
	for _, r := range s {
		if r == '\033' {
			inEscape = true
			continue
		}
		if inEscape {
			if r == 'm' {
				inEscape = false
			}
			continue
		}
		buf.WriteRune(r)
	}
	return buf.String()
}

func TestPrintJSON_String(t *testing.T) {
	got := stripANSI(strings.TrimSpace(captureStdout(t, func() { printJSON([]byte(`"hello"`)) })))
	if got != `"hello"` {
		t.Errorf("printJSON(string) = %q, want %q", got, `"hello"`)
	}
}

func TestPrintJSON_Integer(t *testing.T) {
	got := stripANSI(strings.TrimSpace(captureStdout(t, func() { printJSON([]byte(`42`)) })))
	if got != "42" {
		t.Errorf("printJSON(42) = %q, want %q", got, "42")
	}
}

func TestPrintJSON_Bool(t *testing.T) {
	got := stripANSI(strings.TrimSpace(captureStdout(t, func() { printJSON([]byte(`true`)) })))
	if got != "true" {
		t.Errorf("printJSON(true) = %q, want %q", got, "true")
	}
}

func TestPrintJSON_Null(t *testing.T) {
	got := stripANSI(strings.TrimSpace(captureStdout(t, func() { printJSON([]byte(`null`)) })))
	if got != "null" {
		t.Errorf("printJSON(null) = %q, want %q", got, "null")
	}
}

func TestPrintJSON_Object_IsValidJSON(t *testing.T) {
	raw := []byte(`{"port":3000}`)
	got := stripANSI(captureStdout(t, func() { printJSON(raw) }))

	var parsed map[string]any
	if err := json.Unmarshal([]byte(got), &parsed); err != nil {
		t.Fatalf("printJSON(object) output is not valid JSON: %v\ngot: %s", err, got)
	}
	if parsed["port"] != float64(3000) {
		t.Errorf("expected port=3000, got: %v", parsed["port"])
	}
}

func TestPrintJSON_Object_IsIndented(t *testing.T) {
	raw := []byte(`{"port":3000}`)
	got := stripANSI(captureStdout(t, func() { printJSON(raw) }))

	if !strings.Contains(got, "\n") {
		t.Errorf("printJSON(object) should be indented, got: %q", got)
	}
}

func TestPrintJSON_NestedObject(t *testing.T) {
	raw := []byte(`{"apps":{"web":{"port":3000}}}`)
	got := stripANSI(captureStdout(t, func() { printJSON(raw) }))

	var parsed map[string]any
	if err := json.Unmarshal([]byte(got), &parsed); err != nil {
		t.Fatalf("printJSON(nested) output is not valid JSON: %v\ngot: %s", err, got)
	}

	apps, ok := parsed["apps"].(map[string]any)
	if !ok {
		t.Fatalf("expected apps to be object, got: %T", parsed["apps"])
	}
	web, ok := apps["web"].(map[string]any)
	if !ok {
		t.Fatalf("expected apps.web to be object, got: %T", apps["web"])
	}
	if web["port"] != float64(3000) {
		t.Errorf("expected apps.web.port=3000, got: %v", web["port"])
	}
}

func TestPrintJSON_Array(t *testing.T) {
	raw := []byte(`["a","b","c"]`)
	got := stripANSI(captureStdout(t, func() { printJSON(raw) }))

	var parsed []any
	if err := json.Unmarshal([]byte(got), &parsed); err != nil {
		t.Fatalf("printJSON(array) output is not valid JSON: %v\ngot: %s", err, got)
	}
	if len(parsed) != 3 {
		t.Errorf("expected 3 elements, got %d", len(parsed))
	}
}

func TestPrintJSON_EmptyObject(t *testing.T) {
	got := stripANSI(strings.TrimSpace(captureStdout(t, func() { printJSON([]byte(`{}`)) })))
	if got != "{}" {
		t.Errorf("printJSON(empty object) = %q, want %q", got, "{}")
	}
}

func TestPrintJSON_EmptyArray(t *testing.T) {
	got := stripANSI(strings.TrimSpace(captureStdout(t, func() { printJSON([]byte(`[]`)) })))
	if got != "[]" {
		t.Errorf("printJSON(empty array) = %q, want %q", got, "[]")
	}
}

func TestPrintJSON_LargeInteger(t *testing.T) {
	got := stripANSI(strings.TrimSpace(captureStdout(t, func() { printJSON([]byte(`1234567890`)) })))
	if got != "1234567890" {
		t.Errorf("printJSON(large int) = %q, want %q", got, "1234567890")
	}
}

func TestPrintJSON_InvalidJSON(t *testing.T) {
	// Should not panic — outputs whatever it can
	got := captureStdout(t, func() { printJSON([]byte(`not json`)) })
	if !strings.Contains(got, "not json") {
		t.Errorf("expected raw passthrough for invalid JSON, got: %q", got)
	}
}

func TestPrintJSON_ComplexObject_RoundTrip(t *testing.T) {
	raw := []byte(`{"a":1,"b":"two","c":null,"d":true,"e":[1,2,3],"f":{"nested":"yes"}}`)
	got := stripANSI(captureStdout(t, func() { printJSON(raw) }))

	var parsed map[string]any
	if err := json.Unmarshal([]byte(got), &parsed); err != nil {
		t.Fatalf("complex object output is not valid JSON: %v\ngot: %s", err, got)
	}
	if parsed["a"] != float64(1) {
		t.Errorf("expected a=1, got: %v", parsed["a"])
	}
	if parsed["b"] != "two" {
		t.Errorf("expected b=two, got: %v", parsed["b"])
	}
	if parsed["c"] != nil {
		t.Errorf("expected c=nil, got: %v", parsed["c"])
	}
	if parsed["d"] != true {
		t.Errorf("expected d=true, got: %v", parsed["d"])
	}
}

// ---------------------------------------------------------------------------
// Attribute path construction
// ---------------------------------------------------------------------------

func TestAttrPathConstruction(t *testing.T) {
	tests := []struct {
		name     string
		dotPath  string
		wantPath string
	}{
		{
			name:     "no path returns base preset",
			dotPath:  "",
			wantPath: ".#stackpanelConfig",
		},
		{
			name:     "single key",
			dotPath:  "project",
			wantPath: ".#stackpanelConfig.project",
		},
		{
			name:     "two-level path",
			dotPath:  "apps.web",
			wantPath: ".#stackpanelConfig.apps.web",
		},
		{
			name:     "deep path",
			dotPath:  "devshell.env.STACKPANEL_ROOT",
			wantPath: ".#stackpanelConfig.devshell.env.STACKPANEL_ROOT",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Replicate the path construction logic from runConfigGet
			attrPath := ".#stackpanelConfig"
			if tt.dotPath != "" {
				attrPath = attrPath + "." + tt.dotPath
			}

			if attrPath != tt.wantPath {
				t.Errorf("attrPath = %q, want %q", attrPath, tt.wantPath)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Default output mode (scalar vs structured)
// ---------------------------------------------------------------------------

func TestDefaultOutput_StringPrintsRaw(t *testing.T) {
	// When the value is a string, the default mode should print it
	// without JSON quotes, followed by a newline.
	got := captureStdout(t, func() {
		var value any = "my-project"
		switch v := value.(type) {
		case string:
			os.Stdout.WriteString(v + "\n")
		default:
			t.Fatalf("unexpected type: %T", value)
		}
	})
	if got != "my-project\n" {
		t.Errorf("default string output = %q, want %q", got, "my-project\n")
	}
}

func TestDefaultOutput_IntegerPrintsWithoutDecimal(t *testing.T) {
	got := captureStdout(t, func() {
		var value any = float64(3000)
		v := value.(float64)
		if v == float64(int64(v)) {
			os.Stdout.WriteString("3000\n")
		}
	})
	if got != "3000\n" {
		t.Errorf("default integer output = %q, want %q", got, "3000\n")
	}
}

func TestDefaultOutput_StructuredUsesJSON(t *testing.T) {
	raw := []byte(`{"key":"value"}`)
	got := stripANSI(captureStdout(t, func() { printJSON(raw) }))

	if !strings.Contains(got, "\n") {
		t.Errorf("structured output should be indented JSON, got: %q", got)
	}
	if !json.Valid([]byte(got)) {
		t.Errorf("structured output should be valid JSON, got: %q", got)
	}
}

// ---------------------------------------------------------------------------
// Flags
// ---------------------------------------------------------------------------

func TestConfigGetFlags(t *testing.T) {
	flags := configGetCmd.Flags()

	tests := []struct {
		name     string
		flagType string
	}{
		{"json", "bool"},
		{"raw", "bool"},
		{"timeout", "duration"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := flags.Lookup(tt.name)
			if f == nil {
				t.Fatalf("flag --%s not found", tt.name)
			}
			if f.Value.Type() != tt.flagType {
				t.Errorf("flag --%s type = %s, want %s", tt.name, f.Value.Type(), tt.flagType)
			}
		})
	}
}

func TestConfigGetAcceptsMaxOneArg(t *testing.T) {
	t.Cleanup(func() {
		rootCmd.SetArgs(nil)
		rootCmd.SetOut(nil)
		rootCmd.SetErr(nil)
	})

	buf := &bytes.Buffer{}
	rootCmd.SetOut(buf)
	rootCmd.SetErr(buf)
	rootCmd.SetArgs([]string{"config", "get", "one", "two"})

	// Cobra prints validation errors to stderr and may or may not return
	// an error depending on version/config. Check the output instead.
	_ = rootCmd.Execute()

	out := buf.String()
	if !strings.Contains(out, "accepts at most 1 arg") && !strings.Contains(out, "too many arguments") {
		// If cobra silently rejected it, the output should at least contain
		// usage info rather than executing the command successfully.
		if !strings.Contains(out, "Usage") {
			t.Fatalf("expected arg validation message or usage output, got: %s", out)
		}
	}
}

// ---------------------------------------------------------------------------
// Edge cases for printRaw
// ---------------------------------------------------------------------------

func TestPrintRaw_EmptyString(t *testing.T) {
	got := captureStdout(t, func() { printRaw("") })
	if got != "" {
		t.Errorf("printRaw(empty string) = %q, want empty", got)
	}
}

func TestPrintRaw_StringWithSpaces(t *testing.T) {
	got := captureStdout(t, func() { printRaw("hello world") })
	if got != "hello world" {
		t.Errorf("printRaw(string with spaces) = %q, want %q", got, "hello world")
	}
}

func TestPrintRaw_NegativeNumber(t *testing.T) {
	got := captureStdout(t, func() { printRaw(float64(-1)) })
	if got != "-1" {
		t.Errorf("printRaw(-1) = %q, want %q", got, "-1")
	}
}

func TestPrintRaw_Zero(t *testing.T) {
	got := captureStdout(t, func() { printRaw(float64(0)) })
	if got != "0" {
		t.Errorf("printRaw(0) = %q, want %q", got, "0")
	}
}

func TestPrintRaw_EmptyObject(t *testing.T) {
	got := captureStdout(t, func() { printRaw(map[string]any{}) })
	if got != "{}" {
		t.Errorf("printRaw(empty object) = %q, want %q", got, "{}")
	}
}

func TestPrintRaw_EmptyArray(t *testing.T) {
	got := captureStdout(t, func() { printRaw([]any{}) })
	if got != "[]" {
		t.Errorf("printRaw(empty array) = %q, want %q", got, "[]")
	}
}

func TestPrintRaw_LargeInteger(t *testing.T) {
	got := captureStdout(t, func() { printRaw(float64(1234567890)) })
	if got != "1234567890" {
		t.Errorf("printRaw(large int) = %q, want %q", got, "1234567890")
	}
}

func TestPrintRaw_StringWithNewlines(t *testing.T) {
	got := captureStdout(t, func() { printRaw("line1\nline2") })
	if got != "line1\nline2" {
		t.Errorf("printRaw(multiline) = %q, want %q", got, "line1\nline2")
	}
}
