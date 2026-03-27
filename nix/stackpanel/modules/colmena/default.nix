# ==============================================================================
# default.nix - Colmena Module Entry Point
#
# NixOS fleet deployment orchestration via Colmena.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options, scripts, health checks, module registration
# - ui.nix: UI panel definitions (status + config form)
#
# Usage:
#   stackpanel.colmena = {
#     enable = true;
#     flake = ".#colmena";
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./module.nix
    ./ui.nix
  ];
}
