package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	nixeval "github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	svc "github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
	"github.com/spf13/cobra"
)

// portsConfig is a minimal struct for the fields we need from the evaluated config
type portsConfig struct {
	ProjectRoot string `json:"projectRoot"`
	ProjectName string `json:"projectName"`
}

var ports = &cobra.Command{
	Use:   "port",
	Short: "Deterministic stable port assignment for services",
	Long: `Compute a port using the Stackpanel conventional port assignment algorithm.

Stackpanel uses a simple deterministic algorithm to assign stable ports to development services.
The convention affords a couple of conveniences:
	- Simple to compute from any language
	- Ports can be known ahead of time
	- Avoids port conflicts between projects
	- Removes the need to pass ports around in config files or environment variables

The algorithm to compute a port is as follows:
  1. Define a range computation as follow:

		range = int(md5("owner/repo")) % 7000
		min = f - (f % 100)
		project_port_min = min + 3000

	2. This gives us a base port like 5500 or 3200 - the base port is always rounded down to the nearest 100, and the last two digits are owned by this project, giving us 100 ports to assign to services.

	3. Perform the same computation over the project's range to get the service port:

		service_offset = int(md5("owner/repo/service_name")) % 100
		service_port = floor(project_port_min + service_offset)

  The numeric value of the hash is determined by taking the first 4 hex characters of the md5 hash and converting them to an integer (base16).

To keep it simple, there is no conflict resolution mechanism - if you run into this just change the
service name or add a prefix to it.

`,
	Run: func(cmd *cobra.Command, args []string) {
		service, _ := cmd.Flags().GetString("service")
		repo, _ := cmd.Flags().GetString("repo")
		var config portsConfig
		ctx := context.Background()
		b, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
			Expression: nixeval.StackpanelConfigPreset,
		})
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to evaluate config: %v\n", err)
			return
		}
		if err := json.Unmarshal(b, &config); err != nil {
			fmt.Fprintf(os.Stderr, "failed to unmarshal config: %v\n", err)
			return
		}
		rk := config.ProjectRoot
		if repo != "" {
			rk = repo
		}
		k := config.ProjectName
		if service != "" {
			k = service
		}
		port := svc.StablePort(rk, k)
		os.Stdout.WriteString(fmt.Sprintf("%d\n", port))
	},
}

func init() {
	ports.Flags().String("repo", "", "git repo formatterd as `owner/repo` to use for port computation")
	ports.Flags().String("service", "", "service name to use for port computation")
	rootCmd.AddCommand(ports)
}
