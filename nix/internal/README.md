# nix/internal/

**Legacy internal modules for the stackpanel repository itself.**

This directory is kept for historical/internal implementation notes. Active development shell construction now lives in the flake-parts module under `nix/flake/default.nix` and reads project configuration from `.stack/config.nix`.

## Development Workflow

```bash
# Enter the development shell
nix develop

# Start all dev processes (web, docs, server, format-watch)
dev

# Or use direnv for automatic shell loading
direnv allow
```

## Architecture

The flake creates a unified shell through `stackpanel.lib.mkFlake`:

- Auto-loads `.stack/config.nix` for stackpanel options
- Uses native `stackpanel.languages.*`, `stackpanel.packages`, and `stackpanel.devshell.*` options
- Provides the `dev` command through process-compose integration

```text
flake.nix
    |
stackpanel.lib.mkFlake { inherit inputs self; }
    |
.stack/config.nix (stackpanel options)
    |
devShells.default (pkgs.mkShell with process-compose)
```

## Current external usage

If you're using stackpanel in your own project, prefer the flake-parts wrapper:

```nix
{
  inputs.stackpanel.url = "github:darkmatter/stackpanel";

  outputs = inputs @ { self, stackpanel, ... }:
    stackpanel.lib.mkFlake {
      inherit inputs self;
    };
}
```

Configure packages, language toolchains, environment variables, hooks, services, and apps in `.stack/config.nix`.
