package tui

import (
	"bytes"
	"strings"
	"testing"
)

func TestStdinSelect(t *testing.T) {
	opts := []string{"none", "cloudflare", "fly"}
	cases := []struct {
		name  string
		input string
		def   string
		want  string
	}{
		{"empty-uses-default", "\n", "cloudflare", "cloudflare"},
		{"by-index", "3\n", "none", "fly"},
		{"by-value", "cloudflare\n", "none", "cloudflare"},
		{"out-of-range-falls-back", "9\n", "none", "none"},
		{"garbage-falls-back", "xyz\n", "fly", "fly"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			got, err := StdinSelect(
				strings.NewReader(tc.input),
				&out,
				"target?",
				opts,
				tc.def,
			)
			if err != nil {
				t.Fatalf("StdinSelect: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q (input=%q)", got, tc.want, tc.input)
			}
		})
	}
}

func TestStdinMultiSelect(t *testing.T) {
	opts := []string{"lint", "test", "format"}
	defaults := []string{"lint"}

	var out bytes.Buffer
	got, err := StdinMultiSelect(strings.NewReader("1,3\n"), &out, "hooks?", opts, defaults)
	if err != nil {
		t.Fatalf("StdinMultiSelect: %v", err)
	}
	if len(got) != 2 || got[0] != "lint" || got[1] != "format" {
		t.Errorf("got %v, want [lint format]", got)
	}

	// Empty input returns the defaults.
	out.Reset()
	got, err = StdinMultiSelect(strings.NewReader("\n"), &out, "hooks?", opts, defaults)
	if err != nil {
		t.Fatalf("StdinMultiSelect (default): %v", err)
	}
	if len(got) != 1 || got[0] != "lint" {
		t.Errorf("empty input should return defaults, got %v", got)
	}
}

func TestStdinConfirm(t *testing.T) {
	cases := []struct {
		name       string
		input      string
		defaultYes bool
		want       bool
	}{
		{"empty-defaults-yes", "\n", true, true},
		{"empty-defaults-no", "\n", false, false},
		{"explicit-y", "y\n", false, true},
		{"explicit-yes", "yes\n", false, true},
		{"explicit-n", "n\n", true, false},
		{"anything-else-is-no", "maybe\n", true, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			got, err := StdinConfirm(strings.NewReader(tc.input), &out, "go?", tc.defaultYes)
			if err != nil {
				t.Fatalf("StdinConfirm: %v", err)
			}
			if got != tc.want {
				t.Errorf(
					"got %v, want %v (input=%q default=%v)",
					got,
					tc.want,
					tc.input,
					tc.defaultYes,
				)
			}
		})
	}
}
