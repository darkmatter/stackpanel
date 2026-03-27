<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://stack.dev/light.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://stack.dev/dark.svg">
    <img alt="stack" src="https://stack.dev/light.svg" width="400">
  </picture>
</p>

<h3 align="center">Ship products, not plumbing.</h3>

<p align="center">
  <a href="https://github.com/darkmatter/stack/actions/workflows/ci.yml"><img src="https://github.com/darkmatter/stack/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://stack.dev"><img src="https://img.shields.io/badge/docs-stack.dev-blue" alt="Documentation"></a>
  <a href="https://github.com/darkmatter/stack/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
</p>

<p align="center">
  Reproducible dev environments, service orchestration, and secrets management.<br>
  Powered by Nix. No Nix knowledge required.
</p>

---

## The Problem

Configuration files, build tooling, environment setup - this is the bureaucracy of software development. Every new project means re-establishing the same foundations. Every config file represents a decision someone already made thousands of times.

**The value of your application lives in your source code, not configuration.**

## What Stack Does

Stack provides a complete development infrastructure toolkit:

- **Zero-config dev environments** - Automatic setup for popular stacks with deterministic ports
- **Secrets management** - Team-based encrypted secrets with AGE/SOPS
- **IDE integration** - Auto-generated VS Code workspaces and settings
- **Global services** - PostgreSQL, Redis, Minio with one-line config
- **AWS integration** - Passwordless AWS access via certificate authentication
- **Web Studio** - Local web UI for managing your entire stack

**No lock-in.** Generated files are standard formats in standard locations. Eject anytime with a normal codebase.

**No Nix knowledge required.** If you can write JSON, you can configure Stack. Or just use the web UI.

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled ([Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer) recommended)
- [direnv](https://direnv.net/) (optional but recommended)

### Create a New Project

```bash
# Create a new project with the default template
nix flake init -t github:darkmatter/stack

# Set up direnv
echo 'use flake . --impure' > .envrc
direnv allow

# Or manually enter the shell
nix develop --impure
```

### Add to an Existing Project

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";
    stack.url = "github:darkmatter/stack";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.devenv.flakeModule
        inputs.stack.flakeModules.default
      ];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

      perSystem = {pkgs, ...}: {
        devenv.shells.default = {
          imports = [inputs.stack.devenvModules.default];
          
          # Your config
          stack.enable = true;
          packages = [pkgs.nodejs pkgs.bun];
        };
      };
    };
}
```

## Configuration

Edit `.stack/config.nix` to configure your environment:

```nix
{
  enable = true;
  
  # Themed shell prompt
  theme.enable = true;
  
  # VS Code integration
  ide.vscode.enable = true;
  
  # Global services
  globalServices = {
    postgres.enable = true;
    redis.enable = true;
  };
  
  # AWS certificate auth
  # aws.roles-anywhere.enable = true;
}
```

## Features

### Deterministic Ports

Ports are computed from your project name, ensuring everyone on the team gets the same ports without configuration:

```
my-project → base port 4200
  web      → 4200
  api      → 4201
  postgres → 4210
  redis    → 4211
```

### Secrets Management

Team-based secrets with AGE encryption:

```nix
stack.secrets = {
  master-key.enable = true;
  
  apps.api = {
    dev = {
      DATABASE_URL = "postgres://...";
      API_KEY = "secret:api-key";
    };
  };
};
```

### IDE Integration

Auto-generated VS Code workspace with:
- Correct terminal environment
- Extension recommendations  
- Debugger configurations
- Task runners

### Web Studio

Local web UI at `localhost:9876` for:
- Managing services
- Viewing logs
- Editing configuration
- Installing extensions

## Documentation

Full documentation is available at [stack.dev](https://stack.dev/docs):

- [Quick Start Guide](https://stack.dev/docs/quick-start)
- [Concepts](https://stack.dev/docs/concepts)
- [Configuration Reference](https://stack.dev/docs/reference)
- [Secrets Management](https://stack.dev/docs/features/secrets)
- [AWS Integration](https://stack.dev/docs/features/aws)

## Architecture

For details on the internal architecture, see [ARCHITECTURE.md](./ARCHITECTURE.md).

## Development

```bash
# Enter the dev shell
nix develop --impure

# Start all services
dev

# Run the web app only
bun run dev:web

# Run the Go agent
bun run dev:agent
```

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## License

MIT License - see [LICENSE](./LICENSE) for details.
