# ==============================================================================
# default.nix
#
# Module exports for stackpanel flake. Provides the devenvModules attribute set
# that consumers can import into their devenv configurations.
#
# Exports:
#   - devenvModules.default: Main devenv adapter with stackpanel.* options
#
# Usage in consumer flake:
#   devenv.shells.default = {
#     imports = [ inputs.stackpanel.devenvModules.default ];
#   };
# ==============================================================================
{ inputs, devshell }:
{
  devenvModules = {
    default = import ./devenv/default.nix { inherit devshell; };
  };
}