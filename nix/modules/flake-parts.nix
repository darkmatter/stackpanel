# Flake-parts integration wrapper
#
# This module wraps the standalone stackpanel modules for use with flake-parts.
# It exposes all stackpanel options under perSystem.stackpanel.*
#
# Usage in flake.nix:
#   imports = [ inputs.stackpanel.flakeModules.default ];
#
#   perSystem = { pkgs, config, ... }: {
#     stackpanel = {
#       enable = true;
#       aws.certAuth = { ... };
#       network.step = { ... };
#       secrets = { ... };
#     };
#   };
#
{
  lib,
  flake-parts-lib,
  ...
}: let
  inherit (flake-parts-lib) mkPerSystemOption;
in {
  options.perSystem = mkPerSystemOption ({
    config,
    pkgs,
    lib,
    ...
  }: {
    imports = [
      # Import all standalone modules
      ./core
      ./aws
      ./network
      ./secrets
      ./ci
      ./theme
    ];

    # Bridge stackpanel.packages to flake-parts packages output
    config.packages =
      lib.mkIf config.stackpanel.enable config.stackpanel.packages;
  });
}
