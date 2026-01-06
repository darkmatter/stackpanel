package cmd

import (
	"bytes"
	"strings"
	"testing"
)

// TestRootCommandHelp ensures the root command wiring stays valid.
func TestRootCommandHelp(t *testing.T) {
	t.Cleanup(func() {
		rootCmd.SetArgs(nil)
		rootCmd.SetOut(nil)
		rootCmd.SetErr(nil)
	})

	buf := &bytes.Buffer{}
	rootCmd.SetOut(buf)
	rootCmd.SetErr(buf)
	rootCmd.SetArgs([]string{"--help"})

	if err := rootCmd.Execute(); err != nil {
		t.Fatalf("root command help should succeed: %v", err)
	}

	if !strings.Contains(buf.String(), "Stackpanel") {
		t.Fatalf("expected help output to mention Stackpanel, got: %s", buf.String())
	}
}
