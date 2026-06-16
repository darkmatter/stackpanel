# Nix Configuration

This directory contains all Nix code for the Stackpanel project, organized into three main sections.

## Directory Structure

```text
nix/
├── README.md           # This file
├── NOTES.md            # Development notes and scratch
│
├── stackpanel/         # Main module system (for users)
│   ├── core/           # Core options and services
│   ├── lib/            # Pure library functions
│   ├── apps/           # App configuration
│   ├── devshell/       # Shell configuration
│   ├── ide/            # VS Code / Zed integration
│   ├── network/        # Step CA / TLS
│   ├── packages/       # Nix packages
│   ├── secrets/        # SOPS secrets
│   ├── services/       # Service orchestration
│   └── tui/            # TUI theming
│
├── flake/              # Flake outputs (exported to users)
│   ├── default.nix     # flake-parts module
│   ├── per-system-outputs.nix # Per-system output builder
│   ├── devshells/      # Devshell factory functions
│   └── templates/      # Project templates
│
└── internal/           # Internal config (for this repo only)
    ├── flake/          # Flake-parts module used by this repo
    └── stackpanel/     # This repo's stackpanel configuration
```

## Overview

### `stackpanel/` - Main Module System

The core Stackpanel functionality that users import into their projects:

- **Options schema** - All `stackpanel.*` configuration options
- **Service orchestration** - PostgreSQL, Redis, MinIO, Caddy
- **Secrets management** - SOPS/vals integration with codegen
- **IDE integration** - VS Code and Zed workspace generation
- **TLS support** - Step CA certificate management

See [stackpanel/README.md](stackpanel/README.md) for detailed documentation.

### `flake/` - Flake Outputs

What gets exported in the flake for users to consume:

- **`flakeModules.default`** - Import into your `flake.nix` (flake-parts)
- **`lib.mkFlake`** - High-level helper for wiring up stackpanel flakes
- **`templates`** - `nix flake init -t github:darkmatter/stackpanel`
- **`devshells`** - Factory functions for creating shells

See [flake/README.md](flake/README.md) for details.

### `internal/` - Internal Configuration

Configuration specific to developing Stackpanel itself:

- Development environment setup
- This repo's `.stack/config.nix`
- CI shell configuration

See [internal/README.md](internal/README.md) for details.

## Usage

### For Users (External Projects)

Add Stackpanel to your flake inputs:

```nix
{
  inputs.stackpanel.url = "github:darkmatter/stackpanel";
}
```

Use the flake-parts module:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    stackpanel.url = "github:darkmatter/stackpanel";
  };

  outputs = inputs @ { self, stackpanel, ... }:
    stackpanel.lib.mkFlake {
      inherit inputs self;

      perSystem = { pkgs, ... }: {
        packages.hello = pkgs.hello;
      };
    };
}
```

Configure the project in `.stack/config.nix`:

```nix
{
  stackpanel = {
    name = "my-project";
    apps.web.port = 3000;
    services.postgres.enable = true;
  };
}
```

### For Development (This Repo)

Enter the development shell:

```bash
direnv allow
# or
nix develop
```

Start all services:

```bash
dev
```

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                        flake.nix                            │
│  (imports nix/internal/flake/ for flake-parts)              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  nix/internal/                              │
│  (.stack/config.nix imports nix/stackpanel/ for this repo)  │
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
│  (exports: flakeModules, lib.mkFlake, templates, devshells) │
└─────────────────────────────────────────────────────────────┘
```

## Key Files

| File                            | Purpose                       |
| ------------------------------- | ----------------------------- |
| `stackpanel/default.nix`        | Main module entry point       |
| `stackpanel/core/options/*.nix` | All configuration options     |
| `stackpanel/lib/default.nix`    | Library functions             |
| `flake/default.nix`             | flake-parts module adapter    |
| `.stack/config.nix`             | This repo's stackpanel config |
