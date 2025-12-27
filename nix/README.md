# Nix Configuration

This directory contains all Nix code for the Stackpanel project, organized into three main sections.

## Directory Structure

```
nix/
├── README.md           # This file
├── NOTES.md            # Development notes and scratch
│
├── stackpanel/         # Main module system (for users)
│   ├── core/           # Core options and services
│   ├── lib/            # Pure library functions
│   ├── apps/           # App configuration
│   ├── devshell/       # Shell configuration
│   ├── ide/            # VS Code integration
│   ├── network/        # Step CA / TLS
│   ├── packages/       # Nix packages
│   ├── secrets/        # SOPS secrets
│   ├── services/       # Service orchestration
│   └── tui/            # TUI application
│
├── flake/              # Flake outputs (exported to users)
│   ├── devshells/      # Devshell factory functions
│   ├── modules/        # Devenv and flake-parts modules
│   └── templates/      # Project templates
│
└── internal/           # Internal config (for this repo only)
    ├── flake-module.nix    # Flake-parts module
    ├── stackpanel.nix      # Main devenv config
    └── devenv/             # Per-app devenv modules
```

## Overview

### `stackpanel/` - Main Module System

The core Stackpanel functionality that users import into their projects:

- **Options schema** - All `stackpanel.*` configuration options
- **Service orchestration** - PostgreSQL, Redis, MinIO, Caddy
- **Secrets management** - SOPS/vals integration with codegen
- **IDE integration** - VS Code workspace generation
- **TLS support** - Step CA certificate management

See [stackpanel/README.md](stackpanel/README.md) for detailed documentation.

### `flake/` - Flake Outputs

What gets exported in the flake for users to consume:

- **devenvModules** - Import into your devenv.nix
- **templates** - `nix flake init -t github:coopermaruyama/stackpanel`
- **devshells** - Factory functions for creating shells

See [flake/README.md](flake/README.md) for details.

### `internal/` - Internal Configuration

Configuration specific to developing Stackpanel itself:

- Development environment setup
- Per-app devenv modules (web, docs, etc.)
- CI shell configuration

See [internal/README.md](internal/README.md) for details.

## Usage

### For Users (External Projects)

Add Stackpanel to your flake inputs:

```nix
{
  inputs.stackpanel.url = "github:coopermaruyama/stackpanel";
}
```

Import the devenv module:

```nix
# devenv.nix
{ inputs, ... }: {
  imports = [ inputs.stackpanel.devenvModules.default ];
  
  stackpanel = {
    name = "my-project";
    apps.web.port = 3000;
    services.postgres.enable = true;
  };
}
```

Or use the flake-parts module:

```nix
# flake.nix
{
  imports = [ inputs.stackpanel.flakeModules.default ];
  
  perSystem = { ... }: {
    devenv.shells.default = {
      stackpanel.name = "my-project";
    };
  };
}
```

### For Development (This Repo)

Enter the development shell:

```bash
direnv allow
# or
devenv shell
# or
nix develop --impure
```

Start all services:

```bash
devenv up
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        flake.nix                            │
│  (imports nix/internal/flake-module.nix for flake-parts)    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  nix/internal/                              │
│  (stackpanel.nix imports nix/stackpanel/ for this repo)     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  nix/stackpanel/                            │
│  (core module system - reusable by external projects)       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    nix/flake/                               │
│  (exports: devenvModules, templates, devshells)             │
└─────────────────────────────────────────────────────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `stackpanel/default.nix` | Main module entry point |
| `stackpanel/core/options/*.nix` | All configuration options |
| `stackpanel/lib/default.nix` | Library functions |
| `flake/modules/devenv/default.nix` | Devenv module adapter |
| `internal/stackpanel.nix` | This repo's devenv config |
