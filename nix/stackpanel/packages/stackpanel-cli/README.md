# Stack CLI Package

Nix derivation for the unified Stack CLI and agent.

## Overview

Builds the Go binary from `apps/stack-go` using `buildGoApplication` with gomod2nix for reproducible builds. The resulting `stack` binary provides the CLI, TUI, and local agent server.

## Usage

The package is automatically added to the devshell when `stack.cli.enable = true`.

```bash
stack          # Interactive TUI
stack agent    # Start local agent server
stack hook     # Shell hook (called by Nix on shell entry)
stack motd     # Display message of the day
stack caddy    # Caddy management subcommands
```
