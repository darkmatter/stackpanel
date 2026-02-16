# Stackpanel Project Rules

Stackpanel is a Nix-based development environment framework that provides:

- **Consistent dev environments** via Nix flakes with reproducible shells
- **Multi-app monorepo support** with automatic port assignment and Caddy reverse proxy
- **Secrets management** with SOPS/vals integration and per-app codegen
- **IDE integration** with VS Code workspace generation
- **Service orchestration** for PostgreSQL, Redis, Minio, etc.

## Directory Layout

```
.
├── .stackpanel/                    # Stackpanel configuration (checked in)
│   ├── .gitignore                  # Ignores state/ only
│   ├── config.nix                  # User-facing Nix config
│   ├── _internal.nix               # Internal Nix config (generated)
│   ├── modules/                    # Project-local Nix modules
│   ├── data/                       # Data files for Nix evaluation
│   ├── gen/                        # Generated files (checked in, regenerated on shell entry)
│   │   ├── ide/vscode/             # VS Code workspace and devshell loader
│   │   └── schemas/secrets/        # JSON schemas for YAML intellisense
│   ├── secrets/                    # Secrets configuration
│   │   ├── config.yaml             # Global secrets settings
│   │   ├── users.yaml              # Team members and AGE keys
│   │   └── apps/{appName}/         # Per-app secret schemas
│   │       ├── config.yaml         # Codegen settings (language, path)
│   │       ├── common.yaml         # Shared schema across environments
│   │       └── {env}.yaml          # Per-environment schema + access
│   └── state/                      # Runtime state (gitignored)
│       └── stackpanel.json         # State file for CLI/agent
│
├── apps/                           # Application packages
│   ├── web/                        # Studio UI (React + TanStack Start + Vite + Cloudflare Workers)
│   ├── stackpanel-go/              # Go CLI + agent (Cobra commands, agent server)
│   ├── docs/                       # Documentation site (Next.js + Fumadocs)
│   └── tui/                        # Terminal UI (TypeScript/Bun)
│
├── packages/                       # Shared packages
│   ├── api/                        # tRPC routers and types
│   ├── auth/                       # Better-Auth logic
│   ├── db/                         # Drizzle schema and utilities
│   ├── proto/                      # Protobuf definitions + codegen (buf-based)
│   ├── gen/                        # Generated code (e.g. @gen/env)
│   ├── ui/                         # Shared UI component re-export layer
│   ├── ui-core/                    # Cross-platform UI primitives
│   ├── ui-web/                     # Web-specific UI components (shadcn/ui)
│   ├── ui-native/                  # Native/mobile UI components
│   ├── ui-primitives/              # Low-level UI primitives
│   ├── config/                     # Shared TypeScript config
│   ├── scripts/                    # Shared scripts and entrypoints
│   ├── secrets/                    # Secrets management
│   ├── infra/                      # Infrastructure-as-code package
│   ├── agent-client/               # Client library for the Go agent
│   ├── znv/                        # Environment variable validation (Zod)
│   └── docs-content/               # Shared documentation content
│
├── nix/                            # Nix modules and libraries
│   ├── stackpanel/                 # Core framework
│   │   ├── core/                   # Core options, schema, state, CLI, aliases
│   │   ├── lib/                    # Utility functions, port management, codegen
│   │   ├── modules/                # Pluggable feature modules (bun, go, turbo, etc.)
│   │   ├── services/               # Service modules (postgres, redis, caddy, minio, etc.)
│   │   ├── devshell/               # Dev shell config (bin, scripts, direnv, files)
│   │   ├── db/                     # Database schemas (.proto.nix files)
│   │   ├── secrets/                # Secrets module
│   │   ├── network/                # Network (ports, caddy, Step CA)
│   │   ├── ide/                    # IDE integration (VS Code, Zed, nixd)
│   │   ├── alchemy/                # Alchemy IaC integration + templates
│   │   ├── infra/                  # Infrastructure codegen + templates
│   │   ├── tui/                    # TUI Nix config and theming
│   │   └── docs/                   # Docs module
│   └── flake/                      # Flake-level config and project templates
│
├── docs/                           # Internal developer documentation
├── infra/                          # Cloud infrastructure (Alchemy/SST scripts)
├── scripts/                        # Shell scripts (setup, wrappers)
├── tests/                          # Smoke tests and template tests
└── flake.nix                       # Nix flake (primary entrypoint)
```

## Key Concepts

### State File

The state file (`.stackpanel/state/stackpanel.json`) is generated on each devshell entry and provides the Go CLI and agent with access to the current configuration without evaluating Nix.

**Location**: `.stackpanel/state/stackpanel.json` (gitignored)

**Go Usage** (with fallback):
```go
// Load tries nix eval first, falls back to state file
st, err := state.Load("")
```

**Environment Variables**:
- `STACKPANEL_STATE_FILE`: Full path to state file
- `STACKPANEL_STATE_DIR`: Directory containing state file

### Live Nix Evaluation

For tools that need always-fresh config without state file drift, use `nix eval`:

```bash
# Within devshell (uses STACKPANEL_CONFIG_JSON env var for pre-computed JSON)
nix eval --impure --json --expr 'builtins.fromJSON (builtins.readFile (builtins.getEnv "STACKPANEL_CONFIG_JSON"))'

# Or import the source Nix config directly (uses STACKPANEL_NIX_CONFIG)
nix eval --impure --json --expr 'import (builtins.getEnv "STACKPANEL_NIX_CONFIG")'
```

## Development Workflow

```bash
# Enter development shell
nix develop --impure  # or: direnv allow (with .envrc)

# Start all dev processes (web, docs, server, etc.)
dev                    # Uses process-compose

# Individual commands
bun install            # Install dependencies
bun run dev            # Start dev servers
stackpanel status      # Check service status
stackpanel services start  # Start PostgreSQL, Redis, etc.
```

## Nix Module Guidelines

When creating or modifying Nix modules in `nix/stackpanel/`:

1. **Options go in `options.stackpanel.*`** - Follow the existing pattern
2. **Use `lib.mkOption` with descriptions** - Document all options
3. **Config uses `lib.mkIf cfg.enable`** - Guard config blocks
4. **File generation via `stackpanel.files.entries`** - See nix-templating.md for patterns
5. **Library functions go in `nix/stackpanel/lib/`** - Keep modules focused on options/config
6. **Follow the module convention** - Each module gets `default.nix`, `module.nix`, `ui.nix`, `meta.nix` (see `nix/stackpanel/modules/_template/`)

## YAML Configuration

All user-editable config files use YAML with JSON Schema validation:
- Schemas are generated from Nix in `.stackpanel/gen/schemas/`
- VS Code workspace maps schemas to file patterns
- Install the Red Hat YAML extension for intellisense

## Docs

The public-facing docs are in `apps/docs/content/`. Internal developer docs are in `docs/`. Always check the docs to understand current behavior before making changes.
