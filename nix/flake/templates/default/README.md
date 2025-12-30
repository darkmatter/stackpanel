# My Project

Powered by [stackpanel](https://github.com/darkmatter/stackpanel).

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
# Start all processes defined in devenv
devenv up

# Or run individual commands
bun run dev
```

## Configuration

All configuration is in `flake.nix` under `devenv.shells.default`.

### Enable Features

```nix
stackpanel = {
  enable = true;
  theme.enable = true;           # Starship prompt
  ide.vscode.enable = true;      # VS Code integration
  
  # AWS certificate auth
  aws.roles-anywhere.enable = true;
  
  # Global services
  globalServices.postgres.enable = true;
};
```

### Add Packages

```nix
packages = with pkgs; [
  nodejs
  bun
  go
];
```

### Configure Languages

```nix
languages = {
  typescript.enable = true;
  go.enable = true;
  python.enable = true;
};
```

### Environment Variables

```nix
env = {
  DATABASE_URL = "postgres://localhost:5432/myapp";
};
```

## Common Commands

| Command | Description |
|---------|-------------|
| `direnv allow` | Activate the dev environment |
| `devenv up` | Start all processes |
| `nix flake check` | Validate the flake |
| `nix flake update` | Update dependencies |

## Learn More

- [stackpanel Documentation](https://stackpanel.dev/docs)
- [devenv Documentation](https://devenv.sh)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
