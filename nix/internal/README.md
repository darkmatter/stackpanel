# nix/internal/

**Internal Nix configuration for the stackpanel repository itself.**

This directory contains Nix modules and devenv configurations that are specific to developing the stackpanel project. These are **not** meant to be imported by external users—they configure the local development environment for this repository.

## Structure

```
nix/internal/
├── README.md              # This file
├── flake-module.nix       # Flake-parts module for external user integration
├── stackpanel.nix         # Main devenv config for this repo
└── devenv/                # Devenv modules for local development
    ├── README.md
    ├── devenv.nix         # Root module that imports all sub-modules
    ├── docs/              # Documentation app (apps/docs)
    │   ├── devenv.nix     # Docs dev server process
    │   └── generate.nix   # Options documentation generator
    ├── tools/             # Development infrastructure
    │   └── devenv.nix     # PostgreSQL, Redis, Minio, Caddy
    └── web/               # Web app (apps/web)
        └── devenv.nix     # Web dev server process
```

## Key Files

### `flake-module.nix`
The flake-parts module that external users import into their flakes. This provides the `stackpanel.flakeModules.default` output and makes stackpanel's packages available via `perSystem`.

### `stackpanel.nix`
Main devenv configuration for developing stackpanel itself. Enables:
- Theme and IDE integrations (VSCode)
- AWS Roles Anywhere authentication
- Step CA for internal certificates
- MOTD with helpful commands

### `devenv/`
Contains all the devenv modules for local development. See [devenv/README.md](devenv/README.md) for details.

## Usage

These files are automatically imported when you run `devenv shell` or `devenv up` in the stackpanel repository root. You don't need to manually import them.

## For External Users

If you're looking to use stackpanel in your own project, you should import from `nix/stackpanel/` instead. See the main project documentation for user-facing modules.
