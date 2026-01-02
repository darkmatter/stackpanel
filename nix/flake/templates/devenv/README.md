# My Project

Powered by [stackpanel](https://github.com/darkmatter/stackpanel) + [devenv](https://devenv.sh).

## Getting Started

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- [devenv](https://devenv.sh/getting-started/)

### Enter the Dev Environment

```bash
# Enter the shell
devenv shell

# Or use direnv (recommended)
echo "use devenv" > .envrc
direnv allow
```

### Run Development Server

```bash
# Start all processes defined in devenv.nix
devenv up

# Or run individual commands
bun run dev
```

## Project Structure

```
.
├── devenv.yaml            # Devenv inputs and imports
├── devenv.nix             # Devenv configuration (packages, languages, etc.)
├── .stackpanel/
│   └── config.nix         # Stackpanel options (theme, AWS, services, etc.)
└── devenv.lock            # Locked dependencies (auto-generated)
```

## Configuration

### Stackpanel Options

Edit `.stackpanel/config.nix` to configure stackpanel features:

```nix
{
  enable = true;
  cli.enable = true;             # CLI tools
  theme.enable = true;           # Starship prompt
  ide.vscode.enable = true;      # VS Code integration

  # AWS certificate auth
  # aws.roles-anywhere.enable = true;

  # Global services
  # globalServices.postgres.enable = true;
}
```

### Devenv Options

Edit `devenv.nix` to configure the dev environment:

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
| `devenv shell` | Enter the dev environment |
| `devenv up` | Start all processes |
| `devenv info` | Show environment info |
| `devenv update` | Update dependencies |
| `devenv gc` | Garbage collect old environments |

## Learn More

- [stackpanel Documentation](https://stackpanel.dev/docs)
- [devenv Documentation](https://devenv.sh)
- [devenv Options Reference](https://devenv.sh/reference/options/)
