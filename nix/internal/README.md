# nix/internal/

**Internal devenv modules for the stackpanel repository itself.**

This directory contains devenv-specific modules for developing the stackpanel project. These are **not** used by `nix develop` - they configure the `devenv shell` workflow.

## Architecture

Stackpanel now has two shell workflows:

### 1. `nix develop` (Recommended)

Uses the flakeModule which creates a pure `pkgs.mkShell`:
- Auto-loads `.stackpanel/config.nix`
- Auto-loads `.stackpanel/devenv.nix` for additional packages/env
- Full control over passthru, shellHook, packages
- No devenv involvement

```
flake.nix
    ↓
imports = [ exports.flakeModules.default ]
    ↓
.stackpanel/config.nix (stackpanel options)
.stackpanel/devenv.nix (additional packages/env)
    ↓
devShells.default (pkgs.mkShell)
```

### 2. `devenv shell` (For devenv features)

For users who need devenv-specific features (languages, services, processes):
- Uses `devenv.nix` + `devenv.yaml` at project root
- Imports stackpanel's devenv adapter
- Imports project-specific devenv modules from this directory

```
devenv shell
    ↓
devenv.nix (project root)
    ↓
nix/flake/modules/devenv.nix (adapter)
nix/internal/devenv/devenv.nix (project-specific)
    ↓
devenv shell with processes, services, languages
```

## Structure

```
nix/internal/
├── README.md              # This file
└── devenv/                # Devenv modules for `devenv shell` workflow
    ├── devenv.nix         # Root module (imports all sub-modules)
    ├── docs/              # Documentation app (apps/docs)
    │   └── devenv.nix     # Docs dev server process
    ├── tools/             # Development infrastructure
    │   └── devenv.nix     # Services: mailpit, tailscale funnel
    └── web/               # Web app (apps/web)
        └── devenv.nix     # Web dev server process
```

## What These Modules Provide

For `devenv shell` / `devenv up`:

- **Processes**: `web`, `docs` dev servers
- **Services**: `mailpit` for email testing
- **Profiles**: `web`, `docs`, `share` for focused development
- **Cachix**: Binary cache configuration

## For External Users

If you're using stackpanel in your own project:

### Pure Stackpanel Shell (`nix develop`)

```nix
# flake.nix
imports = [ inputs.stackpanel.flakeModules.default ];

# Configure in .stackpanel/config.nix
# Additional packages/env in .stackpanel/devenv.nix (optional)
```

### With Devenv Features (`devenv shell`)

```nix
# devenv.nix (project root)
{
  imports = [
    inputs.stackpanel.devenvModules.default
    ./nix/devenv.nix  # Your project-specific devenv modules
  ];

  stackpanel = import ./.stackpanel/_internal.nix { inherit pkgs lib; };

  # Devenv-specific options
  languages.javascript.enable = true;
  processes.web.exec = "bun dev";
}
```

See the main project documentation for details.