<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://stackpanel.dev/light.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://stackpanel.dev/dark.svg">
    <img alt="stackpanel" src="https://stackpanel.dev/light.svg" width="400">
  </picture>
</p>

<h3 align="center">Ship products, not plumbing.</h3>

<p align="center">
  <a href="https://github.com/darkmatter/stackpanel/actions/workflows/ci.yml"><img src="https://github.com/darkmatter/stackpanel/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://stackpanel.dev"><img src="https://img.shields.io/badge/docs-stackpanel.dev-blue" alt="Documentation"></a>
  <a href="https://github.com/darkmatter/stackpanel/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
</p>

<p align="center">
  Reproducible dev environments, service orchestration, and secrets management.<br>
  Powered by Nix. No Nix knowledge required.
</p>

---

## The Problem

Configuration files, build tooling, environment setup - this is the bureaucracy of software development. Every new project means re-establishing the same foundations. Every config file represents a decision someone already made thousands of times.

**The value of your application lives in your source code, not configuration.**

## What Stackpanel Does

Stackpanel provides a complete development infrastructure toolkit:

- **Zero-config dev environments** - Automatic setup for popular stacks with deterministic ports
- **Secrets management** - Team-based encrypted secrets with AGE/SOPS
- **IDE integration** - Auto-generated VS Code workspaces and settings
- **Global services** - PostgreSQL, Redis, Minio with one-line config
- **AWS integration** - Passwordless AWS access via certificate authentication
- **Web Studio** - Local web UI for managing your entire stack

**No lock-in.** Generated files are standard formats in standard locations. Eject anytime with a normal codebase.

**No Nix knowledge required.** If you can write JSON, you can configure Stackpanel. Or just use the web UI.

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled ([Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer) recommended)
- [direnv](https://direnv.net/) (optional but recommended)

### Create a New Project

```bash
# Create a new project with the default template
nix flake init -t github:darkmatter/stackpanel

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
    stackpanel.url = "github:darkmatter/stackpanel";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.devenv.flakeModule
        inputs.stackpanel.flakeModules.default
      ];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

      perSystem = {pkgs, ...}: {
        devenv.shells.default = {
          imports = [inputs.stackpanel.devenvModules.default];
          
          # Your config
          stackpanel.enable = true;
          packages = [pkgs.nodejs pkgs.bun];
        };
      };
    };
}
```

## Configuration

Edit `.stackpanel/config.nix` to configure your environment:

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

## Documentation

Full documentation is available at [stackpanel.dev](https://stackpanel.dev/docs):

- [Quick Start Guide](https://stackpanel.dev/docs/quick-start)
- [Concepts](https://stackpanel.dev/docs/concepts)
- [Configuration Reference](https://stackpanel.dev/docs/reference)
- [Secrets Management](https://stackpanel.dev/docs/features/secrets)
- [AWS Integration](https://stackpanel.dev/docs/features/aws)

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for details on the internal architecture.

## Contributing

Contributions are welcome! Please see our [contributing guide](./CONTRIBUTING.md) for details.

## License

MIT License - see [LICENSE](./LICENSE) for details.
