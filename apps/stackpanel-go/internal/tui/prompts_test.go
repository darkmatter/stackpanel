package tui

import (
	"bytes"
	"strings"
	"testing"
)

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
				t.Errorf("got %v, want %v (input=%q default=%v)", got, tc.want, tc.input, tc.defaultYes)
			}
		})
	}
}
