# Stackpanel Project Rules

Stackpanel is a Nix-based development environment framework that provides:

- **Consistent dev environments** via devenv/Nix with reproducible shells
- **Multi-app monorepo support** with automatic port assignment and Caddy reverse proxy
- **Secrets management** with SOPS/vals integration and per-app codegen
- **IDE integration** with VS Code workspace generation
- **Service orchestration** for PostgreSQL, Redis, Minio, etc.

## Directory Layout

```
.
├── .stackpanel/                    # Stackpanel configuration (checked in)
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
│       └── stackpanel.json         # State file for CLI/agent
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
│   ├── modules/                    # Stackpanel modules (options + config)
│   │   ├── stackpanel.nix          # Core module (dirs, motd, direnv)
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

Stackpanel assigns deterministic ports based on a hash of the project name, ensuring each project gets a unique, predictable port range that won't conflict with other stackpanel projects.

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

**Example** for project `stackpanel`:
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

Files in `.stackpanel/gen/` are regenerated on each `devenv` run:
- Should be checked into git for IDE functionality without devenv
- JSON schemas enable YAML intellisense in VS Code
- Workspace file configures terminal integration

**Architecture**: Nix computes the configuration, then calls the Go CLI to write all files atomically:

```
┌─────────────────────────────────────────────────────────────┐
│                         Nix/devenv                          │
│  - Computes full config (ports, apps, services, IDE)        │
│  - Builds Go CLI binary                                     │
│  - In enterShell: pipes config JSON to CLI                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
              stackpanel init --config '${configJson}'
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Go CLI (single writer)                 │
│  - Writes state.json                                        │
│  - Writes IDE files (real files, not symlinks)              │
│  - Writes JSON schemas                                      │
│  - All writes happen atomically                             │
└─────────────────────────────────────────────────────────────┘
```

This ensures generated files and state.json are always in sync (no divergence possible).

### State File

The state file (`.stackpanel/state/stackpanel.json`) is generated on each devenv shell entry and provides the Go CLI and agent with access to the current devenv configuration without evaluating Nix.

**Location**: `.stackpanel/state/stackpanel.json` (gitignored)

**Contents**:
```json
{
  "version": 1,
  "projectName": "stackpanel",
  "basePort": 6400,
  "paths": {
    "state": ".stackpanel/state",
    "gen": ".stackpanel/gen",
    "data": ".stackpanel"
  },
  "apps": {
    "web": { "port": 6402, "domain": "stackpanel.localhost", "url": "http://stackpanel.localhost", "tls": false },
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
import "github.com/darkmatter/stackpanel/cli/state"

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
direnv allow  # or: devenv shell

# Individual commands
bun install            # Install dependencies
bun run dev            # Start dev servers
stackpanel status      # Check service status
stackpanel services start  # Start PostgreSQL, Redis, etc.
```

## Nix Module Guidelines

When creating or modifying Nix modules:

1. **Options go in `options.stackpanel.*`** - Follow the existing pattern
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
- Schemas are generated from Nix in `.stackpanel/gen/schemas/`
- VS Code workspace maps schemas to file patterns
- Install the Red Hat YAML extension for intellisense

## Docs

The docs for stackpanel are in apps/docs/content - ALWAYS give the docs a quick scan so that you understand stackpanel.