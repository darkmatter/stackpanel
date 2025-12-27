# nix/flake/modules/

NixOS-style modules for stackpanel integrations.

## Overview

This directory contains modules that integrate stackpanel with various Nix ecosystems including devenv and flake-parts. The modules provide the `stackpanel.*` options namespace and handle wiring between stackpanel's internal configuration and host systems.

## Directory Structure

```
modules/
├── default.nix                  # Module exports
├── devenv-devshell-adapter.nix  # Low-level devenv adapter
├── devenv/                      # devenv integration
│   ├── default.nix              # Main devenv module
│   └── recommended.nix          # Recommended settings
└── flake-parts/                 # flake-parts integration
    └── devshell.nix             # Devshell flake-parts module
```

## Exports

### devenvModules

Available via `inputs.stackpanel.devenvModules`:

- **default**: Main devenv module with full `stackpanel.*` options

### flakeModules

Available via `inputs.stackpanel.flakeModules`:

- **devshell**: Flake-parts module for stackpanel devshells

## devenv Integration

### Basic Usage

```nix
# devenv.nix
{ inputs, ... }: {
  imports = [ inputs.stackpanel.devenvModules.default ];

  stackpanel.enable = true;
  stackpanel.devshell = {
    packages = [ pkgs.nodejs ];
    env.NODE_ENV = "development";
  };
}
```

### Recommended Settings

Enable opinionated defaults for formatters and linters:

```nix
stackpanel.devenv.recommended = {
  enable = true;       # All recommended settings
  formatters.enable = true;  # Just formatters
};
```

Formatters included:
- **alejandra**: Nix code formatter
- **shellcheck**: Shell script linter
- **ruff**: Python format/lint (when Python enabled)
- **mdformat**: Markdown formatter

## flake-parts Integration

### Basic Usage

```nix
# flake.nix
{
  imports = [ inputs.stackpanel.flakeModules.devshell ];

  stackpanel.devshell = {
    enable = true;
    shellName = "default";  # Name in devShells output
    modules = [
      ./devshell.nix
      { devshell.packages = [ pkgs.git ]; }
    ];
  };
}
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable stackpanel devshell |
| `shellName` | string | `"default"` | Name of the devShell output |
| `modules` | list | `[]` | Devshell modules to include |
| `specialArgs` | attrs | `{}` | Extra arguments for modules |

## How It Works

### Option Mapping

The modules automatically map stackpanel configuration to host system options:

| stackpanel | devenv |
|------------|--------|
| `devshell.packages` | `packages` |
| `devshell.env` | `env` |
| `devshell.hooks.*` | `enterShell` |
| `devshell.commands` | `scripts` |

### Module Evaluation

1. Modules import stackpanel core options from `stackpanel/core/options`
2. User configuration is evaluated
3. Resulting config is mapped to host system options
4. Host system (devenv/flake-parts) produces the final shell

## Low-Level Adapter

The `devenv-devshell-adapter.nix` provides direct mapping without the full options namespace. Prefer using `devenv/default.nix` for most use cases.
