# My Project

Powered by [Stackpanel](https://stackpanel.dev) - reproducible dev environments without the complexity.

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

You'll see a welcome message with available commands when the shell activates.

### Start Development

```bash
# Start all services and processes
dev

# Or run individual commands
bun run dev
```

## Configuration

### Stackpanel Config

Edit `.stack/config.nix` to configure your environment:

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

Edit `nix/devenv.nix` for packages, languages, and processes:

```nix
{ pkgs }: {
  packages = with pkgs; [
    nodejs
    bun
  ];

  languages.typescript.enable = true;

  env = {
    NODE_ENV = "development";
  };
}
```

## Commands

| Command | Description |
|---------|-------------|
| `dev` | Start development (all processes) |
| `direnv allow` | Activate the dev environment |
| `stackpanel status` | Check service status |
| `stackpanel services start` | Start background services |
| `nix flake update` | Update dependencies |

## Project Structure

```
.
├── .stack/                # Stackpanel configuration
│   ├── config.nix         # Main config
│   ├── profile/           # Runtime state (gitignored)
│   └── gen/               # Generated files (gitignored)
├── nix/
│   └── devenv.nix         # Devenv options
├── flake.nix              # Nix flake entrypoint
└── .envrc                 # direnv integration
```

## Learn More

- [Stackpanel Documentation](https://stackpanel.dev/docs)
- [Quick Start Guide](https://stackpanel.dev/docs/quick-start)
- [Configuration Reference](https://stackpanel.dev/docs/reference)
