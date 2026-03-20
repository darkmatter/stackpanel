# StackPanel Nix Packages

This directory contains Nix package definitions for StackPanel's core binaries and libraries. These packages are exposed through the StackPanel flake and can be built or installed using Nix.

## Packages

### stack-cli

The main command-line interface for StackPanel. Built from the Go source in `apps/cli/`.

**Binary:** `stack`

**Features:**
- Manage local development services
- Configure Caddy reverse proxy
- Handle SSL certificates
- Control the StackPanel agent

**Build:**
```bash
nix build .#stack-cli
```

### stack-agent

A background service that enables web UI integration with local development environments. Built from the Go source in `apps/agent/`.

**Binary:** `stack-agent`

**Features:**
- Bridge between web interface and local services
- Real-time monitoring and control
- WebSocket communication

**Build:**
```bash
nix build .#stack-agent
```

### stack-go

A source derivation containing the shared Go module used by both the CLI and agent. This is **not** a compiled binary - it provides source files for Go module replace directives during builds.

**Source:** `packages/stack-go/`

**Contains:**
- Shared types and interfaces
- State management utilities
- Nix evaluation helpers

## Usage

These packages are typically consumed through the StackPanel devenv configuration or flake outputs. You can also build them directly:

```bash
# Build all packages
nix build .#stack-cli .#stack-agent

# Enter a shell with packages available
nix develop

# Run directly
nix run .#stack-cli -- --help
```

## Adding New Packages

1. Create a new directory: `nix/stack/packages/<package-name>/`
2. Add a `default.nix` with the package definition
3. Follow the documentation header format used in existing packages
4. Export the package in the appropriate flake output
