# nix/internal/devenv/

**Internal devenv-compatible modules for the stackpanel project.**

This directory contains modules that define processes, languages, and services for developing the stackpanel project. These modules use devenv's syntax but are loaded by the flake's unified shell.

## Structure

```
devenv/
├── README.md          # This file
├── devenv.nix         # Root module - imports all sub-modules
├── docs/              # Documentation site modules
│   ├── devenv.nix     # Docs dev server (apps/docs)
│   └── generate.nix   # Options documentation generator
├── tools/             # Development infrastructure
│   └── devenv.nix     # Additional tools and services
└── web/               # Web application modules
    └── devenv.nix     # Web dev server (apps/web)
```

## Usage

Enter the development shell and use the `dev` command:

```bash
# Enter the shell
nix develop --impure

# Start all processes
dev

# Processes available:
# - web: Web app dev server
# - docs: Documentation dev server
# - server: API server
# - format-watch: Auto-format on file changes
```

## Modules

### `devenv.nix`
Root aggregator module that imports all sub-modules.

### `docs/devenv.nix`
Configures the documentation development server:
- Enables JavaScript/Bun runtime
- Defines `processes.docs` running `bun run dev` in `apps/docs`

### `tools/devenv.nix`
Development infrastructure and additional services.

### `web/devenv.nix`
Web application development server:
- Enables JavaScript/Bun runtime
- Defines `processes.web` running `bun dev` in `apps/web`

## Services

PostgreSQL, Redis, Minio, and Caddy are configured via stackpanel's globalServices options in `.stackpanel/config.nix`. Start them with:

```bash
stackpanel services start
```
