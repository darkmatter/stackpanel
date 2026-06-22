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

| Layer           | Technologies                                                          |
| --------------- | --------------------------------------------------------------------- |
| Dev environment | Nix, flake-parts, direnv                                              |
| Config language | Nix (modules, lib functions)                                          |
| Backend Go      | Go 1.25, Cobra, Bubble Tea, Connect-RPC, fsnotify                     |
| Web frontend    | React 19, TanStack Router/Query/Start, Vite, Tailwind v4, Radix UI    |
| Cloud API       | Hono on Cloudflare Workers, tRPC, Better Auth, Drizzle ORM            |
| Database        | Neon PostgreSQL (serverless)                                          |
| Package manager | Bun (workspaces + lockfile)                                           |
| Monorepo        | Turborepo                                                             |
| Deployment      | Cloudflare Workers (web), Colmena/NixOS (server), Alchemy IaC (infra) |
| Issue tracking  | **bd (beads)** — see [Issue Tracking](#issue-tracking-with-bd-beads)  |

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
│   └── flake/             # flake-parts outputs and templates
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

| File                                 | Purpose                                                      |
| ------------------------------------ | ------------------------------------------------------------ |
| `flake.nix`                          | Nix flake: exports devShells, packages, flakeModules, lib    |
| `.stack/config.nix`                  | Main project config: apps, services, users, theme, IDE       |
| `nix/stackpanel/core/options/`       | All `options.stack.*` option definitions                     |
| `nix/stackpanel/lib/`                | Pure Nix library functions (ports, theme, IDE, services)     |
| `apps/stackpanel-go/cmd/`            | Cobra CLI command definitions                                |
| `apps/stackpanel-go/internal/agent/` | Agent HTTP server (60+ endpoints)                            |
| `apps/web/src/routes/`               | TanStack Router file-based routes                            |
| `packages/proto/`                    | Protobuf definitions (source of truth for agent ↔ web types) |
| `packages/gen/env/src/`              | Generated type-safe env (do not edit manually)               |

---

## Essential Commands

> **All commands must be run inside the Nix devshell.** Wrong binaries will be used otherwise.
> Avoid `--impure` by default. Do not add features that require impure Nix
> evaluation. When you find an existing source of impurity, call it out
> explicitly with the file/command and why it is impure.

```bash
# Enter the devshell (required before anything else)
nix develop
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
nix flake check              # Nix flake check (also: just check)
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
bun run db:generate          # Generate a new Drizzle migration after a schema change
                             # (writes packages/db/drizzle/<NNNN>_<name>.sql + bundles for runtime)
bun run db:studio            # Open Drizzle Studio
bun run db:migrate           # Apply migrations against $DATABASE_URL — local/dev only
                             # (production / staging / preview migrate automatically at app
                             # startup via @stackpanel/db's runMigrations(); see
                             # docs/adr/0002-runtime-startup-migrations.md)
```

**Generating a migration**

1. Edit a schema file under `packages/db/src/schema/`.
2. Run `bun run db:generate` (or `bun run --cwd packages/db db:generate` directly).
3. Commit the new SQL file under `packages/db/drizzle/` along with the
   regenerated `packages/db/drizzle/meta/_journal.json` and
   `packages/db/src/migrations-bundle.generated.ts`.
4. Deploy. The first request to a new isolate will apply pending migrations
   transparently — no manual `db:push` step.

### Nix / Infra

```bash
just dev                     # Enter devenv shell
just check                   # nix flake check
just clean-cache             # Wipe nix-direnv cache and reload
just deploy <region>         # Build → publish artifact → Alchemy IaC (EC2/AL2023)
just deploy-nixos            # Build → Cachix push → Alchemy infra → Colmena apply
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

| ❌ Don't                                                 | ✅ Do instead                                                      |
| -------------------------------------------------------- | ------------------------------------------------------------------ |
| Run commands outside the Nix devshell                    | Enter with `nix develop` or `direnv allow` first                   |
| Add features that require `--impure`                     | Keep Nix evaluation pure; call out existing impurity when found    |
| Hardcode port numbers                                    | Read `STACKPANEL_<KEY>_PORT` env vars                              |
| Write directly to `.stack/gen/`                          | Let the Go CLI generator write these files                         |
| Add options directly to `config = {}` without `lib.mkIf` | Guard all config blocks with `lib.mkIf cfg.enable`                 |
| Duplicate computation in both lib and modules            | Implement once in `nix/stackpanel/lib/`, call from modules         |
| Use markdown TODO lists for task tracking                | Use `bd create` (beads) — the only allowed tracker                 |
| Assume `devenv shell` is available                       | Use `nix develop` or `direnv allow` — devenv is not always present |
| Edit `packages/gen/env/src/` manually                    | It's generated — edit the source schemas instead                   |
| Store secrets in plaintext in git                        | Use SOPS-encrypted `.sops.yaml` files                              |
| Mutate `options.stack.*` from outside the framework      | Use the `.stack/config.nix` / `data/*.nix` entry points            |

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
nix flake check        # Nix validity
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
