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
