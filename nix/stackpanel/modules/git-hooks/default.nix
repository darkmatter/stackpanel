# ==============================================================================
# default.nix - Git Hooks Module Entry Point
#
# Git hooks integration using stackpanel app tooling wrappers.
# Handles pre-commit linters, formatters, and pre-push build steps.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options and configuration
# - ui.nix: UI panel definitions
#
# Usage:
#   stackpanel.git-hooks.enable = true;
#   stackpanel.git-hooks.extraLinters = [ myLinter ];
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
