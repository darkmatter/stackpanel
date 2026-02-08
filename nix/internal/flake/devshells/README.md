# nix/flake/devshells/

Development shell creation utilities for stackpanel.

## Overview

This directory provides the infrastructure for creating Nix development shells with stackpanel's module system. It exports a factory function and core module that can be used directly or through higher-level integrations.

## Files

### default.nix

Entry point that exports:
- `core`: The core devshell module with schema, commands, codegen, and files support
- `mkDevShell`: Factory function for creating shells
- `features`: Optional feature modules (AWS, Step CA, etc.)

### mkDevShell.nix

The main factory function that:
1. Evaluates a list of NixOS-style modules using `lib.evalModules`
2. Extracts configuration from `devshell.*` options
3. Produces a `pkgs.mkShell` derivation with:
   - Packages and build inputs
   - Environment variable exports
   - Shell hooks (before, main, after phases)
   - Passthru attributes for introspection

## Usage

### Direct Usage

```nix
let
  devshell = import ./devshells { inherit inputs; };

  myShell = devshell.mkDevShell {
    inherit pkgs;
    modules = [
      ./my-project-module.nix
      ({ config, ... }: {
        devshell.packages = [ pkgs.nodejs ];
        devshell.env.NODE_ENV = "development";
      })
    ];
    specialArgs = {
      # Extra args passed to all modules
    };
  };
in myShell
```

### With flake-parts

```nix
stackpanel.devshell = {
  enable = true;
  modules = [ ./devshell.nix ];
};
```

### With devenv

```nix
devenv.shells.default = {
  imports = [ inputs.stackpanel.devenvModules.default ];
  stackpanel.enable = true;
};
```

### Legacy Usage

```nix
# flake.nix
devShells.${system}.default = inputs.stackpanel.lib.mkDevShell {
  pkgs = pkgs;
  modules = [
    inputs.stackpanel.lib.devshellModules.example
    ({ lib, pkgs, ... }: {
      devshell.packages = [ pkgs.nodejs_22 ];
      devshell.hooks.before = lib.mkBefore [ "echo consumer before" ];
    })
  ];
};
```

## Shell Hook Phases

The devshell supports three hook phases that run in order:
1. **before**: Setup tasks, environment preparation
2. **main**: Primary initialization
3. **after**: Cleanup, status messages

```nix
devshell.hooks = {
  before = [ "echo 'Starting...'" ];
  main = [ "source .env" ];
  after = [ "echo 'Ready!'" ];
};
```

## Introspection

Created shells include passthru attributes for debugging:

```nix
myShell.passthru.devshellConfig  # The evaluated devshell config
myShell.passthru.moduleConfig    # The full evaluated module config
```