# nix/internal/

**Internal modules for the stack repository itself.**

This directory contains internal devenv-compatible modules that are loaded by the flake. These modules define processes, languages, and services for developing the stack project.

## Development Workflow

```bash
# Enter the development shell
nix develop --impure

# Start all dev processes (web, docs, server, format-watch)
dev

# Or use direnv for automatic shell loading
direnv allow
```

## Architecture

The flake creates a unified shell using `pkgs.mkShell`:
- Auto-loads `.stack/config.nix` for stack options
- Auto-loads internal devenv modules for processes/languages
- Provides the `dev` command (process-compose wrapper)

```
flake.nix
    |
imports = [ exports.flakeModules.default ]
    |
.stack/config.nix (stack options)
nix/internal/devenv/* (processes, languages)
    |
devShells.default (pkgs.mkShell with process-compose)
```

## Structure

```
nix/internal/
├── README.md              # This file
└── devenv/                # Internal modules
    ├── devenv.nix         # Root module (imports all sub-modules)
    ├── docs/              # Documentation app (apps/docs)
    │   └── devenv.nix     # Docs dev server process
    ├── tools/             # Development infrastructure
    │   └── devenv.nix     # Services and tooling
    └── web/               # Web app (apps/web)
        └── devenv.nix     # Web dev server process
```

## What These Modules Provide

- **Processes**: `web`, `docs`, `server`, `format-watch` dev servers
- **Languages**: JavaScript/Bun, Go
- **Cachix**: Binary cache configuration

## For External Users

If you're using stack in your own project:

### Standard Setup (`nix develop`)

```nix
# flake.nix
imports = [ inputs.stack.flakeModules.default ];

# Configure in .stack/config.nix
# Additional packages/env in .stack/devenv.nix (optional)
```

### With Devenv (for devenv.shells users)

Stack modules are compatible with devenv. Import the devenv adapter:

```nix
# In your devenv.shells.default
{
  imports = [ inputs.stack.devenvModules.default ];
  
  stack = import ./.stack/_internal.nix { inherit pkgs lib; };
  
  # Additional devenv options
  languages.javascript.enable = true;
}
```

See the main project documentation for details.
