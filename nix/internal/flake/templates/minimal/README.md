# My Project

Powered by [Stack](https://stack.dev) - reproducible dev environments without the complexity.

> This is the **minimal** template - a bare Nix flake without flake-parts.

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled ([Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer) recommended)
- [direnv](https://direnv.net/) (optional but recommended)

### Enter the Dev Environment

```bash
# With direnv (recommended)
direnv allow

# Or manually
nix develop --impure
```

### Start Development

```bash
# Start all processes
devenv up

# Or run individual commands
bun run dev
```

## Project Structure

```
.
├── flake.nix              # Nix flake (main entry point)
├── flake.lock             # Locked dependencies (auto-generated)
├── .stack/
│   └── config.nix         # Stack options
└── .envrc                 # direnv configuration
```

## Configuration

### Stack Config

Edit `.stack/config.nix`:

```nix
{
  enable = true;
  
  # Shell prompt theme
  theme.enable = true;
  
  # VS Code integration
  ide.vscode.enable = true;
  
  # Enable services
  globalServices = {
    postgres.enable = true;
    redis.enable = true;
  };
}
```

### Devenv Options

Edit `flake.nix` directly:

```nix
{
  packages = [ pkgs.nodejs pkgs.bun ];
  languages.typescript.enable = true;
  env.DATABASE_URL = "postgres://localhost:5432/myapp";
}
```

## Commands

| Command | Description |
|---------|-------------|
| `direnv allow` | Activate the dev environment |
| `devenv up` | Start all processes |
| `nix develop --impure` | Enter shell manually |
| `nix flake update` | Update dependencies |

## Why Minimal?

This template uses a standard Nix flake without [flake-parts](https://flake.parts/).

**Choose this if:**
- You prefer explicit over magical
- You don't need flake-parts features
- You want a simpler flake structure

**Choose the default template if:**
- You want better modularity
- You need perSystem helpers
- You're building a complex project

## Learn More

- [Stack Documentation](https://stack.dev/docs)
- [Quick Start Guide](https://stack.dev/docs/quick-start)
- [devenv Documentation](https://devenv.sh)
