# nix/internal/devenv/

**Devenv modules for local development of the stackpanel project.**

This directory contains devenv configuration modules that set up the development environment for working on stackpanel itself.

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

## Modules

### `devenv.nix`
Root aggregator module that imports all sub-modules. This is the entry point for the devenv configuration.

### `docs/devenv.nix`
Configures the documentation development server:
- Enables JavaScript/Bun runtime
- Defines `processes.docs` running `bun run dev` in `apps/docs`
- Provides `docs:install` task for dependency installation

### `docs/generate.nix`
Options documentation generator:
- Uses `nixosOptionsDoc` to generate JSON from stackpanel module options
- Provides `generate-docs` script to create MDX files for fumadocs
- Outputs: `stackpanel-docs-options-json`, `stackpanel-docs-options-md`

### `tools/devenv.nix`
Development infrastructure services:
- **PostgreSQL**: Local database (project-local in `.stackpanel/state/services/`)
- **Redis**: Caching server
- **Minio**: S3-compatible object storage
- **Caddy**: Reverse proxy (global, shared across projects)
- **Mailpit**: Email testing UI

Port allocation is automatic based on project name to avoid conflicts.

### `web/devenv.nix`
Web application development server:
- Enables JavaScript/Bun runtime
- Defines `processes.web` running `bun dev` in `apps/web`

## Processes

When you run `devenv up`, the following processes are available:
- `web` - Web app dev server at `stackpanel.localhost`
- `docs` - Documentation dev server at `docs.localhost`

## Common Commands

```bash
# Start development environment
devenv shell

# Start all processes
devenv up

# Generate options documentation
generate-docs

# Check service status
stackpanel status

# Start/stop services
stackpanel services start
stackpanel services stop
```

## Configuration

Services are configured with project-local state stored in `.stackpanel/state/services/`. This allows multiple stackpanel-based projects to run independently with their own database versions and data.

Caddy is the exception—it runs globally to avoid port 443 conflicts, with configuration in `~/.config/caddy/sites.d/`.
