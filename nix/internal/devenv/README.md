# nix/internal/devenv/

**Devenv modules for `devenv shell` workflow.**

This directory contains devenv-specific modules for the stackpanel project.
These are used by `devenv shell` / `devenv up`, NOT by `nix develop`.

For `nix develop`, the flakeModule creates a pure stackpanel shell without devenv.

## Structure

```
devenv/
├── README.md          # This file
├── devenv.nix         # Root module - imports all sub-modules
├── docs/              # Documentation site modules
│   ├── devenv.nix     # Docs dev server (apps/docs)
│   └── generate.nix   # Options documentation generator
├── tools/             # Development infrastructure
│   └── devenv.nix     # Services: PostgreSQL, Redis, Minio, Caddy
└── web/               # Web application modules
    └── devenv.nix     # Web dev server (apps/web)
```

## Usage

These modules are imported by `devenv.nix` at the project root:

```nix
# devenv.nix (project root)
{
  imports = [
    ./nix/flake/modules/devenv.nix  # Stackpanel adapter
    ./nix/internal/devenv/devenv.nix  # This directory
  ];
  stackpanel = import ./.stackpanel/_internal.nix { inherit pkgs lib; };
}
```

## Modules

### `devenv.nix`
Root aggregator module that imports all sub-modules.

### `docs/devenv.nix`
Configures the documentation development server:
- Enables JavaScript/Bun runtime
- Defines `processes.docs` running `bun run dev` in `apps/docs`
- Provides `docs:install` task for dependency installation

### `tools/devenv.nix`
Development infrastructure services:
- **Mailpit**: Email testing UI
- **Tailscale funnel**: Share dev server with team

Note: PostgreSQL, Redis, Minio, Caddy are configured via stackpanel's
globalServices options in `.stackpanel/config.nix`, not here.

### `web/devenv.nix`
Web application development server:
- Enables JavaScript/Bun runtime
- Defines `processes.web` running `bun dev` in `apps/web`

## Processes

When you run `devenv up`, the following processes are available:
- `web` - Web app dev server at `stackpanel.localhost`
- `docs` - Documentation dev server at `docs.localhost`

## Commands

```bash
# For devenv shell workflow:
devenv shell     # Enter shell with languages/services
devenv up        # Start all processes (web, docs)

# For pure stackpanel workflow:
nix develop      # Enter pure stackpanel shell (no devenv)
```

## When to Use Which

| Workflow | Command | Use Case |
|----------|---------|----------|
| Pure Stackpanel | `nix develop` | Fast, reproducible, CI-friendly |
| Devenv | `devenv shell` | Need languages.*, services.*, processes.* |
