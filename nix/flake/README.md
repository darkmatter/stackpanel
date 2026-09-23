# nix/flake/

This directory contains the flake outputs and exported modules for stackpanel's Nix integration.

## Overview

The `nix/flake/` directory provides everything needed to integrate stackpanel into Nix projects using pure flakes or flake-parts.

## Directory Structure

```text
flake/
├── default.nix              # Thin flake-parts composer
├── options.nix              # stackpanel.projectRoot / imports / includeRootOutputs
├── overlays.nix             # Required nixpkgs overlays
├── flake-outputs.nix        # flake.nixosModules, config exports, tests
├── load-config.nix          # Config discovery helpers
├── global-outputs.nix       # NixOS / colmena global outputs
├── packages.nix             # Root CLI package definitions
├── per-system/
│   ├── eval.nix             # evalModules → spConfig
│   ├── shell.nix            # devShells.default
│   └── outputs.nix          # packages / apps / checks / legacyPackages
├── integrations/            # External flake registry (see integrations/README.md)
│   ├── prelude/
│   ├── process-compose/
│   ├── git-hooks/
│   └── treefmt/
├── templates/               # Project templates
└── …
```

## Adding a flake integration

External flakes (Prelude, process-compose, …) register under
[`integrations/`](./integrations/). See [`integrations/README.md`](./integrations/README.md)
for the interface (`available`, `flakeModules`, `perSystem`, `extraShellPackages`).

## Key Exports

### `flakeModules`

Modules for [flake-parts](https://flake.parts) integration:

```nix
{
  inputs.stackpanel.url = "github:darkmatter/stackpanel";

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
nix flake init -t github:darkmatter/stackpanel
```

## Usage

Add stackpanel to your flake inputs:

```nix
{
  inputs.stackpanel.url = "github:darkmatter/stackpanel";

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
