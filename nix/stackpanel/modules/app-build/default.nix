# ==============================================================================
# default.nix - App Build Module Entry Point
#
# Nix-based app packaging and flake derivation routing.
#
# Provides per-app `build.*` options (serializable for UI) and Nix-only
# `package`/`checkPackage` options (set by language modules). Routes
# non-null packages to flake outputs, checks, and apps.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options, routing logic
#
# Usage:
#   # Language modules auto-set these:
#   stackpanel.apps.my-app.build.enable = true;
#   stackpanel.apps.my-app.package = <derivation>;
#
#   # Users can override build options:
#   stackpanel.apps.my-app.build.srcRoot = "apps/my-app";
#   stackpanel.apps.my-app.build.outputVersion = "1.2.0";
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
  ];
}
