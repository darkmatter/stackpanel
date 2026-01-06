package executor

import (
	"strings"
	"testing"
)

func TestExecutorRun(t *testing.T) {
	exec, err := NewWithoutDevshell(t.TempDir(), nil)
	if err != nil {
		t.Fatalf("executor.NewWithoutDevshell returned error: %v", err)
	}

	res, err := exec.Run("echo", "hello")
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}
	if res.ExitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", res.ExitCode)
	}
	if strings.TrimSpace(res.Stdout) != "hello" {
		t.Fatalf("unexpected stdout: %q", res.Stdout)
	}
}

func TestParseDevEnvOutput(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected map[string]string
	}{
		{
			name: "simple exports",
			input: `export FOO="bar"
export BAZ="qux"`,
			expected: map[string]string{
				"FOO": "bar",
				"BAZ": "qux",
			},
		},
		{
			name: "single quotes",
			input: `export FOO='bar'
export BAZ='qux'`,
			expected: map[string]string{
				"FOO": "bar",
				"BAZ": "qux",
			},
		},
		{
			name:  "path with colons",
			input: `export PATH="/nix/store/abc:/nix/store/def:/usr/bin"`,
			expected: map[string]string{
				"PATH": "/nix/store/abc:/nix/store/def:/usr/bin",
			},
		},
		{
			name: "skips filtered variables",
			input: `export FOO="bar"
export PWD="/some/path"
export HOME="/home/user"
export BAZ="qux"`,
			expected: map[string]string{
				"FOO": "bar",
				"BAZ": "qux",
			},
		},
		{
			name: "skips comments and empty lines",
			input: `# This is a comment
export FOO="bar"

# Another comment
export BAZ="qux"
`,
			expected: map[string]string{
				"FOO": "bar",
				"BAZ": "qux",
			},
		},
		{
			name:  "handles values with equals sign",
			input: `export FOO="bar=baz"`,
			expected: map[string]string{
				"FOO": "bar=baz",
			},
		},
		{
			name:     "empty input",
			input:    "",
			expected: map[string]string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := parseDevEnvOutput(tt.input)

			// Convert result slice to map for easier comparison
			resultMap := make(map[string]string)
			for _, env := range result {
				parts := strings.SplitN(env, "=", 2)
				if len(parts) == 2 {
					resultMap[parts[0]] = parts[1]
				}
			}

			if len(resultMap) != len(tt.expected) {
				t.Errorf("expected %d env vars, got %d", len(tt.expected), len(resultMap))
				t.Errorf("expected: %v", tt.expected)
				t.Errorf("got: %v", resultMap)
				return
			}

			for key, expectedVal := range tt.expected {
				if gotVal, ok := resultMap[key]; !ok {
					t.Errorf("missing expected key %q", key)
				} else if gotVal != expectedVal {
					t.Errorf("key %q: expected %q, got %q", key, expectedVal, gotVal)
				}
			}
		})
	}
}

func TestMergeEnv(t *testing.T) {
	tests := []struct {
		name      string
		base      []string
		overrides []string
		expected  map[string]string
	}{
		{
			name:      "basic merge",
			base:      []string{"FOO=bar", "BAZ=qux"},
			overrides: []string{"NEW=value"},
			expected: map[string]string{
				"FOO": "bar",
				"BAZ": "qux",
				"NEW": "value",
			},
		},
		{
			name:      "override existing",
			base:      []string{"FOO=bar", "BAZ=qux"},
			overrides: []string{"FOO=newbar"},
			expected: map[string]string{
				"FOO": "newbar",
				"BAZ": "qux",
			},
		},
		{
			name:      "empty base",
			base:      []string{},
			overrides: []string{"FOO=bar"},
			expected: map[string]string{
				"FOO": "bar",
			},
		},
		{
			name:      "empty overrides",
			base:      []string{"FOO=bar"},
			overrides: []string{},
			expected: map[string]string{
				"FOO": "bar",
			},
		},
		{
			name:      "both empty",
			base:      []string{},
			overrides: []string{},
			expected:  map[string]string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := mergeEnv(tt.base, tt.overrides)

			// Convert result slice to map for easier comparison
			resultMap := make(map[string]string)
			for _, env := range result {
				parts := strings.SplitN(env, "=", 2)
				if len(parts) == 2 {
					resultMap[parts[0]] = parts[1]
				}
			}

			if len(resultMap) != len(tt.expected) {
				t.Errorf("expected %d env vars, got %d", len(tt.expected), len(resultMap))
				return
			}

			for key, expectedVal := range tt.expected {
				if gotVal, ok := resultMap[key]; !ok {
					t.Errorf("missing expected key %q", key)
				} else if gotVal != expectedVal {
					t.Errorf("key %q: expected %q, got %q", key, expectedVal, gotVal)
				}
			}
		})
	}
}

func TestShouldSkipEnvVar(t *testing.T) {
	skipped := []string{"PWD", "OLDPWD", "SHLVL", "_", "TERM", "SHELL", "HOME", "USER", "LOGNAME", "TMPDIR", "XDG_RUNTIME_DIR"}
	allowed := []string{"PATH", "FOO", "NIX_PATH", "GOPATH", "CARGO_HOME"}

	for _, key := range skipped {
		if !shouldSkipEnvVar(key) {
			t.Errorf("expected %q to be skipped", key)
		}
	}

	for _, key := range allowed {
		if shouldSkipEnvVar(key) {
			t.Errorf("expected %q to NOT be skipped", key)
		}
	}
}

func TestExecutorDevshellDetection(t *testing.T) {
	exec, err := NewWithoutDevshell(t.TempDir(), nil)
	if err != nil {
		t.Fatalf("NewWithoutDevshell returned error: %v", err)
	}

	// When created without devshell loading, HasDevshellEnv should be false
	// (unless we're actually running in a devshell)
	if exec.InDevshell() && !exec.HasDevshellEnv() {
		t.Error("InDevshell is true but HasDevshellEnv is false - inconsistent state")
	}
}
