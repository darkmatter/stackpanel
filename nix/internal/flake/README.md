# nix/flake/

This directory contains the flake outputs and exported modules for stackpanel's Nix integration.

## Overview

The `nix/flake/` directory provides everything needed to integrate stackpanel into Nix projects, whether using pure flakes, flake-parts, or devenv.

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
  imports = [ inputs.stackpanel.devenvModules.default ];
  stackpanel.enable = true;
};
```

### flakeModules

Modules for [flake-parts](https://flake.parts) integration:

```nix
imports = [ inputs.stackpanel.flakeModules.devshell ];
stackpanel.devshell.enable = true;
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

Add stackpanel to your flake inputs:

```nix
{
  inputs.stackpanel.url = "github:stack-panel/nix";

  outputs = { stackpanel, ... }: {
    # Use stackpanel exports here
  };
}
```

See individual subdirectory READMEs for detailed usage.
