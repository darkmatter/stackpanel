// init.go keeps `stackpanel init` as a hidden, deprecated alias of
// `stack setup`. With a unified reconciler there is no difference between
// initializing a project and reconciling one from empty, so the two commands
// share one body. The alias is retained for one release.
package cmd

import (
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/spf13/cobra"
)

var initOpts setupFlags

var initCmd = &cobra.Command{
	Use:        "init",
	Short:      "Deprecated: use 'stack setup'",
	Long:       "Deprecated alias of 'stack setup'. It accepts the same flags and will be removed in a future release.",
	Hidden:     true,
	Deprecated: "use 'stack setup' instead",
	RunE: func(cmd *cobra.Command, args []string) error {
		output.Warning("'stackpanel init' is deprecated; use 'stack setup'")
		return runSetupWith(cmd, initOpts)
	},
}

func init() {
	f := initCmd.Flags()
	f.BoolVar(&initOpts.force, "force", false, "Overwrite existing files")
	f.BoolVar(
		&initOpts.dryRun,
		"dry-run",
		false,
		"Show what would be done without writing files",
	)
	f.StringVar(
		&initOpts.flake,
		"flake",
		"",
		"Stackpanel flake reference (default: github:darkmatter/stackpanel)",
	)
	f.StringVar(&initOpts.template, "template", "default", "Template name to initialize")
	f.BoolVar(
		&initOpts.tmp,
		"tmp",
		false,
		"Create the project in a temporary git repository and print its path",
	)
	f.BoolVar(
		&initOpts.nonInteractive,
		"non-interactive",
		false,
		"Skip all prompts and apply every pending step",
	)
	f.StringSliceVar(
		&initOpts.with,
		"with",
		nil,
		"Enable an addon by id without prompting (repeatable)",
	)
	f.StringSliceVar(
		&initOpts.without,
		"without",
		nil,
		"Decline an addon by id without prompting (repeatable)",
	)
	f.StringSliceVar(
		&initOpts.addonValues,
		"addon",
		nil,
		"Answer an addon explicitly as id=value",
	)
	rootCmd.AddCommand(initCmd)
}
