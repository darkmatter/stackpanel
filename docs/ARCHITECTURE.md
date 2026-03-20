# Stack Architecture

This document describes the internal architecture of Stack for contributors and those interested in understanding how the system works.

## Overview

Stack is a Nix-based development environment framework that provides deterministic dev environments, service orchestration, secrets management, IDE integration, and a web-based studio for managing everything.

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

All stack logic lives in `nix/stack/` and has zero dependency on devenv, NixOS, or any other module system. Adapters translate the core outputs to their target:

- `nix/flake/default.nix` - flake-parts adapter
- `nix/flake/modules/devenv.nix` - devenv adapter
- `nix/flake/devenv.nix` - standalone devenv adapter

### Import Flow

```
User's flake.nix
  -> imports flakeModules.default (nix/flake/default.nix)
    -> auto-loads .stack/_internal.nix
    -> lib.evalModules with nix/stack/ (the core)
    -> optionally imports .stack/devenv.nix into devenv.shells.default
    -> creates devShells.default via pkgs.mkShell
```

### Option Namespaces

All options are under `options.stack.*`:

| Namespace | Purpose |
|-----------|---------|
| `stack.{enable, name, root, dirs}` | Project identity and paths |
| `stack.apps` / `stack.appsComputed` | App definitions and computed ports/URLs |
| `stack.ports` | Deterministic port computation config |
| `stack.services` | Canonical service type system |
| `stack.globalServices` | Convenience service definitions (postgres, redis, minio) |
| `stack.devshell` | Shell environment (packages, hooks, env, files) |
| `stack.scripts` | Shell commands |
| `stack.modules` | Extension module registry |
| `stack.secrets` | Master-key secrets management |
| `stack.ide` | VS Code and Zed integration |
| `stack.theme` | Starship prompt theming |
| `stack.step-ca` | Certificate management |
| `stack.aws` | AWS Roles Anywhere |
| `stack.process-compose` | Process orchestration |

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
- **Cloud API**: tRPC via `@stack/api`
- **Agent API**: Dual protocol - HTTP REST and Connect-RPC
- **Auth**: Better-Auth client with JWT session management
- **UI**: Radix UI primitives + shadcn components + Tailwind CSS v4

### apps/stack-go/ - CLI + Agent (Go)

Single Go binary with two modes:

**CLI** (Cobra commands):
- `stack` - Interactive TUI navigator (default)
- `stack services {start,stop,status,restart,logs}` - Service management
- `stack caddy {start,stop,status,add,remove}` - Reverse proxy
- `stack status` - Status dashboard
- `stack agent` - Start the HTTP agent server

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
  -> @stack/api (tRPC routers + types)
     -> @stack/auth (Better Auth + Polar payments)
        -> @stack/db (Drizzle ORM + Neon PostgreSQL)
  -> @stack/agent-client -> @stack/proto (Connect-RPC types)
  -> @stack/ui-web (shadcn components) -> @stack/ui-core (cn, cva, Logo) + @radix-ui/*
```

## Secrets Architecture

Three-tier system:

1. **Master keys**: AGE-encrypted master keys (local auto-generated, team-shared)
2. **SOPS-encrypted YAML**: Per-environment files (`dev.yaml`, `staging.yaml`, `prod.yaml`)
3. **Agenix**: Per-secret `.age` files encrypted to team member SSH public keys

## .stack/ Configuration

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
| `state/stack.json` | Runtime state |
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

- Nix modules implement behavior once in `nix/stack/lib/`, called from thin adapter modules
- The Go CLI is the single writer for generated files (avoids symlink issues, ensures atomicity)
- Proto definitions in `packages/proto/` are the contract between Go agent and TypeScript web app
- Environment variables follow the pattern `STACKPANEL_<KEY>_<PROPERTY>`
- All user-editable config uses YAML/Nix with JSON Schema validation for IDE intellisense

## Plugin Ecosystem

Plugins are just flake inputs:

```nix
inputs = {
  stack.url = "github:darkmatter/stack";

  # Community plugins
  stack-aws.url = "github:someone/stack-aws";
  stack-stripe.url = "github:someone/stack-stripe";
};

imports = [
  inputs.stack.flakeModules.default
  inputs.stack-aws.flakeModules.default
];
```

## Directory Structure

```
nix/stack/
  core/              # Core schema, CLI invocation, state, utilities
    options/         # Centralized option definitions (multi-consumer options only)
    lib/             # Pure service library functions (mkGlobalServices, etc.)
    cli.nix          # CLI-based file generation (includes cli options)
    state.nix        # Legacy state file generation (includes state options)
  devshell/          # Shell subsystem (scripts, files, codegen, bin wrappers)
  network/           # Step CA certificates, port env vars, DNS (includes dns options)
  services/          # Service implementations (postgres, redis, caddy, aws, binary-cache w/ options)
  secrets/           # Master-key encryption (agenix, SOPS, combined)
  ide/               # VS Code and Zed file generation
  modules/           # Auto-discovered directory modules
  lib/               # Pure library functions (ports, theme, IDE, paths)
  apps/              # App-level features and CI (includes ci options)
  tui/               # Terminal UI theme (includes theme options)
  packages/          # Nix package definitions
```
