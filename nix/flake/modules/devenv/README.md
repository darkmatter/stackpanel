# Devenv Adapter

Usage:

```nix
# devenv.nix
{ inputs, pkgs, ... }: {
  imports = [
    inputs.stackpanel.devenvModules.default
    inputs.stackpanel.lib.devshellModules.example
  ];
}
```