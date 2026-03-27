// stackpanel-go is the CLI and localhost agent for managing Nix-based dev environments.
// It operates in two modes: as an interactive CLI (Cobra + Bubble Tea TUI) for direct
// service management, and as an HTTP agent server that bridges the Studio web UI to
// the local Nix environment.
package main

import (
	"os"

	cmd "github.com/darkmatter/stackpanel/stackpanel-go/cmd/cli"
)

func main() {
	if err := cmd.Execute(); err != nil {
		os.Exit(1)
	}
}
