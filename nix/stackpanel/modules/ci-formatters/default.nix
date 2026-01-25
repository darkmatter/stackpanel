# ==============================================================================
# default.nix - CI Formatters Module Entry Point
#
# Flake checks for formatter tooling.
# Runs wrapped formatters in a writable copy of the repo for CI usage.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options and configuration
# - ui.nix: UI panel definitions
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
    ./ui.nix
  ];
}
