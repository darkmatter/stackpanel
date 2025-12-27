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

```
stackpanel/
├── default.nix      # Main entry point - imports core module
├── core/            # Core module system (options + config)
│   ├── options/     # All NixOS module option definitions
│   ├── services/    # Service registry and factory functions
│   └── lib/         # Configuration evaluation for CLI/agent
├── lib/             # Pure library functions
│   └── services/    # Service-specific utilities (postgres, redis, etc.)
├── apps/            # Application configuration and CI generation
├── devshell/        # Development shell configuration
├── ide/             # IDE integration (VS Code)
├── network/         # Step CA and network configuration
├── packages/        # Nix package definitions
├── secrets/         # SOPS secrets management module
├── services/        # Service orchestration
└── tui/             # TUI application module
```

## Key Concepts

### Options System (`core/options/`)

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

### Library Functions (`lib/`)

Pure functions for file generation, path resolution, and service configuration:

```nix
let
  spLib = import ./lib { inherit lib pkgs; };
in
spLib.files.generate {
  path = ".env";
  content = "DATABASE_URL=...";
}
```

### Service Orchestration (`services/`)

Configures development services (PostgreSQL, Redis, MinIO, Caddy):

- Automatic port assignment based on project name
- TLS certificates via Step CA
- Caddy reverse proxy with automatic vhosts

### Secrets Management (`secrets/`)

SOPS-based secrets with per-app configuration:

- Per-environment schemas (dev, staging, prod)
- Automatic codegen for TypeScript/Python/Go
- JSON Schema generation for IDE intellisense

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

## Related Documentation

- [Core Module](core/README.md) - Options and services
- [Library Functions](lib/README.md) - Pure utilities
- [Secrets Module](secrets/README.md) - SOPS integration
- [Services](services/README.md) - PostgreSQL, Redis, etc.
- [IDE Integration](ide/README.md) - VS Code support
