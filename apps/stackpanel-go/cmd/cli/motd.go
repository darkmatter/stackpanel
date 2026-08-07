// motd.go provides status data for Prelude probes and Studio.
//
// The human shell banner is Prelude's `motd` binary. This command keeps
// --json / --minimal for machine-readable and one-line status. There is no
// Lip Gloss full MOTD renderer anymore.
package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/spf13/cobra"
)

var (
	motdMinimal bool
	motdJSON    bool
)

var motdCmd = &cobra.Command{
	Use:   "motd",
	Short: "Project status for Prelude / Studio (JSON or minimal)",
	Long: `Emit Stackpanel project status used by Prelude MOTD probes and Studio.

The interactive shell banner is Prelude's ` + "`motd`" + ` binary (on PATH in the
devshell). Use this command for machine-readable status:

Examples:
  stackpanel motd --json       # Full status JSON (agent, services, issues)
  stackpanel motd --minimal    # One-line status
  motd                         # Prelude welcome banner (separate binary)`,
	RunE: runMOTD,
}

func init() {
	motdCmd.Flags().BoolVar(&motdMinimal, "minimal", false, "Show minimal one-line status")
	motdCmd.Flags().BoolVar(&motdJSON, "json", false, "Output status as JSON")
	rootCmd.AddCommand(motdCmd)
}

func runMOTD(cmd *cobra.Command, args []string) error {
	if !motdJSON && !motdMinimal {
		return fmt.Errorf(
			"human MOTD is Prelude's `motd` binary; use --json or --minimal\n" +
				"  stackpanel motd --json\n" +
				"  stackpanel motd --minimal\n" +
				"  motd",
		)
	}

	cfg, err := nixconfig.Load()
	if err != nil {
		cfg = &nixconfig.Config{
			ProjectName: "",
			ProjectRoot: os.Getenv("STACKPANEL_PROJECT_ROOT"),
		}
	}

	if motdMinimal {
		fmt.Fprint(os.Stderr, tui.RenderMinimalMOTD(cfg.ProjectName))
		return nil
	}

	var motdOpts *tui.CollectMOTDDataOpts
	if len(cfg.Healthchecks) > 0 {
		stateDir := cfg.Paths.State
		if stateDir == "" {
			stateDir = ".stack/profile"
		}
		if cfg.ProjectRoot != "" && !filepath.IsAbs(stateDir) {
			stateDir = filepath.Join(cfg.ProjectRoot, stateDir)
		}
		motdOpts = &tui.CollectMOTDDataOpts{
			Healthchecks: cfg.Healthchecks,
			StateDir:     stateDir,
		}
	}

	data := tui.CollectMOTDData(
		cfg.ProjectName,
		cfg.ProjectRoot,
		Version,
		9876,
		motdOpts,
	)

	if len(cfg.MissingFlakeInputs) > 0 {
		for _, fi := range cfg.MissingFlakeInputs {
			data.MissingFlakeInputs = append(data.MissingFlakeInputs, tui.MissingFlakeInput{
				Name:           fi.Name,
				URL:            fi.URL,
				FollowsNixpkgs: fi.FollowsNixpkgs,
				RequiredBy:     fi.RequiredBy,
			})
		}
		data.Issues = tui.CollectIssues(data)
	}

	if cfg.Services != nil {
		for name := range cfg.Services {
			data.Services = append(data.Services, tui.ServiceStatus{
				Name:    name,
				Running: checkDockerServiceStatus(name),
			})
		}
	}

	if len(data.Services) == 0 {
		for _, name := range []string{"postgres", "redis"} {
			data.Services = append(data.Services, tui.ServiceStatus{
				Name:    name,
				Running: checkDockerServiceStatus(name),
			})
		}
	}

	jsonData, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal MOTD data: %w", err)
	}
	fmt.Println(string(jsonData))
	return nil
}

func checkDockerServiceStatus(service string) bool {
	cmd := exec.Command(
		"docker",
		"compose",
		"ps",
		"--format",
		"{{.State}}",
		"--filter",
		fmt.Sprintf("name=%s", service),
	)
	output, err := cmd.Output()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(output)), "running")
}
