// logs.go surfaces shell-entry logs captured during devshell initialisation.
//
// The shell hook pipes its output to a log file so it doesn't clutter the
// terminal on every shell entry. This command provides a way to inspect those
// logs when debugging shell hook issues.
package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/envvars"
	"github.com/spf13/cobra"
)

var logsCmd = &cobra.Command{
	Use:   "logs",
	Short: "View stackpanel logs",
}

var logsShellCmd = &cobra.Command{
	Use:   "shell",
	Short: "Show shell entry logs",
	RunE:  runShellLogs,
}

func init() {
	logsCmd.AddCommand(logsShellCmd)
	rootCmd.AddCommand(logsCmd)
}

// runShellLogs reads the shell entry log. It tries STACKPANEL_SHELL_LOG first
// (set directly by the shell hook), then falls back to constructing the path
// from STACKPANEL_STATE_DIR. Both vars are only available inside the devshell.
func runShellLogs(cmd *cobra.Command, args []string) error {
	logPath := envvars.StackpanelShellLog.Get()
	if logPath == "" {
		stateDir := envvars.StackpanelStateDir.Get()
		if stateDir != "" {
			logPath = filepath.Join(stateDir, "shell.log")
		}
	}

	if logPath == "" {
		return fmt.Errorf("STACKPANEL_SHELL_LOG not set and STACKPANEL_STATE_DIR unavailable")
	}

	content, err := os.ReadFile(logPath)
	if err != nil {
		return fmt.Errorf("failed to read shell log: %w", err)
	}

	if strings.TrimSpace(string(content)) == "" {
		fmt.Println("No shell entry logs captured yet.")
		return nil
	}

	fmt.Print(string(content))
	return nil
}
