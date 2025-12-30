# My Project

Powered by [stackpanel](https://github.com/darkmatter/stackpanel).

This is the **minimal** template - a bare Nix flake without flake-parts.

## Getting Started

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- [direnv](https://direnv.net/) (recommended)

### Enter the Dev Environment

```bash
# Allow direnv (first time only)
direnv allow

# Or manually enter the shell
nix develop --impure
```

### Run Development Server

```bash
# Start all processes defined in the flake
devenv up

# Or run individual commands
bun run dev
```

## Project Structure

```
.
├── flake.nix           # Nix flake (main entry point)
├── flake.lock          # Locked dependencies (auto-generated)
├── nix/
│   └── stackpanel.nix  # Stackpanel options
└── .envrc              # direnv configuration
```

## Configuration

### Stackpanel Options

Edit `nix/stackpanel.nix` to configure stackpanel features:

```nix
{
  enable = true;
  theme.enable = true;           # Starship prompt
  ide.vscode.enable = true;      # VS Code integration
  
  # AWS certificate auth
  aws.roles-anywhere.enable = true;
  
  # Global services
  globalServices.postgres.enable = true;
}
```

### Devenv Options

Edit `flake.nix` directly to configure the dev environment:

```nix
{
  packages = [ pkgs.nodejs pkgs.bun ];
  
  languages.typescript.enable = true;
  
  env.DATABASE_URL = "postgres://localhost:5432/myapp";
  
  processes.server.exec = "bun run dev";
}
```

## Common Commands

| Command | Description |
|---------|-------------|
| `direnv allow` | Activate the dev environment |
| `nix develop --impure` | Enter shell manually |
| `devenv up` | Start all processes |
| `nix flake update` | Update dependencies |
| `nix flake check` | Validate the flake |

## Why Minimal?

This template uses a standard Nix flake without [flake-parts](https://flake.parts/).
It's simpler but less modular than the default template.

**Choose this if:**
- You prefer explicit over magical
- You don't need flake-parts features
- You want a simpler flake structure

**Choose the default template if:**
- You want better modularity
- You need perSystem helpers
- You're building a complex project

## Learn More

- [stackpanel Documentation](https://stackpanel.dev/docs)
- [devenv Documentation](https://devenv.sh)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
