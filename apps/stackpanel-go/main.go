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
