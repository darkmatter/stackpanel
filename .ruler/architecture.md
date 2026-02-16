# Stackpanel Architecture

## What Stackpanel Is

Stackpanel is a Nix-based development environment framework and studio UI for managing multi-app monorepos. It provides deterministic dev environments, service orchestration, secrets management, IDE integration, and a web-based studio for visualizing and controlling everything.

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

All stackpanel logic lives in `nix/stackpanel/` and has zero dependency on devenv, NixOS, or any other module system. Adapters translate the core outputs to their target:

- `nix/flake/default.nix` -- flake-parts adapter: `lib.evalModules` with core, then `pkgs.mkShell`
- `nix/flake/modules/devenv.nix` -- devenv adapter: maps `stackpanel.devshell.*` to devenv's outputs
- `nix/flake/devenv.nix` -- standalone devenv adapter

### Import Flow

```
User's flake.nix
  -> imports flakeModules.default (nix/flake/default.nix)
    -> auto-loads .stackpanel/_internal.nix (merges config.nix + data/*.nix + overrides)
    -> lib.evalModules with nix/stackpanel/ (the core)
    -> optionally imports .stackpanel/devenv.nix into devenv.shells.default
    -> creates devShells.default via pkgs.mkShell
```

### Option Namespaces

All options are under `options.stackpanel.*`:

| Namespace | Purpose |
|---|---|
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

### Key Module Directories

```
nix/stackpanel/
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
  packages/          # Nix package definitions (stackpanel-cli)
```

### Extensibility Patterns

- **appModules**: Modules inject per-app options. Go module adds `app.go.*`, process-compose adds `app.process-compose.*`, OxLint adds `app.linting.oxlint.*`.
- **serviceModules**: Modules inject per-service options. Process-compose adds readiness probes, namespaces.
- **Directory modules** (`nix/stackpanel/modules/`): Auto-discovered. Each has `meta.nix` (pure data), `module.nix` (options + config), `ui.nix` (UI panel definitions).

### Proto-Nix Schema System

`.proto.nix` files in `nix/stackpanel/db/schemas/` serve as single source of truth. They generate: Nix module options, Go types (protobuf), TypeScript types, and JSON schemas from one definition.

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
- **Cloud API**: tRPC via `@stackpanel/api` -- server uses `localLink` (in-process), client uses `httpBatchStreamLink`
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
3. `ProjectProvider` manages multi-project selection with `X-Stackpanel-Project` header

### apps/stackpanel-go/ -- CLI + Agent (Go)

Single Go binary with two modes:

**CLI** (Cobra commands):
- `stackpanel` -- Interactive TUI navigator (default)
- `stackpanel services {start,stop,status,restart,logs}` -- Service management
- `stackpanel caddy {start,stop,status,add,remove}` -- Reverse proxy
- `stackpanel status` -- Status dashboard
- `stackpanel agent` -- Start the HTTP agent server
- `stackpanel init` -- Initialize from Nix config (called by Nix shell entry)
- `stackpanel commands`, `users`, `env`, `vars`, `ports`, `scaffold`, `motd`, `gendocs`, `logs`, `project`

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
  -> @stackpanel/api (tRPC routers + types)
     -> @stackpanel/auth (Better Auth + Polar payments)
        -> @stackpanel/db (Drizzle ORM + Neon PostgreSQL)
        -> @gen/env (validated env vars)
     -> @stackpanel/db
  -> @stackpanel/agent-client -> @stackpanel/proto (Connect-RPC types)
  -> @stackpanel/ui -> @stackpanel/ui-web -> @stackpanel/ui-core + @stackpanel/ui-primitives (Radix)
```

### Key Packages

| Package | Purpose |
|---|---|
| `@stackpanel/api` | tRPC routers (agent, github). Creates context with `{ authApi, session, db }`. Defines `publicProcedure` and `protectedProcedure`. |
| `@stackpanel/auth` | Better Auth with Drizzle adapter, email/password, Polar payments plugin. |
| `@stackpanel/db` | Drizzle ORM with Neon serverless PostgreSQL. Auth schema (user, session, account, verification). |
| `@gen/env` | Type-safe env vars via Zod schemas. Per-app/per-env codegen from Nix. Multi-entrypoint (web, web-client, web-server, auth, loader). |
| `@stackpanel/proto` | 23+ protobuf modules for agent communication. Generated Go + TypeScript types. |
| `@stackpanel/agent-client` | Connect-RPC client factory with JWT interceptor. |
| `@stackpanel/ui` | Facade: re-exports ui-web (or ui-native) + ui-core utilities. |
| `@stackpanel/ui-web` | 16 shadcn-style components (Button, Card, Dialog, etc.) using Radix + Tailwind. |
| `@stackpanel/ui-primitives` | Thin re-export of 27 Radix UI packages. |
| `@stackpanel/ui-core` | `cn()` utility, `cva`, `clsx`, `twMerge`, Logo component. |
| `@stackpanel/scripts` | Shell scripts for app orchestration: entrypoint.sh, devshell detection, secret loading (AGE + vals + chamber). |
| `@stackpanel/docs-content` | Raw MDX guide content, importable as strings. |
| `@stackpanel/infra` | SST IaC: GitHub OIDC, IAM roles, KMS keys for secrets. |
| `znv` | Vendored Zod-based env parser (`parseEnv()`). |

### Export Convention

All packages use the `exports` field with `.` and `./*` patterns. Source TypeScript is exported directly (no build step) -- bundlers handle transpilation. Internal dependencies use `workspace:*`.

## Secrets Architecture

Three-tier system:

1. **Master keys**: AGE-encrypted master keys (local auto-generated, team-shared). Local key at `.stackpanel/state/keys/`.
2. **SOPS-encrypted YAML**: Per-environment files (`dev.yaml`, `staging.yaml`, `prod.yaml`) + `vars.yaml` (plaintext shared config).
3. **Group keys**: Per-group `.enc.age` files encrypted to all team recipients. Decrypted at runtime for secret access.

Key directories:
- `.stackpanel/secrets/keys/recipients/` -- AGE public keys per team member (committed, auto-registered on shell entry)
- `.stackpanel/secrets/keys/*.enc.age` -- SOPS-encrypted group private keys (committed, encrypted to all recipients)
- `.stackpanel/secrets/keys/.sops.yaml` -- Auto-generated from all `recipients/*.pub` files
- `.stackpanel/secrets/groups/.sops.yaml` -- GENERATED at shell entry from `config.nix` group keys (gitignored, never committed)

Key integrity: `config.nix` is the single source of truth for group public keys. A wrapped SOPS binary resolves group pubkeys from Nix at build time (injects `--age` per file), and `groups/.sops.yaml` is generated as a fallback. This eliminates key drift between config files.

Team onboarding: self-service via Git push. New member enters devshell -> pub key registered in `recipients/` -> push triggers GitHub Actions rekey workflow -> `.enc.age` files re-encrypted for all recipients -> pull to access secrets. Group private keys stored as GitHub Actions secrets (`SECRETS_AGE_KEY_<GROUP>`).

Codegen: Nix generates typed TypeScript env modules in `packages/env/src/generated/` per app per environment.

Runtime resolution chain: `secrets:env` script -> AGE decryption -> vals (SSM/Vault/SOPS) -> env files -> chamber (AWS SSM).

## .stackpanel/ Configuration

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
| `state/stackpanel.json` | Runtime state: evaluated apps, services, ports, URLs, extensions |
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
  -> CLI init: stackpanel init --config '${configJson}'
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

- Nix modules implement behavior once in `nix/stackpanel/lib/`, called from thin adapter modules
- The Go CLI is the single writer for generated files (avoids symlink issues, ensures atomicity)
- Proto definitions in `packages/proto/` are the contract between Go agent and TypeScript web app
- Environment variables follow the pattern `STACKPANEL_<KEY>_<PROPERTY>` (e.g., `STACKPANEL_POSTGRES_PORT`)
- All user-editable config uses YAML/Nix with JSON Schema validation for IDE intellisense

## Change Propagation

When modifying any part of the system, you must propagate changes to all affected layers. Stackpanel is a full-stack system where Nix modules, Go CLI, TypeScript packages, codegen, templates, UI, and docs are tightly coupled. A change in one layer almost always requires updates in others.

### Propagation Matrix

Use this matrix to identify what else needs updating when you change something:

| What Changed | Also Update |
|---|---|
| **Nix module options** | Proto schema if the option feeds into types, Go CLI if it reads the option, `@gen/env` codegen templates if it's an env var, docs content (`apps/docs/`), module `ui.nix` if it should appear in Studio, module `meta.nix` if metadata changed |
| **Proto schema (`.proto.nix`)** | Run `packages/proto/generate.sh` to regenerate Go + TS types, update any Go/TS code consuming the changed types, update UI components displaying the data |
| **Go CLI command** | Doc generation templates (`apps/stackpanel-go/internal/docgen/`), docs site content (`apps/docs/`), `meta.nix` if the command relates to a module |
| **Go agent API endpoint** | TypeScript agent client (`packages/agent-client/`), UI components consuming the endpoint (`apps/web/`), tRPC routers if proxied (`packages/api/`) |
| **UI component** | Ensure proto types are current, check if the component is used in Studio module panels (`ui.nix` references) |
| **Nix service module** | Port allocation in `network/`, process-compose config, env var exports, codegen templates, docs, Studio UI panel |
| **Flake template** | Update ALL template variants (`default/`, `minimal/`, `devenv/`), run template tests (`tests/`), update docs if user-facing behavior changed |
| **Codegen template** | Re-run the relevant generation script, verify generated output compiles/type-checks, update tests |
| **Package public API** | Check all downstream consumers in the dependency chain, update re-exports in `packages/ui/` if it's a UI package |
| **Secrets / SOPS config** | Update `.stackpanel/secrets/` schema, verify group key derivation, check env var propagation |
| **Database schema** | Update proto schema, regenerate types, update Drizzle schema (`packages/db/`), run migrations |
| **Docs content** | Verify code examples are current, check cross-references to other doc pages |
| **Config schema (YAML/JSON Schema)** | Update validation schemas, Nix option types, docs, and any Go/TS code that parses the config |

### Workflow Checklist

When completing any task, verify the following before considering it done:

1. **Types are current**: If you changed a schema or data structure, regenerate types (`packages/proto/generate.sh`, `nix/stackpanel/core/generate-types.sh`)
2. **Codegen is current**: If you changed Nix options or templates, re-run the relevant codegen and verify output
3. **UI reflects changes**: If you changed a module's behavior or options, update `ui.nix` and any Studio components
4. **Docs are updated**: If you changed user-facing behavior, update `apps/docs/` content and any relevant `docs/` files
5. **Templates are consistent**: If you changed project structure or defaults, update all flake templates
6. **Tests pass**: Run `bun run test` / `turbo test` and verify nothing is broken by the change
7. **Devshell builds**: Enter `nix develop --impure` to verify the Nix evaluation still succeeds
