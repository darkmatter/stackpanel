# ==============================================================================
# default.nix - Entrypoints Module Entry Point
#
# Per-app entrypoint shell scripts with devshell and secrets loading.
#
# IMPORTANT: Entrypoints ONLY inject environment variables. They do NOT run
# commands. The caller is responsible for running the actual command after
# sourcing the entrypoint.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options and script generation
# - ui.nix: UI panel definitions
#
# Usage (source the entrypoint, then run your command):
#   source packages/scripts/entrypoints/web.sh --dev
#   bun run dev
#
# Or inline:
#   source packages/scripts/entrypoints/web.sh --dev && bun run dev
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
