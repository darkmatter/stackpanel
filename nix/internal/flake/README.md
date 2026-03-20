# nix/flake/

This directory contains the flake outputs and exported modules for stack's Nix integration.

## Overview

The `nix/flake/` directory provides everything needed to integrate stack into Nix projects, whether using pure flakes, flake-parts, or devenv.

## Directory Structure

```
flake/
├── devshells/     # Development shell creation utilities
├── modules/       # NixOS-style modules for various integrations
├── templates/     # Project templates for quick-start
├── apps/          # Runnable applications
├── checks/        # Flake checks
├── formatter/     # Code formatting configuration
├── lib/           # Library functions
├── overlays/      # Nixpkgs overlays
└── packages/      # Package definitions
```

## Key Exports

### devenvModules

Modules for [devenv](https://devenv.sh) integration:

```nix
devenv.shells.default = {
  imports = [ inputs.stack.devenvModules.default ];
  stack.enable = true;
};
```

### flakeModules

Modules for [flake-parts](https://flake.parts) integration:

```nix
imports = [ inputs.stack.flakeModules.devshell ];
stack.devshell.enable = true;
```

### devshells

Utilities for creating development shells:

```nix
devshell.mkDevShell {
  inherit pkgs;
  modules = [ ./my-module.nix ];
}
```

### templates

Project templates for bootstrapping new projects:

```bash
nix flake init -t github:stack-panel/nix#default
```

## Usage

Add stack to your flake inputs:

```nix
{
  inputs.stack.url = "github:stack-panel/nix";

  outputs = { stack, ... }: {
    # Use stack exports here
  };
}
```

See individual subdirectory READMEs for detailed usage.
