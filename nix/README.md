# Nix Configuration

This directory contains all Nix code for the Stack project, organized into three main sections.

## Directory Structure

```
nix/
├── README.md           # This file
├── NOTES.md            # Development notes and scratch
│
├── stack/         # Main module system (for users)
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
    ├── stack.nix      # Main devenv config
    └── devenv/             # Per-app devenv modules
```

## Overview

### `stack/` - Main Module System

The core Stack functionality that users import into their projects:

- **Options schema** - All `stack.*` configuration options
- **Service orchestration** - PostgreSQL, Redis, MinIO, Caddy
- **Secrets management** - SOPS/vals integration with codegen
- **IDE integration** - VS Code workspace generation
- **TLS support** - Step CA certificate management

See [stack/README.md](stack/README.md) for detailed documentation.

### `flake/` - Flake Outputs

What gets exported in the flake for users to consume:

- **devenvModules** - Import into your devenv.nix
- **templates** - `nix flake init -t github:coopermaruyama/stack`
- **devshells** - Factory functions for creating shells

See [flake/README.md](flake/README.md) for details.

### `internal/` - Internal Configuration

Configuration specific to developing Stack itself:

- Development environment setup
- Per-app devenv modules (web, docs, etc.)
- CI shell configuration

See [internal/README.md](internal/README.md) for details.

## Usage

### For Users (External Projects)

Add Stack to your flake inputs:

```nix
{
  inputs.stack.url = "github:coopermaruyama/stack";
}
```

Import the devenv module:

```nix
# devenv.nix
{ inputs, ... }: {
  imports = [ inputs.stack.devenvModules.default ];

  stack = {
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
  imports = [ inputs.stack.flakeModules.default ];

  perSystem = { ... }: {
    devenv.shells.default = {
      stack.name = "my-project";
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
│  (stack.nix imports nix/stack/ for this repo)     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  nix/stack/                            │
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
| `stack/default.nix` | Main module entry point |
| `stack/core/options/*.nix` | All configuration options |
| `stack/lib/default.nix` | Library functions |
| `flake/modules/devenv/default.nix` | Devenv module adapter |
| `internal/stack.nix` | This repo's devenv config |
