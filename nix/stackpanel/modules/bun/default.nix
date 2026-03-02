# ==============================================================================
# default.nix - Bun Module Entry Point
#
# Bun/TypeScript application support using bun2nix for hermetic packaging.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options, packages, scripts, health checks
# - ui.nix: UI panel definitions
#
# Usage:
#   stackpanel.modules.bun.enable = true;
#   stackpanel.apps.my-app = {
#     path = "apps/web";
#     bun.enable = true;
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
in
{
  imports = [
    ./module.nix
    ./catalog.nix
    ./ui.nix
  ];
}
