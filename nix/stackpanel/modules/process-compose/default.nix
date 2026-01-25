# ==============================================================================
# default.nix - Process Compose Module Entry Point
#
# Process orchestration with auto-generated app processes.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options, process generation, devenv compatibility
# - ui.nix: UI panel definitions
#
# Usage:
#   # Apps automatically get dev processes
#   stackpanel.apps.web.path = "apps/web";
#   
#   # Then run `dev` in the devshell
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
