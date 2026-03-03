# Stackpanel CLI Package

Nix derivation for the unified Stackpanel CLI and agent.

## Overview

Builds the Go binary from `apps/stackpanel-go` using `buildGoApplication` with gomod2nix for reproducible builds. The resulting `stackpanel` binary provides the CLI, TUI, and local agent server.

## Usage

The package is automatically added to the devshell when `stackpanel.cli.enable = true`.

```bash
stackpanel          # Interactive TUI
stackpanel agent    # Start local agent server
stackpanel hook     # Shell hook (called by Nix on shell entry)
stackpanel motd     # Display message of the day
stackpanel caddy    # Caddy management subcommands
```
