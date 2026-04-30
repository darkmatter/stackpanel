<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://stackpanel.com/light.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://stackpanel.com/dark.png">
    <img alt="stackpanel" src="https://stackpanel.com/light.svg" width="400">
  </picture>
</p>

<h3 align="center">Ship products, not plumbing.</h3>

<p align="center">
  <a href="https://github.com/darkmatter/stackpanel/actions/workflows/ci.yml"><img src="https://github.com/darkmatter/stackpanel/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://stackpanel.dev"><img src="https://img.shields.io/badge/docs-stackpanel.dev-blue" alt="Documentation"></a>
  <a href="https://github.com/darkmatter/stackpanel/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
</p>

<p align="center">
  Reproducible dev environments, service orchestration, secrets management, and deployment —<br>
  powered by Nix, driven by a local agent, managed through a web studio or CLI.<br>
  No Nix knowledge required.
</p>

---

## Why Stackpanel?

Every new project means re-establishing the same foundations: database setup, environment variables, IDE config, deployment boilerplate. The value of your application lives in your source code, not in the glue around it.

Stackpanel replaces that glue with a single `config.nix` file. Deterministic ports, encrypted secrets, service orchestration, VS Code integration, TLS certificates, and deployment — all computed from one config. No lock-in: generated files are standard formats in standard locations. Eject anytime.

## How It Works

Stackpanel runs on three planes:

```
Browser (Studio UI)
  │
  ├── tRPC ──→ Cloud API (Hono on Cloudflare Workers)
  │                ├── Auth (Better Auth + Polar payments)
  │                └── Drizzle ORM → Neon PostgreSQL
  │
  └── HTTP/Connect-RPC ──→ Go Agent (localhost)
                              ├── nix eval (config, options, packages)
                              ├── process-compose (service lifecycle)
                              ├── file system (secrets, config, codegen)
                              ├── Caddy (reverse proxy, TLS)
                              └── Step CA (certificates)
```

1. **Nix plane** — evaluates your config, computes ports, provisions the devshell, generates files. Runs once on shell entry.
2. **Go agent** — a localhost HTTP server that bridges the Studio web UI to the local environment. REST + Connect-RPC APIs, SSE events, file watching, process management.
3. **Web Studio** — a React app (TanStack Start) for managing your entire stack visually: services, secrets, config, deploys, and more.

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled ([Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer) recommended)
- [direnv](https://direnv.net/) (optional but recommended)

### Create a New Project

```bash
nix flake init -t git+ssh://git@github.com/darkmatter/stackpanel

echo 'use flake . --impure' > .envrc
direnv allow
```

### Add to an Existing Project

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.stackpanel.flakeModules.default];
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

      perSystem = {pkgs, ...}: {
        devenv.shells.default = {
          imports = [inputs.stackpanel.devenvModules.default];
          stackpanel.enable = true;
          packages = [pkgs.nodejs pkgs.bun];
        };
      };
    };
}
```

## Configuration

Everything lives in `.stack/config.nix`:

```nix
{ config, ... }:
{
  stackpanel = {
    enable = true;

    # Apps — ports are computed deterministically from the project name
    apps.web.port = 3000;
    apps.api.port = 3001;

    # Services
    globalServices = {
      postgres.enable = true;
      redis.enable = true;
      minio.enable = true;
    };

    # Secrets (AGE/SOPS encrypted, team-based)
    secrets = {
      master-key.enable = true;
      apps.api.dev = {
        DATABASE_URL = "postgres://...";
        API_KEY = "secret:api-key";
      };
    };

    # IDE integration
    ide.vscode.enable = true;

    # Shell prompt theming
    theme.enable = true;

    # TLS via Step CA
    # step-ca.enable = true;

    # AWS Roles Anywhere
    # aws.roles-anywhere.enable = true;

    # Deployment
    deployment.alchemy = {
      deploy.enable = true;
      deploy.auto-provision-state-store = true;
    };
  };
}
```

## Features

### Deterministic Ports

Ports are computed from a hash of your project name — the same ports on every machine, no manual assignment:

```
my-project → base port 4200
  web      → 4200
  api      → 4201
  postgres → 4210
  redis    → 4211
```

### Secrets Management

Team-based encrypted secrets with AGE/SOPS. Secrets are encrypted at rest, decrypted on shell entry, and injected as environment variables:

```nix
stackpanel.secrets = {
  master-key.enable = true;
  apps.api.dev = {
    DATABASE_URL = "postgres://...";
    STRIPE_KEY = "secret:stripe-key";
  };
};
```

### IDE Integration

Auto-generated VS Code workspace with correct terminal environment, extension recommendations, debugger configurations, and task runners. Zed support coming soon.

### Web Studio

A local web UI for managing your entire stack:

- **Dashboard** — overview of all apps, services, and health checks
- **Services** — start/stop/restart databases and services
- **Secrets** — manage encrypted environment variables
- **Configuration** — edit `config.nix` with a visual editor
- **Deploy** — trigger deployments to cloud infrastructure
- **Processes** — view and manage running processes
- **Terminal** — embedded terminal with devshell environment
- **Packages** — browse and add nixpkgs packages
- **Extensions** — install stackpanel extension modules

### CLI (`stackpanel`)

The Go-based CLI provides everything the Studio does, plus more:

```bash
stackpanel commands          # List/run devshell scripts (interactive TUI)
stackpanel config show       # Print resolved configuration
stackpanel config example    # Generate example config
stackpanel env               # Show environment variables
stackpanel logs              # Tail service logs
stackpanel deploy            # Deploy to cloud
stackpanel agent             # Start the localhost agent server
stackpanel caddy             # Manage the shared Caddy reverse proxy
stackpanel init              # Initialize a new project
stackpanel nixify            # Generate Nix config for an existing project
stackpanel healthcheck       # Run health checks
stackpanel codegen           # Run host-side code generators
stackpanel flake             # Manage the Nix flake
```

### Nix Module System

Stackpanel's core is an adapter-agnostic Nix module system. All logic lives in `nix/stack/` with zero dependency on devenv, NixOS, or any specific module host. Thin adapters translate to each target:

| Namespace | Purpose |
|-----------|---------|
| `stackpanel.apps` | App definitions with computed ports and URLs |
| `stackpanel.services` | Canonical service type system |
| `stackpanel.globalServices` | Convenience services (postgres, redis, minio) |
| `stackpanel.devshell` | Shell environment, packages, hooks, env vars, generated files |
| `stackpanel.scripts` | Shell commands (shown in TUI and Studio) |
| `stackpanel.modules` | Extension module registry |
| `stackpanel.secrets` | Master-key secrets management |
| `stackpanel.ide` | VS Code and Zed integration |
| `stackpanel.theme` | Starship prompt theming |
| `stackpanel.step-ca` | Certificate management |
| `stackpanel.aws` | AWS Roles Anywhere |
| `stackpanel.process-compose` | Process orchestration |
| `stackpanel.deployment` | Alchemy / cloud deployment |

### Deployment

Stackpanel supports deploying to cloud infrastructure via [Alchemy](https://alchemy.run), with support for Cloudflare Workers, microVMs (NixOS on OVH/Hetzner), and more. Colmena and nixos-anywhere are available for bare-metal NixOS deployments.

## Project Structure

```
stackpanel/
├── apps/
│   ├── web/              # Studio UI (React + TanStack Start)
│   ├── api/              # Cloud API (Hono on Cloudflare Workers)
│   ├── docs/             # Documentation site (Next.js + Fumadocs)
│   ├── stackpanel-go/    # CLI + localhost agent (Go + Cobra + Bubble Tea)
│   └── tui/              # Terminal UI components (TypeScript + Ink)
├── packages/
│   ├── api/              # Shared business logic
│   ├── auth/             # Better-Auth config
│   ├── db/               # Drizzle ORM + Neon PostgreSQL
│   ├── ui/               # Shared UI components
│   ├── config/           # Config utilities
│   ├── infra/            # Infrastructure-as-code (Alchemy)
│   ├── proto/            # Connect-RPC protocol definitions
│   ├── sdk/              # Stackpanel SDK
│   ├── gen/              # Generated types
│   ├── agent-client/     # Go agent HTTP client
│   ├── scripts/          # Build and CI scripts
│   ├── docs-content/     # Shared documentation content
│   └── znv/              # Zod + env parsing
├── nix/
│   ├── stack/            # Core Nix module system (adapter-agnostic)
│   ├── flake/            # Flake outputs (devenvModules, templates, devshells)
│   └── internal/         # Internal config for developing stackpanel itself
├── docs/                 # Architecture docs, specs, and design notes
└── examples/             # Example projects
```

## Development

```bash
# Enter the dev shell
nix develop --impure
# or with direnv
direnv allow

# Start all services
dev

# Individual apps
bun run dev:web       # Studio UI
bun run dev:server    # Cloud API
bun run dev:agent     # Go agent (alias for stackpanel agent)
```

## Documentation

Full docs at [stackpanel.dev](https://stackpanel.dev/docs):

- [Quick Start](https://stackpanel.dev/docs/quick-start)
- [Concepts](https://stackpanel.dev/docs/concepts)
- [Configuration Reference](https://stackpanel.dev/docs/reference)
- [Secrets Management](https://stackpanel.dev/docs/features/secrets)
- [AWS Integration](https://stackpanel.dev/docs/features/aws)
- [Architecture](docs/ARCHITECTURE.md)

## License

MIT — see [LICENSE](./LICENSE) for details.
