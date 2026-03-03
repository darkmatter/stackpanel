# Stackpanel Nix Module System

This directory contains the main Stackpanel Nix module system - a comprehensive framework for managing development environments with Nix.

## Overview

Stackpanel provides:
- **Reproducible dev environments** via devenv/Nix
- **Multi-app monorepo support** with automatic port assignment
- **Secrets management** with SOPS/vals integration
- **IDE integration** with VS Code workspace generation
- **Service orchestration** for PostgreSQL, Redis, MinIO, etc.
- **TLS everywhere** via Step CA certificate management

## Directory Structure

Options are co-located with their feature implementations. Each directory owns its options, logic, and helpers.

```
stackpanel/
├── default.nix      # Main entry point - imports all feature modules
├── core/            # Core options + boot logic (enable, dirs, root, CLI)
├── apps/            # App configuration, ports, and CI generation
├── network/         # Ports, DNS, Step CA certificates
├── services/        # Service orchestration (postgres, redis, minio, caddy, AWS)
├── secrets/         # Master key-based secrets management
├── variables/       # Workspace variables with keygroup organization
├── ide/             # IDE integration (VS Code, Zed)
├── tui/             # Terminal theming (Starship prompt)
├── deployment/      # Deployment providers (Fly.io, Cloudflare)
├── containers/      # OCI container image building
├── docker/          # Container tooling (skopeo)
├── infra/           # Alchemy-based infrastructure modules
├── sst/             # SST AWS infrastructure provisioning
├── docs/            # Documentation generation
├── devshell/        # Shell configuration (packages, hooks, scripts, files)
├── plugins/         # Auto-discovered feature plugins (bun, go, turbo, etc.)
├── db/              # Proto-derived schema system
├── lib/             # Shared pure library functions
└── packages/        # Nix package definitions (stackpanel-cli)
```

## Key Concepts

### Options System

All configuration is defined through NixOS module options under `stackpanel.*`:

```nix
{
  stackpanel = {
    name = "my-project";
    apps = {
      web = { port = 3000; };
      api = { port = 4000; };
    };
    services.postgres.enable = true;
    services.redis.enable = true;
  };
}
```

### Service Orchestration (`services/`)

Configures development services (PostgreSQL, Redis, MinIO, Caddy):

- Automatic port assignment based on project name
- TLS certificates via Step CA
- Caddy reverse proxy with automatic vhosts

### Secrets Management (`secrets/`)

Master key-based secrets with keygroup organization:

- Per-environment encryption (dev, staging, prod)
- Local key auto-generation for immediate use
- External key storage via AWS SSM, Vault, etc.

## Usage

Import this module in your devenv.nix:

```nix
{ inputs, ... }: {
  imports = [
    inputs.stackpanel.devenvModules.default
  ];

  stackpanel.name = "my-project";
}
```

Or use the flake template:

```bash
nix flake init -t github:coopermaruyama/stackpanel
```

## Module Documentation

Each directory has its own README with detailed documentation:

| Module | Description |
|--------|-------------|
| [core/](core/README.md) | Core options and boot logic |
| [apps/](apps/README.md) | App configuration |
| [network/](network/README.md) | Ports, DNS, Step CA |
| [services/](services/README.md) | Service orchestration |
| [secrets/](secrets/README.md) | Secrets management |
| [variables/](variables/README.md) | Workspace variables |
| [ide/](ide/README.md) | IDE integration |
| [tui/](tui/README.md) | Terminal theming |
| [deployment/](deployment/README.md) | Deployment providers |
| [containers/](containers/README.md) | Container building |
| [plugins/](plugins/README.md) | Auto-discovered plugins |
| [lib/](lib/README.md) | Library functions |
| [db/](db/README.md) | Schema system |
