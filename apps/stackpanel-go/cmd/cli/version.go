// Package cmd implements the Cobra command tree for the stackpanel CLI.
package cmd

import (
	"fmt"
	"io"
	"runtime/debug"
	"strings"

	"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Show version information",
	Long:  `Display the version and build information for Stackpanel.`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Fprint(cmd.OutOrStdout(), formatVersion(rootCmd.Name(), Version, GitCommit, BuildDate))
	},
}

func init() {
	applyEmbeddedBuildInfo()
	rootCmd.SetVersionTemplate(versionCobraTemplate(GitCommit, BuildDate))
	rootCmd.AddCommand(versionCmd)
}

func isSetBuildMeta(s string) bool {
	return s != "" && s != "unknown"
}

// formatVersion is the human-readable version block used by `stack version`
// and (via versionCobraTemplate) by `stack --version`.
func formatVersion(name, version, commit, date string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s version %s\n", name, version)
	writeBuildMeta(&b, commit, date)
	return b.String()
}

func versionCobraTemplate(commit, date string) string {
	var b strings.Builder
	// Keep cobra v1.9's default first line, then append build metadata.
	b.WriteString(`{{with .DisplayName}}{{printf "%s " .}}{{end}}{{printf "version %s" .Version}}`)
	b.WriteByte('\n')
	writeBuildMeta(&b, commit, date)
	return b.String()
}

func writeBuildMeta(w io.StringWriter, commit, date string) {
	if isSetBuildMeta(commit) {
		_, _ = w.WriteString(fmt.Sprintf("commit: %s\n", commit))
	}
	if isSetBuildMeta(date) {
		_, _ = w.WriteString(fmt.Sprintf("built:  %s\n", date))
	}
}

// applyEmbeddedBuildInfo fills GitCommit and BuildDate from Go's embedded
// VCS settings when they were not injected via -ldflags (local go build).
func applyEmbeddedBuildInfo() {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return
	}
	vcsRevision := ""
	modified := false
	for _, s := range info.Settings {
		switch s.Key {
		case "vcs.revision":
			vcsRevision = s.Value
		case "vcs.time":
			if !isSetBuildMeta(BuildDate) {
				BuildDate = s.Value
			}
		case "vcs.modified":
			modified = s.Value == "true"
		}
	}
	if isSetBuildMeta(GitCommit) || vcsRevision == "" {
		return
	}
	GitCommit = vcsRevision
	if modified {
		GitCommit += "-dirty"
	}
}
