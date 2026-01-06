package main

import (
	"os"

	cmd "github.com/darkmatter/stackpanel/apps/stackpanel-go/cmd/cli"
)

func main() {
	if err := cmd.Execute(); err != nil {
		os.Exit(1)
	}
}
