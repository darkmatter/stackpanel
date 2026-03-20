# My Project

Powered by [Stack](https://stack.dev) + [devenv](https://devenv.sh).

> This template uses standalone devenv (no flake.nix required).

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled ([Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer) recommended)
- [devenv](https://devenv.sh/getting-started/)

### Enter the Dev Environment

```bash
# Enter the shell
devenv shell

# Or use direnv (recommended)
echo "use devenv" > .envrc
direnv allow
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
├── devenv.yaml            # Devenv inputs and imports
├── devenv.nix             # Devenv configuration
├── devenv.lock            # Locked dependencies (auto-generated)
└── .stack/
    └── config.nix         # Stack options
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

Edit `devenv.nix`:

```nix
{ pkgs, ... }: {
  packages = [ pkgs.nodejs pkgs.bun ];
  
  languages.typescript.enable = true;
  
  env.DATABASE_URL = "postgres://localhost:5432/myapp";
  
  processes.server.exec = "bun run dev";
}
```

## Commands

| Command | Description |
|---------|-------------|
| `devenv shell` | Enter the dev environment |
| `devenv up` | Start all processes |
| `devenv info` | Show environment info |
| `devenv update` | Update dependencies |
| `devenv gc` | Garbage collect old environments |

## Learn More

- [Stack Documentation](https://stack.dev/docs)
- [Quick Start Guide](https://stack.dev/docs/quick-start)
- [devenv Documentation](https://devenv.sh)
- [devenv Options Reference](https://devenv.sh/reference/options/)
