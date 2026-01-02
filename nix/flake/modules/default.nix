# ==============================================================================
# default.nix
#
# Canonical flake outputs for stackpanel modules. This file exports all module
# types that consumers can import into their configurations.
#
# Exports:
#   - devenvModules: For devenv users (yaml or flake-parts)
#   - flakeModules: For flake-parts users
#
# Usage in consumer flake:
#   devenv.shells.default = {
#     imports = [ inputs.stackpanel.devenvModules.default ];
#   };
# ==============================================================================
{
  inputs,
  devshell,
  ...
}:
{
  devenvModules = {
    # Main devenv module with stackpanel.* options
    default = import ./devenv.nix { inherit devshell; };
  };

  flakeModules = {
    # Flake-parts module for stackpanel devshells
    devshell = import ./flake-parts.nix { inherit devshell; };
  };
}
