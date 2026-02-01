# Stackpanel Architecture

This document describes the internal architecture of Stackpanel for contributors and those interested in understanding how the system works.

## Overview

Stackpanel is a Nix-based development environment framework that provides deterministic dev environments, service orchestration, secrets management, IDE integration, and a web-based studio for managing everything.

## Runtime Architecture

The system has three runtime planes:

1. **Nix plane** - Evaluates configuration, computes ports, provisions the devshell, generates files. Runs once on shell entry.
2. **Go agent plane** - A localhost HTTP server (default port 9876) that bridges the web UI to the local Nix environment. Provides REST + Connect-RPC APIs, SSE events, file watching, and process management.
3. **Web plane** - A React (TanStack Start) application that serves as the studio UI. Communicates with the cloud API via tRPC and with the local Go agent via HTTP REST + Connect-RPC.

```
Browser (Studio UI)
  |
  |-- tRPC --> Cloud API (Hono on Cloudflare Workers)
  |               |-- Better Auth (sessions, Polar payments)
  |               |-- Drizzle ORM --> Neon PostgreSQL
  |
  |-- HTTP/Connect-RPC --> Go Agent (localhost:9876)
                              |-- nix eval (config, options, packages)
                              |-- process-compose (service lifecycle)
                              |-- file system (secrets, config, code)
                              |-- Caddy (reverse proxy, TLS)
                              |-- Step CA (certificates)
```

## Components

| Component | Role |
|-----------|------|
| **Agent** | Go binary serving the GUI locally. Executes Nix commands. Works offline. |
| **GUI (Studio)** | Browser interface to configure stack, trigger builds, view status. |
| **Flake** | Source of truth. flake-parts modules define the entire stack. |
| **Generated Files** | Standard paths (`.github/`, `Dockerfile`). Git-tracked. CI works without Nix. |

## Nix Module System

### Core Design: Adapter-Agnostic Core + Thin Adapters

All stackpanel logic lives in `nix/stackpanel/` and has zero dependency on devenv, NixOS, or any other module system. Adapters translate the core outputs to their target:

- `nix/flake/default.nix` - flake-parts adapter
- `nix/flake/modules/devenv.nix` - devenv adapter
- `nix/flake/devenv.nix` - standalone devenv adapter

### Import Flow

```
User's flake.nix
  -> imports flakeModules.default (nix/flake/default.nix)
    -> auto-loads .stackpanel/_internal.nix
    -> lib.evalModules with nix/stackpanel/ (the core)
    -> optionally imports .stackpanel/devenv.nix into devenv.shells.default
    -> creates devShells.default via pkgs.mkShell
```

### Option Namespaces

All options are under `options.stackpanel.*`:

| Namespace | Purpose |
|-----------|---------|
| `stackpanel.{enable, name, root, dirs}` | Project identity and paths |
| `stackpanel.apps` / `stackpanel.appsComputed` | App definitions and computed ports/URLs |
| `stackpanel.ports` | Deterministic port computation config |
| `stackpanel.services` | Canonical service type system |
| `stackpanel.globalServices` | Convenience service definitions (postgres, redis, minio) |
| `stackpanel.devshell` | Shell environment (packages, hooks, env, files) |
| `stackpanel.scripts` | Shell commands |
| `stackpanel.modules` | Extension module registry |
| `stackpanel.secrets` | Master-key secrets management |
| `stackpanel.ide` | VS Code and Zed integration |
| `stackpanel.theme` | Starship prompt theming |
| `stackpanel.step-ca` | Certificate management |
| `stackpanel.aws` | AWS Roles Anywhere |
| `stackpanel.process-compose` | Process orchestration |

## Deterministic Port System

Ports are computed from the project name hash, ensuring identical ports across all team members without manual configuration:

1. Hash project name with MD5
2. Convert first 8 hex chars to decimal
3. Constrain to range `[3000, 65000)`, round to nearest 100
4. Apps get sequential ports at `base + 0-9`
5. Services get stable ports via `hash(projectName + serviceName)` within the project's port range

Environment variables: `STACKPANEL_<KEY>_PORT` (e.g., `STACKPANEL_POSTGRES_PORT=6410`).

## Application Architecture

### apps/web/ - Studio UI (React)

- **Framework**: TanStack Start (SSR-capable React) + Vite + Cloudflare Workers
- **Router**: TanStack Router with file-based routing
- **State**: TanStack Query with SuperJSON serialization
- **Cloud API**: tRPC via `@stackpanel/api`
- **Agent API**: Dual protocol - HTTP REST and Connect-RPC
- **Auth**: Better-Auth client with JWT session management
- **UI**: Radix UI primitives + shadcn components + Tailwind CSS v4

### apps/stackpanel-go/ - CLI + Agent (Go)

Single Go binary with two modes:

**CLI** (Cobra commands):
- `stackpanel` - Interactive TUI navigator (default)
- `stackpanel services {start,stop,status,restart,logs}` - Service management
- `stackpanel caddy {start,stop,status,add,remove}` - Reverse proxy
- `stackpanel status` - Status dashboard
- `stackpanel agent` - Start the HTTP agent server

**Agent** (localhost HTTP server, port 9876):
- JWT auth via popup pairing flow
- SSE event broadcasting on config changes
- File watching + FlakeWatcher
- 60+ REST API endpoints

### apps/docs/ - Documentation Site

- **Framework**: Next.js with Fumadocs (static export for Cloudflare)
- **Content**: MDX in `content/docs/`
- Auto-generation from Nix options and Cobra commands

## Package Architecture

```
apps/web
  -> @stackpanel/api (tRPC routers + types)
     -> @stackpanel/auth (Better Auth + Polar payments)
        -> @stackpanel/db (Drizzle ORM + Neon PostgreSQL)
  -> @stackpanel/agent-client -> @stackpanel/proto (Connect-RPC types)
  -> @stackpanel/ui -> @stackpanel/ui-web -> @stackpanel/ui-core + @stackpanel/ui-primitives
```

## Secrets Architecture

Three-tier system:

1. **Master keys**: AGE-encrypted master keys (local auto-generated, team-shared)
2. **SOPS-encrypted YAML**: Per-environment files (`dev.yaml`, `staging.yaml`, `prod.yaml`)
3. **Agenix**: Per-secret `.age` files encrypted to team member SSH public keys

## .stackpanel/ Configuration

### Files

| Path | Purpose |
|------|---------|
| `config.nix` | Primary user-editable config |
| `_internal.nix` | Merge point for all config sources |
| `devenv.nix` | Devenv-specific config |
| `config.local.nix` | Per-user gitignored overrides |
| `data/*.nix` | Auto-loaded data tables |
| `secrets/` | SOPS config, encrypted YAML files |

### State and Generated Files (runtime)

| Path | Purpose |
|------|---------|
| `state/stackpanel.json` | Runtime state |
| `state/shellhook.sh` | Generated shell hook |
| `state/starship.toml` | Generated prompt config |
| `gen/ide/vscode/` | VS Code workspace + devshell loader |

## Build and Deploy

- **Monorepo orchestration**: Turborepo (JS/TS tasks) + Nix (dev environment)
- **Package manager**: Bun with workspaces
- **Web deployment**: Cloudflare Workers via Alchemy + Vite Cloudflare plugin
- **Docs deployment**: Static export to Cloudflare
- **Go build**: `gomod2nix` for Nix, `air` for hot reload in dev
- **CI**: GitHub Actions with OIDC-based AWS access

## Key Conventions

- Nix modules implement behavior once in `nix/stackpanel/lib/`, called from thin adapter modules
- The Go CLI is the single writer for generated files (avoids symlink issues, ensures atomicity)
- Proto definitions in `packages/proto/` are the contract between Go agent and TypeScript web app
- Environment variables follow the pattern `STACKPANEL_<KEY>_<PROPERTY>`
- All user-editable config uses YAML/Nix with JSON Schema validation for IDE intellisense

## Plugin Ecosystem

Plugins are just flake inputs:

```nix
inputs = {
  stackpanel.url = "github:darkmatter/stackpanel";

  # Community plugins
  stackpanel-aws.url = "github:someone/stackpanel-aws";
  stackpanel-stripe.url = "github:someone/stackpanel-stripe";
};

imports = [
  inputs.stackpanel.flakeModules.default
  inputs.stackpanel-aws.flakeModules.default
];
```

## Directory Structure

```
nix/stackpanel/
  core/              # Options definitions, CLI invocation, state, utilities
  devshell/          # Shell subsystem (scripts, files, codegen, bin wrappers)
  network/           # Step CA certificates, port env vars
  services/          # Service implementations (postgres, redis, caddy, aws)
  secrets/           # Master-key encryption (agenix, SOPS, combined)
  ide/               # VS Code and Zed file generation
  modules/           # Auto-discovered directory modules
  lib/               # Pure library functions
  apps/              # App-level features and CI
  tui/               # Terminal UI theme
  packages/          # Nix package definitions
```
