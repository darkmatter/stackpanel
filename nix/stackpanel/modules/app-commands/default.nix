# ==============================================================================
# default.nix - App Commands Module Entry Point
#
# Nix-native app commands for build, dev, test, lint, format operations.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options, derivation builders, flake outputs
# - ui.nix: UI panel definitions
#
# Usage:
#   stackpanel.apps.web = {
#     path = "apps/web";
#     commands = {
#       dev = { command = "bun run dev"; };
#       build = { command = "bun run build"; };
#     };
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
    ./ui.nix
  ];
}
