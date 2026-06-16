# nix/flake/

This directory contains the flake outputs and exported modules for stackpanel's Nix integration.

## Overview

The `nix/flake/` directory provides everything needed to integrate stackpanel into Nix projects using pure flakes or flake-parts.

## Directory Structure

```text
flake/
├── default.nix          # Main flake-parts module
├── per-system-outputs.nix # Per-system flake output builder
├── load-config.nix      # Config discovery and loading helpers
├── global-outputs.nix   # Global flake outputs (NixOS, colmena, etc.)
├── devshells/           # Development shell creation utilities
├── templates/           # Project templates for quick-start
├── apps/                # Runnable applications
├── checks/              # Flake checks
├── formatter/           # Code formatting configuration
├── lib/                 # Library functions
├── overlays/            # Nixpkgs overlays
└── packages/            # Package definitions
```

## Key Exports

### `flakeModules`

Modules for [flake-parts](https://flake.parts) integration:

```nix
{
  inputs.stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";

  outputs = inputs @ { self, stackpanel, ... }:
    stackpanel.lib.mkFlake {
      inherit inputs self;

      perSystem = { pkgs, ... }: {
        packages.hello = pkgs.hello;
      };
    };
}
```

### `lib.mkFlake`

High-level helper that wires up `flake-parts`, the stackpanel module, required overlays, and caller-provided imports:

```nix
stackpanel.lib.mkFlake {
  inherit inputs self;

  systems = [ "aarch64-darwin" "x86_64-linux" ];
  stackpanelImports = [ ./nix/my-module.nix ];

  perSystem = { pkgs, ... }: {
    packages.myapp = pkgs.hello;
  };
}
```

### `lib.mkOutputs`

Lower-level helper for building per-system outputs manually when you already have a `pkgs`:

```nix
import stackpanel.lib.mkOutputs { inherit pkgs inputs self system; }
```

### `templates`

Project templates for bootstrapping new projects:

```bash
nix flake init -t git+ssh://git@github.com/darkmatter/stackpanel
```

## Usage

Add stackpanel to your flake inputs:

```nix
{
  inputs.stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";

  outputs = inputs @ { self, stackpanel, ... }:
    stackpanel.lib.mkFlake {
      inherit inputs self;
      # ...your configuration
    };
}
```

Configuration lives in `.stack/config.nix` and is loaded automatically. See individual subdirectory READMEs and `.stack/config.nix` in this repo for detailed usage.

## Legacy Notes

- `devenvModules` and `lib.wrapDevenv` were removed as part of the flake-parts migration. Use `stackpanel.lib.mkFlake` or `stackpanel.flakeModules.default` instead.
- The `devenv` standalone template and `devenv.shells.*` configuration are no longer provided.
