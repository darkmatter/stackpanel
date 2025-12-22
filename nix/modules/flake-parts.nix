# Flake-parts integration for stackpanel
#
# This module provides stackpanel for flake users via devenv.
# It wraps devenv to provide the same environment as `devenv shell`.
#
# Usage in flake.nix:
#   {
#     inputs = {
#       nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
#       flake-parts.url = "github:hercules-ci/flake-parts";
#       devenv.url = "github:cachix/devenv";
#       stackpanel.url = "github:darkmatter/stackpanel";
#     };
#
#     outputs = inputs@{ flake-parts, ... }:
#       flake-parts.lib.mkFlake { inherit inputs; } {
#         imports = [
#           inputs.devenv.flakeModule
#           inputs.stackpanel.flakeModules.default
#         ];
#
#         perSystem = { ... }: {
#           devenv.shells.default = {
#             imports = [ inputs.stackpanel.devenvModules.default ];
#             # Your stackpanel config here
#             stackpanel.enable = true;
#           };
#         };
#       };
#   }
#
# This is a thin wrapper - all the real work is in the devenv modules.
# For most users, just use devenv directly with devenv.yaml.
#
{
  lib,
  flake-parts-lib,
  inputs,
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
    # The main work is done by importing stackpanel.devenvModules.default
    # into your devenv.shells.default configuration.
    #
    # This module just provides helper options if needed.
  });
}
