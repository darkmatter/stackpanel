package cmd

import (
	"bytes"
	"strings"
	"testing"
)

func TestFormatVersion(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		cmd     string
		version string
		commit  string
		date    string
		want    []string
		hide    []string
	}{
		{
			name:    "version only",
			cmd:     "stack",
			version: "0.1.0",
			commit:  "unknown",
			date:    "unknown",
			want:    []string{"stack version 0.1.0\n"},
			hide:    []string{"commit:", "built:"},
		},
		{
			name:    "commit and date",
			cmd:     "stack",
			version: "0.1.0",
			commit:  "abc123def",
			date:    "2026-09-08T05:23:00Z",
			want: []string{
				"stack version 0.1.0\n",
				"commit: abc123def\n",
				"built:  2026-09-08T05:23:00Z\n",
			},
		},
		{
			name:    "empty meta omitted",
			cmd:     "stack",
			version: "dev",
			commit:  "",
			date:    "",
			want:    []string{"stack version dev\n"},
			hide:    []string{"commit:", "built:"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got := formatVersion(tt.cmd, tt.version, tt.commit, tt.date)
			for _, want := range tt.want {
				if !strings.Contains(got, want) {
					t.Errorf("formatVersion() = %q, want to contain %q", got, want)
				}
			}
			for _, hide := range tt.hide {
				if strings.Contains(got, hide) {
					t.Errorf("formatVersion() = %q, should omit %q", got, hide)
				}
			}
		})
	}
}

func resetRootFlags() {
	rootCmd.SetArgs(nil)
	rootCmd.SetOut(nil)
	rootCmd.SetErr(nil)
	for _, name := range []string{"version", "help"} {
		if f := rootCmd.Flags().Lookup(name); f != nil {
			_ = f.Value.Set("false")
			f.Changed = false
		}
	}
}

func TestVersionFlagIncludesBuildMetadata(t *testing.T) {
	prevVersion, prevCommit, prevDate := Version, GitCommit, BuildDate
	t.Cleanup(func() {
		Version, GitCommit, BuildDate = prevVersion, prevCommit, prevDate
		rootCmd.Version = Version
		rootCmd.SetVersionTemplate(versionCobraTemplate(GitCommit, BuildDate))
		resetRootFlags()
	})

	Version = "0.1.0"
	GitCommit = "deadbeefcafebabe"
	BuildDate = "2026-09-08T05:23:00Z"
	rootCmd.Version = Version
	rootCmd.SetVersionTemplate(versionCobraTemplate(GitCommit, BuildDate))
	resetRootFlags()

	buf := &bytes.Buffer{}
	rootCmd.SetOut(buf)
	rootCmd.SetErr(buf)
	rootCmd.SetArgs([]string{"--version"})

	if err := rootCmd.Execute(); err != nil {
		t.Fatalf("stack --version should succeed: %v", err)
	}

	got := buf.String()
	for _, want := range []string{
		"stack version 0.1.0",
		"commit: deadbeefcafebabe",
		"built:  2026-09-08T05:23:00Z",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("--version output %q, want to contain %q", got, want)
		}
	}
}
