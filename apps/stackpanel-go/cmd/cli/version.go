// Package cmd implements the Cobra command tree for the stackpanel CLI.
package cmd

import (
"fmt"

"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
Use:   "version",
Short: "Show version information",
Long:  `Display the version and build information for Stackpanel.`,
Run: func(cmd *cobra.Command, args []string) {
fmt.Printf("Stackpanel %s\n", Version)
if BuildDate != "unknown" {
fmt.Printf("Built: %s\n", BuildDate)
}
},
}

func init() {
rootCmd.AddCommand(versionCmd)
}
