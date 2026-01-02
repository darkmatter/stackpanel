# My Project

Powered by [stackpanel](https://github.com/darkmatter/stackpanel) with native Nix shells.

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

## Configuration

- **Stackpanel config**: `.stackpanel/config.nix`
- **Flake entry**: `flake.nix`

### Enable Stackpanel Features

Edit `.stackpanel/config.nix`:

```nix
{
  cli.enable = true;             # CLI tools
  theme.enable = true;           # Starship prompt
  ide.vscode.enable = true;      # VS Code integration

  # MOTD
  motd.enable = true;
  motd.commands = [
    { name = "dev"; description = "Start development server"; }
  ];
}
```

### Add Packages

In `flake.nix`, the `stackpanel` module automatically provides shell packages
based on your config. You can add additional packages in `perSystem`:

```nix
perSystem = { pkgs, ... }: {
  stackpanel = import ./.stackpanel/config.nix // { enable = true; };

  # Add additional packages via stackpanel's native output
  # ...

  packages.default = pkgs.myPackage;
};
```

## Why Native?

This template uses `flakeModules.native` instead of devenv, providing:

- **Faster evaluation**: No devenv dependency
- **Pure Nix**: Uses standard `mkShell`
- **Simpler**: Fewer moving parts

Trade-offs:
- No `devenv up` for process management (use `process-compose` separately)
- No devenv-managed services (use `globalServices` or external)

## Common Commands

| Command | Description |
|---------|-------------|
| `direnv allow` | Activate the dev environment |
| `nix develop --impure` | Enter shell manually |
| `stackpanel status` | Check stackpanel services |
| `stackpanel users sync` | Sync team from GitHub |
| `nix flake check` | Validate the flake |
| `nix flake update` | Update dependencies |

## Learn More

- [stackpanel Documentation](https://stackpanel.dev/docs)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
