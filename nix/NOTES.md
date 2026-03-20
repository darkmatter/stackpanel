```nix
# nix/flake/devshells/default.nix
{ inputs }:
let
  # base schema + mkDevShell live here
  mkDevShell = import ./mkDevShell.nix;

  # feature modules: these are normal nixpkgs modules that write into devshell.*
  devshellModules = {
    # base features
    aws = import ./modules/aws.nix;
    step = import ./modules/step.nix;
    codegen = import ./modules/codegen.nix;

    # product defaults (compose multiple features)
    stack-defaults = import ./modules/stack-defaults.nix;
  };
in
{
  inherit mkDevShell devshellModules;
}
```

# adapters

```nix
# nix/flake/modules/default.nix
{ inputs, devshell }:
{
  devenvModules = {
    default = import ./devenv/default.nix { inherit devshell; };
  };

  flakePartsModules = {
    default = import ./flake-parts/default.nix { inherit devshell; };
  };
}
```


```nix
# nix/flake/modules/devenv/default.nix
{ devshell }:
{ config, lib, pkgs, ... }:
let
  hooks = config.devshell.hooks;
  enterShell = lib.concatStringsSep "\n\n" (lib.flatten [
    hooks.before hooks.main hooks.after
  ]);

  # Scripts are now handled by nix/stack/devshell/scripts.nix
  # which creates a package with all scripts in bin/
in
{
  # import the schema so devshell.* exists
  imports = [ devshell.devshellModules._base ];

  config = {
    packages = config.devshell.packages;
    env = config.devshell.env;
    enterShell = enterShell;
    scripts = scripts;
  };
}
```

# USAGE (FLAKE)

```nix
devShells.${system}.default = inputs.stack.lib.mkDevShell {
  pkgs = pkgs;
  modules = [
    inputs.stack.lib.devshellModules.aws
    ({ lib, pkgs, ... }: {
      # Example: Enable AWS Module
      stack.aws.enable = true;
      Exampple: Add package
      devshell.packages = [ pkgs.nodejs_22 pkgs.bun ];
      Example: Add Hook
      devshell.hooks.before = lib.mkBefore [ "echo enter" ];
    })
  ];
};
```

# USAGE(DEVENV)

```nix
# devenv.nix
{ inputs, ... }: {
  imports = [
    inputs.stack.devenvModules.default
    inputs.stack.lib.devshellModules.aws
  ];

  stack.aws.enable = true;
}
```
