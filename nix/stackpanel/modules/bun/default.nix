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
#   stackpanel.apps.my-app = {
#     path = "apps/web";
#     bun.enable = true;
#   };
#
# appBuildProviders.bun.my-app supplies the package for `nix build .#my-app`.
# Set stackpanel.bun.package to pin the runtime. The bundled installer can be
# disabled with stackpanel.bun.install.enable = false, or restricted to the
# local cache with install.offline = true. An active JavaScript pack installer
# takes precedence, so the shell never installs twice.
# ==============================================================================
{
  ...
}:
{
  imports = [
    ./module.nix
    ./catalog.nix
    ./ui.nix
  ];
}
