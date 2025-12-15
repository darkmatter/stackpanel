# Module index - import this to get all standalone modules
#
# These modules are standalone and don't require flake-parts.
# They follow the standard NixOS module pattern: { lib, config, pkgs, ... }
#
# For standalone use with lib.evalModules:
#   let
#     result = lib.evalModules {
#       modules = [
#         inputs.stackpanel.nixosModules.default
#         { config.stackpanel.enable = true; }
#         { config._module.args.pkgs = pkgs; }
#       ];
#     };
#   in result.config.stackpanel.packages
#
# For flake-parts users:
#   imports = [ inputs.stackpanel.flakeModules.default ];
#
# For devenv users:
#   imports = [ stackpanel/devenvModules/default ]
#
{...}: {
  imports = [
    ./core
    ./secrets
    ./ci
    ./aws
    ./network
    ./theme
    # ./container # uncomment when ready
  ];
}
