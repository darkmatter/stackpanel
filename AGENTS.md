You are an experienced, pragmatic software engineering AI agent. Do not over-engineer a solution when a simple one is possible. Keep edits minimal. If you want an exception to ANY rule, you MUST stop and get permission first.

> **Note**: This file is partially managed by [Ruler](https://github.com/intellectronica/ruler). The architecture sections below are auto-regenerated from `.ruler/*.md` on `bun run ruler:apply`. The preamble and agent-guidance sections above/below those blocks are manually maintained — do not remove them.

---

# Stackpanel — Agent Contribution Guide

## Project Overview

**Stackpanel** is a Nix-based development environment framework and studio UI for managing multi-app monorepos. It provides:

- **Deterministic dev environments** — reproducible devshells via Nix/devenv
- **Service orchestration** — PostgreSQL, Redis, Minio, Caddy, Step CA managed via process-compose
- **Secrets management** — SOPS/AGE-encrypted secrets with per-app codegen
- **IDE integration** — VS Code & Zed workspace generation
- **Web studio** — React (TanStack Start) UI on Cloudflare Workers, talking to a local Go agent

### Technology Stack

| Layer | Technologies |
|---|---|
| Dev environment | Nix, devenv, flake-parts, direnv |
| Config language | Nix (modules, lib functions) |
| Backend Go | Go 1.25, Cobra, Bubble Tea, Connect-RPC, fsnotify |
| Web frontend | React 19, TanStack Router/Query/Start, Vite, Tailwind v4, Radix UI |
| Cloud API | Hono on Cloudflare Workers, tRPC, Better Auth, Drizzle ORM |
| Database | Neon PostgreSQL (serverless) |
| Package manager | Bun (workspaces + lockfile) |
| Monorepo | Turborepo |
| Deployment | Cloudflare Workers (web), Colmena/NixOS (server), Alchemy IaC (infra) |
| Issue tracking | **bd (beads)** — see [Issue Tracking](#issue-tracking-with-bd-beads) |

---

## Reference

### Repository Layout

```
.
├── apps/
│   ├── web/               # Studio UI (React + TanStack Start, Cloudflare Workers)
│   ├── stackpanel-go/     # CLI + local agent (Go binary)
│   ├── docs/              # Documentation site (Fumadocs / Next.js)
│   └── tui/               # Experimental React terminal UI (OpenTUI)
├── packages/
│   ├── api/               # tRPC routers (@stack/api)
│   ├── auth/              # Better Auth (@stack/auth)
│   ├── db/                # Drizzle schema + Neon client (@stack/db)
│   ├── proto/             # Protobuf definitions + generated Go/TS types
│   ├── agent-client/      # Connect-RPC client factory with JWT (@stack/agent-client)
│   ├── ui/                # Shared UI (shadcn-style components + Radix)
│   ├── gen/env/           # Generated, type-safe env package (@gen/env)
│   ├── infra/             # Alchemy IaC scripts
│   └── scripts/           # Shell scripts for secrets/entrypoint
├── nix/
│   ├── stackpanel/        # Core Nix framework (adapter-agnostic)
│   │   ├── core/          # Schema, state, CLI integration, option definitions
│   │   ├── lib/           # Pure library functions (ports, theme, IDE, services)
│   │   ├── modules/       # Thin adapters (bun, go, turbo, git-hooks, process-compose)
│   │   ├── services/      # Service modules (caddy, aws, global-services, binary-cache)
│   │   ├── network/       # Network modules (ports, step-ca)
│   │   ├── ide/           # IDE file generation (vscode, zed)
│   │   ├── secrets/       # Secrets management (agenix, SOPS, codegen)
│   │   └── db/            # Proto-Nix schema system (.proto.nix files)
│   └── flake/             # flake-parts + devenv adapters
├── .stack/
│   ├── config.nix         # Primary user config (apps, services, theme, IDE)
│   ├── data/*.nix         # Auto-loaded data tables
│   ├── gen/               # Generated files (checked in; regenerated on devshell entry)
│   ├── secrets/           # SOPS config + encrypted YAML secrets
│   └── state/             # Runtime state (gitignored: stack.json, keys/, etc.)
├── tests/                 # Smoke tests + template tests
├── scripts/deploy/        # Deploy scripts (artifact build/publish, Alchemy, logs)
├── Justfile               # Task runner (use `just --list`)
├── flake.nix              # Nix flake entrypoint
└── turbo.json             # Turborepo task config
```

### Key Files

| File | Purpose |
|---|---|
| `flake.nix` | Nix flake: exports devShells, packages, devenvModules, lib |
| `.stack/config.nix` | Main project config: apps, services, users, theme, IDE |
| `nix/stackpanel/core/options/` | All `options.stack.*` option definitions |
| `nix/stackpanel/lib/` | Pure Nix library functions (ports, theme, IDE, services) |
| `apps/stackpanel-go/cmd/` | Cobra CLI command definitions |
| `apps/stackpanel-go/internal/agent/` | Agent HTTP server (60+ endpoints) |
| `apps/web/src/routes/` | TanStack Router file-based routes |
| `packages/proto/` | Protobuf definitions (source of truth for agent ↔ web types) |
| `packages/gen/env/src/` | Generated type-safe env (do not edit manually) |

---

## Essential Commands

> **All commands must be run inside the Nix devshell.** Wrong binaries will be used otherwise.

```bash
# Enter the devshell (required before anything else)
nix develop --impure
# or, with direnv:
direnv allow
```

### Development

```bash
dev                          # Start all services via process-compose
bun run dev:web              # Start only the web app
bun run dev:server           # Start only the server
stack services start         # Start background services (postgres, redis, etc.)
stack status                 # Check service/agent status
```

### Build & Type-check

```bash
bun run build                # Build all packages (Turborepo)
bun run check-types          # TypeScript type check (turbo)
nix flake check --impure     # Nix flake check (also: just check)
```

### Lint & Format

```bash
bun run lint                 # oxlint (TypeScript/React)
bun run check                # oxlint + oxfmt --write
```

### Test

```bash
just test                    # Smoke tests (devenv + native) + template tests
just test-smoke              # Smoke tests only (both shells)
just test-devenv             # Smoke tests — devenv shell only
just test-native             # Smoke tests — native shell only
just test-templates          # Test all project templates
just test-template <name>    # Test a specific template
bun run test                 # JS/TS tests via Turborepo
```

### Go (apps/stackpanel-go)

```bash
cd apps/stackpanel-go
go build ./...               # Build
go test ./...                # Run Go tests
air                          # Hot reload (dev mode)
```

### Database

```bash
bun run db:push              # Push Drizzle schema changes
bun run db:studio            # Open Drizzle Studio
bun run db:generate          # Generate Drizzle types
bun run db:migrate           # Run migrations
```

### Nix / Infra

```bash
just dev                     # Enter devenv shell
just check                   # nix flake check --impure
just clean-cache             # Wipe nix-direnv cache and reload
just deploy <region>         # Build → publish artifact → Alchemy IaC (EC2/AL2023)
just deploy-nixos            # Build → Cachix push → Alchemy infra → Colmena apply
```

### Issue Tracking (bd / beads)

```bash
bd ready --json              # Show unblocked issues
bd create "Title" --description="..." -t feature -p 2 --json
bd update <id> --claim --json
bd close <id> --reason "Done" --json
```

---

## Patterns

### Adding a Nix Module Option

1. Define the option in `nix/stackpanel/core/options/<domain>.nix` using `lib.mkOption`
2. Implement logic once in `nix/stackpanel/lib/<domain>.nix` (pure function)
3. Wire in the relevant module under `nix/stackpanel/modules/` or `services/`; keep the module thin
4. Guard config blocks with `lib.mkIf cfg.enable`

```nix
# In core/options/mything.nix
options.stack.myThing = {
  enable = lib.mkEnableOption "my thing";
  port = lib.mkOption { type = lib.types.port; default = 1234; description = "Port for my thing"; };
};

# In lib/mything.nix — pure computation
mkMyThing = cfg: { port = cfg.port; /* ... */ };

# In modules/mything.nix — thin wiring
config = lib.mkIf cfg.enable {
  stack.devshell.env.MY_THING_PORT = toString (lib.stackpanel.mkMyThing cfg).port;
};
```

### Adding Generated Files (CLI-based generation)

**Do not** use `devenv.files` for generated files — the Go CLI is the single writer (avoids symlink issues).

1. Add the data to `fullConfig` in the relevant Nix module
2. Add generation logic in `apps/stackpanel-go/internal/generator/`
3. Check generated output into `.stack/gen/` for IDE support without devshell

### Proto-Nix Schema System

`.proto.nix` files in `nix/stackpanel/db/schemas/` are the single source of truth for types shared between Nix, Go, and TypeScript. Edit the `.proto.nix` file, then run `generate:proto` / `generate:types`.

### Connecting a New tRPC Procedure

```ts
// packages/api/src/routers/myRouter.ts
export const myRouter = router({
  getData: protectedProcedure.query(async ({ ctx }) => {
    return await ctx.db.select().from(myTable);
  }),
});
// Register in packages/api/src/router.ts
```

### Secrets Workflow

1. Add key/value to `.stack/secrets/vars/<env>.sops.yaml` via `sops`
2. Add field to the relevant secret schema YAML under `.stack/secrets/apps/<app>/`
3. On next devshell entry, codegen regenerates `packages/gen/env/src/`
4. Access via `import "@gen/env/web"` (type-safe)

### Port Conventions

- Ports are deterministic — never hardcode a port; always read from `STACKPANEL_<KEY>_PORT`
- App ports: `basePort + 0-9` (sequential); service ports: computed from hash
- Port allocation is documented in `nix/stackpanel/network/ports.nix`

---

## Anti-patterns

| ❌ Don't | ✅ Do instead |
|---|---|
| Run commands outside the Nix devshell | Always `nix develop --impure` first |
| Hardcode port numbers | Read `STACKPANEL_<KEY>_PORT` env vars |
| Write directly to `.stack/gen/` | Let the Go CLI generator write these files |
| Add options directly to `config = {}` without `lib.mkIf` | Guard all config blocks with `lib.mkIf cfg.enable` |
| Duplicate computation in both lib and modules | Implement once in `nix/stackpanel/lib/`, call from modules |
| Use markdown TODO lists for task tracking | Use `bd create` (beads) — the only allowed tracker |
| Assume `devenv shell` is available | Use `nix develop --impure` — devenv is not always present |
| Edit `packages/gen/env/src/` manually | It's generated — edit the source schemas instead |
| Store secrets in plaintext in git | Use SOPS-encrypted `.sops.yaml` files |
| Mutate `options.stack.*` from outside the framework | Use the `.stack/config.nix` / `data/*.nix` entry points |

---

## Code Style

- **TypeScript/React**: formatted with `oxfmt`, linted with `oxlint`. Run `bun run check` before committing.
- **Nix**: follow the existing module patterns; use `lib.mkOption` with descriptions everywhere.
- **Go**: standard `gofmt`; project uses `golangci-lint` (configured in `apps/stackpanel-go/`).
- **Imports**: packages export source TypeScript directly (no build step); internal deps use `workspace:*`.
- **Component style**: shadcn-style (Radix primitives + Tailwind v4 + `cn()` from `@stack/ui-core`).

---

## Commit and Pull Request Guidelines

### Before Committing

```bash
bun run check          # lint + format (TS/React)
bun run check-types    # TypeScript type check
nix flake check --impure  # Nix validity
```

For Go changes:

```bash
cd apps/stackpanel-go && go build ./... && go test ./...
```

### Commit Message Format

Use the conventional commits style:

```
<type>: <short description>

# Types: feat | fix | chore | refactor | docs | test | ci | build
```

Examples:
- `feat: add S3 artifact upload to deploy pipeline`
- `fix: correct port computation for services hash`
- `chore: update bun lockfile`
- `refactor: extract mkMyThing into nix/stackpanel/lib/`

### Session End Checklist (mandatory)

Before ending a work session, complete **all** of the following — work is **not complete** until `git push` succeeds:

```bash
# 1. File issues for remaining/discovered work
bd create "..." --description="..." -t task -p 2 --json

# 2. Run quality gates (if code changed)
bun run check && bun run check-types

# 3. Update issue status
bd close <id> --reason "Completed" --json

# 4. Sync and push
git pull --rebase
bd dolt push
git push
git status   # Must show: "up to date with origin"
```

**Never** leave work uncommitted and unpushed. **Never** say "ready to push when you are" — you must push.

---

<!-- Generated by Ruler -->


<!-- Source: .ruler/architecture.md -->

# Stack Architecture

## What Stack Is

Stack is a Nix-based development environment framework and studio UI for managing multi-app monorepos. It provides deterministic dev environments, service orchestration, secrets management, IDE integration, and a web-based studio for visualizing and controlling everything.

## Runtime Architecture

The system has three runtime planes:

1. **Nix plane** -- Evaluates configuration, computes ports, provisions the devshell, generates files. Runs once on shell entry.
2. **Go agent plane** -- A localhost HTTP server (default port 9876) that bridges the web UI to the local Nix environment. Provides REST + Connect-RPC APIs, SSE events, file watching, and process management.
3. **Web plane** -- A React (TanStack Start) application that serves as the studio UI. Communicates with the cloud API via tRPC and with the local Go agent via HTTP REST + Connect-RPC.

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

## Nix Module System

### Core Design: Adapter-Agnostic Core + Thin Adapters

All stack logic lives in `nix/stack/` and has zero dependency on devenv, NixOS, or any other module system. Adapters translate the core outputs to their target:

- `nix/flake/default.nix` -- flake-parts adapter: `lib.evalModules` with core, then `pkgs.mkShell`
- `nix/flake/modules/devenv.nix` -- devenv adapter: maps `stack.devshell.*` to devenv's outputs
- `nix/flake/devenv.nix` -- standalone devenv adapter

### Import Flow

```
User's flake.nix
  -> imports flakeModules.default (nix/flake/default.nix)
    -> auto-loads .stack/_internal.nix (merges config.nix + data/*.nix + overrides)
    -> lib.evalModules with nix/stack/ (the core)
    -> optionally imports .stack/devenv.nix into devenv.shells.default
    -> creates devShells.default via pkgs.mkShell
```

### Option Namespaces

All options are under `options.stack.*`:

| Namespace | Purpose |
|---|---|
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

### Key Module Directories

```
nix/stack/
  core/              # Options definitions (30+ files), CLI invocation, state, utilities
  core/options/      # ALL option definitions (the schema)
  core/services/     # Service computation (mkGlobalServices)
  devshell/          # Shell subsystem (scripts, files, codegen, bin wrappers)
  network/           # Step CA certificates, port env vars
  services/          # Service implementations (postgres, redis, caddy, aws, binary-cache)
  secrets/           # Master-key encryption (agenix, SOPS, combined)
  ide/               # VS Code and Zed file generation
  modules/           # Auto-discovered directory modules (process-compose, go, bun, oxlint, turbo, git-hooks)
  db/                # Proto-based schema system (.proto.nix -> Nix options + Go/TS types)
  lib/               # Pure library functions (ports, IDE, theme, serialization, service helpers)
  apps/              # App-level features and CI
  tui/               # Terminal UI theme
  packages/          # Nix package definitions (stack-cli)
```

### Extensibility Patterns

- **appModules**: Modules inject per-app options. Go module adds `app.go.*`, process-compose adds `app.process-compose.*`, OxLint adds `app.linting.oxlint.*`.
- **serviceModules**: Modules inject per-service options. Process-compose adds readiness probes, namespaces.
- **Directory modules** (`nix/stack/modules/`): Auto-discovered. Each has `meta.nix` (pure data), `module.nix` (options + config), `ui.nix` (UI panel definitions).

### Proto-Nix Schema System

`.proto.nix` files in `nix/stack/db/schemas/` serve as single source of truth. They generate: Nix module options, Go types (protobuf), TypeScript types, and JSON schemas from one definition.

## Deterministic Port System

Ports are computed from the project name hash, ensuring identical ports across all team members without manual configuration:

1. Hash project name with MD5
2. Convert first 8 hex chars to decimal
3. Constrain to range `[3000, 65000)`, round to nearest 100
4. Apps get sequential ports at `base + 0-9`
5. Services get stable ports via `hash(projectName + serviceName)` within the project's port range

Environment variables: `STACKPANEL_<KEY>_PORT` (e.g., `STACKPANEL_POSTGRES_PORT=6410`).

## Application Architecture

### apps/web/ -- Studio UI (React)

- **Framework**: TanStack Start (SSR-capable React) + Vite + Cloudflare Workers
- **Router**: TanStack Router with file-based routing
- **State**: TanStack Query with SuperJSON serialization
- **Cloud API**: tRPC via `@stack/api` -- server uses `localLink` (in-process), client uses `httpBatchStreamLink`
- **Agent API**: Dual protocol -- HTTP REST (`AgentHttpClient`, 1244 lines) and Connect-RPC (proto-generated hooks, 1499 lines)
- **Auth**: Better-Auth client with JWT session management
- **UI**: Radix UI primitives + shadcn components + Tailwind CSS v4

Key routes:
- `/` -- Landing page
- `/login` -- Auth (Better-Auth)
- `/dashboard` -- Authenticated dashboard
- `/studio/*` -- Main app (20+ sub-routes): wraps in `AgentProvider > AgentSSEProvider > ProjectProvider > SidebarProvider`

Agent connection pattern:
1. `AgentProvider` manages JWT pairing via popup, stores token in localStorage, polls health
2. `AgentSSEProvider` maintains EventSource to `/api/events` for real-time config changes
3. `ProjectProvider` manages multi-project selection with `X-Stack-Project` header

### apps/stack-go/ -- CLI + Agent (Go)

Single Go binary with two modes:

**CLI** (Cobra commands):
- `stack` -- Interactive TUI navigator (default)
- `stack services {start,stop,status,restart,logs}` -- Service management
- `stack caddy {start,stop,status,add,remove}` -- Reverse proxy
- `stack status` -- Status dashboard
- `stack agent` -- Start the HTTP agent server
- `stack init` -- Initialize from Nix config (called by Nix shell entry)
- `stack commands`, `users`, `env`, `vars`, `ports`, `scaffold`, `motd`, `gendocs`, `logs`, `project`

**Agent** (localhost HTTP server, port 9876):
- JWT auth via popup pairing flow
- CORS middleware for web UI
- SSE event broadcasting on config changes
- File watching (fsnotify) + FlakeWatcher (`.#stackpanelConfig`)
- ShellManager for devshell state tracking
- 60+ REST API endpoints organized by domain: project, nix, files, secrets, security, nixpkgs, SST, process-compose, modules, registry
- Connect-RPC service endpoint for proto-generated typed API

**TUI**: Charmbracelet stack (Bubble Tea, Lip Gloss, Glamour)

### apps/docs/ -- Documentation Site

- **Framework**: Next.js 16 with Fumadocs (static export for Cloudflare)
- **Content**: MDX in `content/docs/` -- guides, reference (auto-generated from Nix options), CLI docs (auto-generated)
- Auto-generation: Go CLI `gendocs` command evaluates Nix options and Cobra commands to produce MDX

### apps/tui/ -- OpenTUI Experiment

Early-stage React-based terminal UI using OpenTUI. Separate from the Go Charmbracelet TUI.

## Package Architecture

### Dependency Chain

```
apps/web
  -> @stack/api (tRPC routers + types)
     -> @stack/auth (Better Auth + Polar payments)
        -> @stack/db (Drizzle ORM + Neon PostgreSQL)
        -> @gen/env (generated env package)
     -> @stack/db
  -> @stack/agent-client -> @stack/proto (Connect-RPC types)
  -> @stack/ui -> @stack/ui-web -> @stack/ui-core + @stack/ui-primitives (Radix)
```

### Key Packages

| Package | Purpose |
|---|---|
| `@stack/api` | tRPC routers (agent, github). Creates context with `{ authApi, session, db }`. Defines `publicProcedure` and `protectedProcedure`. |
| `@stack/auth` | Better Auth with Drizzle adapter, email/password, Polar payments plugin. |
| `@stack/db` | Drizzle ORM with Neon serverless PostgreSQL. Auth schema (user, session, account, verification). |
| `@gen/env` | Generated, type-safe env package. Per-app/per-env codegen from Nix with app exports like `@gen/env/web`, a runtime loader under `src/entrypoints/`, and embedded encrypted payloads in `src/embedded-data.ts`. |
| `@stack/proto` | 23+ protobuf modules for agent communication. Generated Go + TypeScript types. |
| `@stack/agent-client` | Connect-RPC client factory with JWT interceptor. |
| `@stack/ui` | Facade: re-exports ui-web (or ui-native) + ui-core utilities. |
| `@stack/ui-web` | 16 shadcn-style components (Button, Card, Dialog, etc.) using Radix + Tailwind. |
| `@stack/ui-primitives` | Thin re-export of 27 Radix UI packages. |
| `@stack/ui-core` | `cn()` utility, `cva`, `clsx`, `twMerge`, Logo component. |
| `@stack/scripts` | Shell scripts for app orchestration: entrypoint.sh, devshell detection, secret loading (AGE + vals + chamber). |
| `@stack/docs-content` | Raw MDX guide content, importable as strings. |
| `@stack/infra` | SST IaC: GitHub OIDC, IAM roles, KMS keys for secrets. |
| `znv` | Vendored Zod-based env parser (`parseEnv()`). |

### Export Convention

All packages use the `exports` field with `.` and `./*` patterns. Source TypeScript is exported directly (no build step) -- bundlers handle transpilation. Internal dependencies use `workspace:*`.

## Secrets Architecture

Two-layer system:

1. **Local AGE identity**: Auto-generated on shell entry at `.stack/keys/local.txt` for SOPS decryption.
2. **SOPS-encrypted YAML**: Secret files live in `.stack/secrets/vars/*.sops.yaml` and use `# safe` / `# plaintext` comments for unencrypted values.

Codegen: Nix generates the env package under `packages/gen/env/src/`, including typed TypeScript modules, embedded encrypted payloads, and runtime loaders.

Runtime resolution chain: `secrets:env` script -> AGE decryption -> vals (SSM/Vault/SOPS) -> env files -> chamber (AWS SSM).

## .stack/ Configuration

### Files

| Path | Purpose |
|---|---|
| `config.nix` | Primary user-editable config (apps, services, users, theme, IDE, AWS, Step CA) |
| `_internal.nix` | Merge point: data/*.nix + config.nix + GitHub collaborators + local overrides |
| `devenv.nix` | Devenv-specific: languages, packages, git-hooks |
| `config.local.nix` | Per-user gitignored overrides |
| `data/*.nix` | Auto-loaded data tables (apps, variables, secrets, sst, aws, ide, theme, tasks, commands, users, step-ca, packages) |
| `modules/default.nix` | User extension modules |
| `secrets/` | SOPS config, encrypted YAML files, AGE keys |

### State and Generated Files (runtime)

| Path | Purpose |
|---|---|
| `state/stack.json` | Runtime state: evaluated apps, services, ports, URLs, extensions |
| `state/shellhook.sh` | Generated shell hook |
| `state/starship.toml` | Generated prompt config |
| `state/keys/` | Local AGE key pair |
| `state/step/` | Device certificates |
| `gen/config.json` | Full evaluated Nix config as JSON |
| `gen/ide/vscode/` | VS Code workspace + devshell loader |
| `gen/zed/` | Zed settings + devshell loader |

### Config Priority Order

1. `data/*.nix` (defaults)
2. `config.nix` (user config)
3. `external/github-collaborators.nix` (auto-synced)
4. `config.local.nix` (gitignored overrides)
5. `STACKPANEL_CONFIG_OVERRIDE` env var (CI)

## Shell Hook Lifecycle

Strict phase ordering on devshell entry:

```
hooks.before
  -> Clean aliases, set strict mode
  -> Path utilities + root resolution
  -> Directory creation (state/, gen/)
  -> Marker file + .gitignore
  -> CLI init: stack init --config '${configJson}'
  -> State file generation
  -> Auto-generate local master key
  -> Shell hash computation

hooks.main
  -> Service shell hooks
  -> Caddy site registration
  -> Step CA interactive setup

hooks.after
  -> Module init confirmation
  -> MOTD display
  -> Port information
  -> Alias setup (sp, spx, x)
```

## Build and Deploy

- **Monorepo orchestration**: Turborepo (JS/TS tasks) + Nix (dev environment)
- **Package manager**: Bun with workspaces
- **Web deployment**: Cloudflare Workers via Alchemy + Vite Cloudflare plugin
- **Docs deployment**: Static export to Cloudflare
- **Infrastructure**: SST + Pulumi (AWS OIDC, KMS, IAM)
- **Go build**: `gomod2nix` for Nix, `air` for hot reload in dev
- **CI**: GitHub Actions with OIDC-based AWS access

## Key Conventions

- Nix modules implement behavior once in `nix/stack/lib/`, called from thin adapter modules
- The Go CLI is the single writer for generated files (avoids symlink issues, ensures atomicity)
- Proto definitions in `packages/proto/` are the contract between Go agent and TypeScript web app
- Environment variables follow the pattern `STACKPANEL_<KEY>_<PROPERTY>` (e.g., `STACKPANEL_POSTGRES_PORT`)
- All user-editable config uses YAML/Nix with JSON Schema validation for IDE intellisense



<!-- Source: .ruler/bts.md -->

# Better-T-Stack Project Rules

This is a stack project created with Better-T-Stack CLI.

## Project Structure

This is a monorepo with the following structure:

- **`apps/web/`** - Frontend application (React with TanStack Router)

- **`apps/server/`** - Backend server (Hono)

- **`packages/api/`** - Shared API logic and types

- **`packages/auth/`** - Authentication logic and utilities

- **`packages/db/`** - Database schema and utilities

## Available Scripts

- `bun run dev` - Start all apps in development mode
- `bun run dev:web` - Start only the web app
- `bun run dev:server` - Start only the server

## Database Commands

All database operations should be run from the server workspace:

- `bun run db:push` - Push schema changes to database
- `bun run db:studio` - Open database studio
- `bun run db:generate` - Generate Prisma files
- `bun run db:migrate` - Run database migrations

Database schema is located in `apps/server/prisma/schema.prisma`

## API Structure

- tRPC routers are in `apps/server/src/routers/`
- Client-side tRPC utils are in `apps/web/src/utils/trpc.ts`

## Authentication

Authentication is enabled in this project:

- Server auth logic is in `apps/server/src/lib/auth.ts`
- Web app auth client is in `apps/web/src/lib/auth-client.ts`

## Adding More Features

You can add additional addons or deployment options to your project using:

```bash
bunx create-better-t-stack
add
```

Available addons you can add:

- **Documentation**: Starlight, Fumadocs
- **Linting**: Biome, Oxlint, Ultracite
- **Other**: Ruler, Turborepo, PWA, Tauri, Husky

You can also add web deployment configurations like Cloudflare Workers support.

## Project Configuration

This project includes a `bts.jsonc` configuration file that stores your Better-T-Stack settings:

- Contains your selected stack configuration (database, ORM, backend, frontend, etc.)
- Used by the CLI to understand your project structure
- Safe to delete if not needed
- Updated automatically when using the `add` command

## Key Points

- This is a Turborepo monorepo using bun workspaces
- Each app has its own `package.json` and dependencies
- Run commands from the root to execute across all workspaces
- Run workspace-specific commands with `bun run command-name`
- Turborepo handles build caching and parallel execution
- Use `bunx create-better-t-stack add` to add more features later



<!-- Source: .ruler/development.md -->

# Development Guidelines

- To enter the devshell: `nix develop --impure`
- Run ALL commands in the nix shell otherwise you will be using the wrong binaries.
- After you finish a task, ALWAYS try entering the devshell either by using the `devshell` script or `nix develop --impure`
- Do NOT assume `devenv shell` will be used.



<!-- Source: .ruler/stack.md -->

# Stack Project Rules

Stack is a Nix-based development environment framework that provides:

- **Consistent dev environments** via devenv/Nix with reproducible shells
- **Multi-app monorepo support** with automatic port assignment and Caddy reverse proxy
- **Secrets management** with SOPS/vals integration and per-app codegen
- **IDE integration** with VS Code workspace generation
- **Service orchestration** for PostgreSQL, Redis, Minio, etc.

## Directory Layout

```
.
├── .stack/                    # Stack configuration (checked in)
│   ├── .gitignore                  # Ignores state/ only
│   ├── gen/                        # Generated files (checked in, regenerated on devenv)
│   │   ├── ide/vscode/             # VS Code workspace and devshell loader
│   │   └── schemas/secrets/        # JSON schemas for YAML intellisense
│   ├── secrets/                    # Secrets configuration
│   │   ├── config.yaml             # Global secrets settings
│   │   ├── users.yaml              # Team members and AGE keys
│   │   └── apps/{appName}/         # Per-app secret schemas
│   │       ├── config.yaml         # Codegen settings (language, path)
│   │       ├── common.yaml         # Shared schema across environments
│   │       ├── dev.yaml            # Dev-specific schema + access
│   │       ├── staging.yaml        # Staging-specific schema + access
│   │       └── prod.yaml           # Production-specific schema + access
│   └── state/                      # Runtime state (gitignored)
│       └── stack.json         # State file for CLI/agent
│
├── apps/                           # Application packages
│   ├── web/                        # React frontend (TanStack Router)
│   ├── server/                     # Hono backend (Cloudflare Workers)
│   ├── fumadocs/                   # Documentation site
│   ├── cli/                        # Go CLI for service management
│   └── agent/                      # Go agent for remote operations
│
├── packages/                       # Shared packages
│   ├── api/                        # tRPC routers and types
│   ├── auth/                       # Better-Auth logic
│   ├── db/                         # Drizzle schema and utilities
│   ├── ui/                         # Shared UI components
│   └── config/                     # Shared TypeScript config
│
├── nix/                            # Nix modules and libraries
│   ├── modules/                    # Stack modules (options + config)
│   │   ├── stack.nix          # Core module (dirs, motd, direnv)
│   │   ├── apps.nix                # App definitions and port assignment
│   │   ├── ports.nix               # Deterministic port allocation
│   │   ├── ide.nix                 # VS Code integration
│   │   ├── secrets/                # SOPS/vals secrets module
│   │   │   ├── secrets.nix         # Main secrets module
│   │   │   ├── codegen.nix         # TypeScript/Python/Go env codegen
│   │   │   ├── schemas.nix         # JSON schema generation
│   │   │   └── ...
│   │   └── ...
│   ├── lib/                        # Pure library functions
│   │   ├── services/               # Service helpers (postgres, redis, minio)
│   │   └── integrations/           # IDE integration utilities
│   └── templates/                  # Project templates
│
├── tooling/                        # Build tooling
│   ├── alchemy/                    # Alchemy IaC scripts
│   └── devenv/                     # Additional devenv config
│
├── devenv.nix                      # Main devenv configuration
├── devenv.yaml                     # Devenv inputs
└── flake.nix                       # Nix flake for flake-parts integration
```

## Key Concepts

### Ports

Stack assigns deterministic ports based on a hash of the project name, ensuring each project gets a unique, predictable port range that won't conflict with other stack projects.

**Computation Algorithm** (in `nix/modules/ports.nix`):

1. Hash the project name using MD5
2. Convert first 8 hex chars to decimal
3. Constrain to range: `minPort + (hash % portRange)`
4. Round down to nearest `modulus` (default 100) for clean port numbers

**Default Parameters**:
- `minPort`: 3000 (minimum base port)
- `maxPort`: 65000 (maximum base port)
- `modulus`: 100 (ports round to nearest 100)

**Port Layout**:
- **Apps** get ports at `basePort + 0-9` (sequential by definition order)
- **Services** get ports at `basePort + 10-99` (sequential by registration order)

**Example** for project `stack`:
```
Base port: 6400

Apps:
  fumadocs  → 6400
  server    → 6401
  web       → 6402

Services:
  postgres  → 6410
  redis     → 6411
  minio     → 6412
```

**Environment Variables**:
Each service port is exposed as `STACKPANEL_<KEY>_PORT`:
```bash
STACKPANEL_POSTGRES_PORT=6410
STACKPANEL_REDIS_PORT=6411
STACKPANEL_MINIO_PORT=6412
```

**Benefits**:
- Same ports across all team members (deterministic from project name)
- No manual port configuration needed
- Projects don't conflict when running simultaneously
- Clean, memorable port numbers (rounded to modulus)

### Secrets

Secrets use a per-app architecture with environment inheritance:
1. `common.yaml` defines schema shared across all environments
2. `{env}.yaml` extends/overrides common schema and defines access control
3. Codegen generates type-safe env access for TypeScript/Python/Go

### Generated Files

Files in `.stack/gen/` are regenerated on each `devenv` run:
- Should be checked into git for IDE functionality without devenv
- JSON schemas enable YAML intellisense in VS Code
- Workspace file configures terminal integration


### State File

The state file (`.stack/state/stack.json`) is generated on each devenv shell entry and provides the Go CLI and agent with access to the current devenv configuration without evaluating Nix.

**Location**: `.stack/state/stack.json` (gitignored)

**Contents**:
```json
{
  "version": 1,
  "projectName": "stack",
  "basePort": 6400,
  "paths": {
    "state": ".stack/state",
    "gen": ".stack/gen",
    "data": ".stack"
  },
  "apps": {
    "web": { "port": 6402, "domain": "stack.localhost", "url": "http://stack.localhost", "tls": false },
    "server": { "port": 6401, "domain": null, "url": null, "tls": false }
  },
  "services": {
    "postgres": { "key": "POSTGRES", "name": "PostgreSQL", "port": 6410, "envVar": "STACKPANEL_POSTGRES_PORT" },
    "redis": { "key": "REDIS", "name": "Redis", "port": 6411, "envVar": "STACKPANEL_REDIS_PORT" }
  },
  "network": {
    "step": { "enable": true, "caUrl": "https://ca.internal:443" }
  }
}
```

### Live Nix Evaluation

For tools that need always-fresh config without state file drift, use `nix eval`:

```bash
# Within devenv shell (uses STACKPANEL_CONFIG_JSON env var for pre-computed JSON)
nix eval --impure --json --expr 'builtins.fromJSON (builtins.readFile (builtins.getEnv "STACKPANEL_CONFIG_JSON"))'

# Or import the source Nix config directly (uses STACKPANEL_NIX_CONFIG)
nix eval --impure --json --expr 'import (builtins.getEnv "STACKPANEL_NIX_CONFIG")'

# Returns same structure as state.json but directly from Nix
```

**Go Usage** (with fallback):
```go
import "github.com/darkmatter/stack/cli/state"

// Load tries nix eval first, falls back to state file
st, err := state.Load("")
if err == nil {
    fmt.Println("Project:", st.ProjectName)
    fmt.Println("Postgres port:", st.GetServicePort("postgres"))
}

// Force state file only (skip nix eval)
st, err := state.Load("", state.WithNixEval(false))
}
```

**Environment Variables**:
- `STACKPANEL_STATE_FILE`: Full path to state file
- `STACKPANEL_STATE_DIR`: Directory containing state file

## Development Workflow

```bash
# Enter development shell
nix develop --impure  # or: direnv allow (with .envrc)

# Start all dev processes (web, docs, server, etc.)
dev                    # Uses process-compose

# Individual commands
bun install            # Install dependencies
bun run dev            # Start dev servers
stack status      # Check service status
stack services start  # Start PostgreSQL, Redis, etc.
```

## Nix Module Guidelines

When creating or modifying Nix modules:

1. **Options go in `options.stack.*`** - Follow the existing pattern
2. **Use `lib.mkOption` with descriptions** - Document all options
3. **Config uses `lib.mkIf cfg.enable`** - Guard config blocks
4. **File generation via CLI** - Add data to `cli-generate.nix` config, not `devenv.files`
5. **Library functions go in `nix/lib/`** - Keep modules focused on options/config

### CLI-Based Generation

When adding new generated files:

1. Add the data to `fullConfig` in `nix/modules/cli-generate.nix`
2. Add generation logic in `apps/cli/generator/generator.go`
3. The CLI handles writing real files (avoiding symlink issues)

## YAML Configuration

All user-editable config files use YAML with JSON Schema validation:
- Schemas are generated from Nix in `.stack/gen/schemas/`
- VS Code workspace maps schemas to file patterns
- Install the Red Hat YAML extension for intellisense

## Docs

The docs for stack are in apps/docs/content - ALWAYS give the docs a quick scan so that you understand stack.



<!-- Source: .ruler/todo.md -->

## Nix refactor plan: shared core + thin adapters

### Goal
- **Primary entrypoint**: `nix develop --impure` (or `direnv allow`)
- **Devenv compatibility**: Stack modules work in devenv.shells for external users
- Make it **obvious** what is:
  - **core logic** (reusable)
  - **module adapter** (options + wiring)
- Remove duplication between modules and libraries.

### Current layout (achieved)
- **`nix/stack/lib/`**: shared behavior (pure-ish functions for ports, theme, IDE, services, etc.)
- **`nix/stack/core/`**: core schema, state, CLI integration
- **`nix/stack/modules/`**: thin adapters (options + wiring for bun, go, turbo, git-hooks, process-compose)
- **`nix/stack/services/`**: service modules (aws, caddy, global-services, binary-cache)
- **`nix/stack/network/`**: network modules (ports, step-ca)
- **`nix/stack/ide/`**: IDE integration (vscode)
- **`nix/stack/secrets/`**: secrets management (agenix, schemas, codegen)
- **Entrypoints**
  - `nix/stack/default.nix`: main module aggregator
  - `nix/flake/devenv.nix`: devenv integration
  - `flake.nix`: exports `flake.lib.*`, `flake.devenvModules.*`

### Principles
- **Single source of truth**: implement behavior once (lib), call it from modules.
- **Modules stay thin**: avoid duplicating computation.
- **Purity by default**: impure reads must be explicit and optional.
- **Compatibility**: prefer shims/deprecations over breaking moves.

---

## Todo list

### Completed
- [x] Create shared core for global services: `nix/stack/services/global-services.nix`
- [x] Ports module with deterministic port computation: `nix/stack/network/ports.nix`
- [x] Caddy module: `nix/stack/services/caddy.nix`
- [x] Network / Step CA: `nix/stack/network/network.nix`
- [x] AWS Roles Anywhere: `nix/stack/services/aws.nix`
- [x] Theme / starship: `nix/stack/lib/theme.nix`
- [x] IDE integration: `nix/stack/ide/ide.nix`
- [x] Secrets management: `nix/stack/secrets/`
- [x] SST infrastructure module: `nix/stack/sst/sst.nix`
- [x] Process-compose: `nix/stack/modules/process-compose.nix`
- [x] Git hooks: `nix/stack/modules/git-hooks.nix`
- [x] CLI state integration: `nix/stack/core/state.nix`

### Optional (high-leverage)
- [ ] Centralize shared option types/defaults in `nix/stack/core/options/` so both adapters share one schema.
- [ ] Update docs to recommend `nix/stack` import path everywhere.

---

## Architecture (Current)

The codebase follows a consistent pattern:
1. **Libraries** (`nix/stack/lib/*.nix`): Pure functions that implement behavior
2. **Core** (`nix/stack/core/*.nix`): Schema definitions, state management, CLI integration
3. **Modules** (`nix/stack/modules/*.nix`): Thin adapters for specific tooling (bun, go, turbo, etc.)
4. **Services** (`nix/stack/services/*.nix`): Service-specific modules (aws, caddy, global-services)
5. **Network** (`nix/stack/network/*.nix`): Networking modules (ports, step-ca)
6. **IDE** (`nix/stack/ide/*.nix`): IDE integration (vscode workspace, terminal profiles)
7. **Secrets** (`nix/stack/secrets/*.nix`): Secrets management (agenix, schemas, wrapped)

<!-- BEGIN BEADS INTEGRATION v:1 profile:full hash:f65d5d33 -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Dolt-powered version control with native sync
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update <id> --claim --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task atomically**: `bd update <id> --claim`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Quality
- Use `--acceptance` and `--design` fields when creating issues
- Use `--validate` to check description completeness

### Lifecycle
- `bd defer <id>` / `bd supersede <id>` for issue management
- `bd stale` / `bd orphans` / `bd lint` for hygiene
- `bd human <id>` to flag for human decisions
- `bd formula list` / `bd mol pour <name>` for structured workflows

### Auto-Sync

bd automatically syncs via Dolt:

- Each write auto-commits to Dolt history
- Use `bd dolt push`/`bd dolt pull` for remote sync
- No manual export/import needed!

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- END BEADS INTEGRATION -->

<!--VITE PLUS START-->

# Using Vite+, the Unified Toolchain for the Web

This project is using Vite+, a unified toolchain built on top of Vite, Rolldown, Vitest, tsdown, Oxlint, Oxfmt, and Vite Task. Vite+ wraps runtime management, package management, and frontend tooling in a single global CLI called `vp`. Vite+ is distinct from Vite, but it invokes Vite through `vp dev` and `vp build`.

## Vite+ Workflow

`vp` is a global binary that handles the full development lifecycle. Run `vp help` to print a list of commands and `vp <command> --help` for information about a specific command.

### Start

- create - Create a new project from a template
- migrate - Migrate an existing project to Vite+
- config - Configure hooks and agent integration
- staged - Run linters on staged files
- install (`i`) - Install dependencies
- env - Manage Node.js versions

### Develop

- dev - Run the development server
- check - Run format, lint, and TypeScript type checks
- lint - Lint code
- fmt - Format code
- test - Run tests

### Execute

- run - Run monorepo tasks
- exec - Execute a command from local `node_modules/.bin`
- dlx - Execute a package binary without installing it as a dependency
- cache - Manage the task cache

### Build

- build - Build for production
- pack - Build libraries
- preview - Preview production build

### Manage Dependencies

Vite+ automatically detects and wraps the underlying package manager such as pnpm, npm, or Yarn through the `packageManager` field in `package.json` or package manager-specific lockfiles.

- add - Add packages to dependencies
- remove (`rm`, `un`, `uninstall`) - Remove packages from dependencies
- update (`up`) - Update packages to latest versions
- dedupe - Deduplicate dependencies
- outdated - Check for outdated packages
- list (`ls`) - List installed packages
- why (`explain`) - Show why a package is installed
- info (`view`, `show`) - View package information from the registry
- link (`ln`) / unlink - Manage local package links
- pm - Forward a command to the package manager

### Maintain

- upgrade - Update `vp` itself to the latest version

These commands map to their corresponding tools. For example, `vp dev --port 3000` runs Vite's dev server and works the same as Vite. `vp test` runs JavaScript tests through the bundled Vitest. The version of all tools can be checked using `vp --version`. This is useful when researching documentation, features, and bugs.

## Common Pitfalls

- **Using the package manager directly:** Do not use pnpm, npm, or Yarn directly. Vite+ can handle all package manager operations.
- **Always use Vite commands to run tools:** Don't attempt to run `vp vitest` or `vp oxlint`. They do not exist. Use `vp test` and `vp lint` instead.
- **Running scripts:** Vite+ built-in commands (`vp dev`, `vp build`, `vp test`, etc.) always run the Vite+ built-in tool, not any `package.json` script of the same name. To run a custom script that shares a name with a built-in command, use `vp run <script>`. For example, if you have a custom `dev` script that runs multiple services concurrently, run it with `vp run dev`, not `vp dev` (which always starts Vite's dev server).
- **Do not install Vitest, Oxlint, Oxfmt, or tsdown directly:** Vite+ wraps these tools. They must not be installed directly. You cannot upgrade these tools by installing their latest versions. Always use Vite+ commands.
- **Use Vite+ wrappers for one-off binaries:** Use `vp dlx` instead of package-manager-specific `dlx`/`npx` commands.
- **Import JavaScript modules from `vite-plus`:** Instead of importing from `vite` or `vitest`, all modules should be imported from the project's `vite-plus` dependency. For example, `import { defineConfig } from 'vite-plus';` or `import { expect, test, vi } from 'vite-plus/test';`. You must not install `vitest` to import test utilities.
- **Type-Aware Linting:** There is no need to install `oxlint-tsgolint`, `vp lint --type-aware` works out of the box.

## CI Integration

For GitHub Actions, consider using [`voidzero-dev/setup-vp`](https://github.com/voidzero-dev/setup-vp) to replace separate `actions/setup-node`, package-manager setup, cache, and install steps with a single action.

```yaml
- uses: voidzero-dev/setup-vp@v1
  with:
    cache: true
- run: vp check
- run: vp test
```

## Review Checklist for Agents

- [ ] Run `vp install` after pulling remote changes and before getting started.
- [ ] Run `vp check` and `vp test` to validate changes.
<!--VITE PLUS END-->
