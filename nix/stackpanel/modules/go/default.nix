# ==============================================================================
# default.nix - Go Module Entry Point
#
# Go application support using gomod2nix for hermetic packaging.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options, packages, scripts, health checks
# - ui.nix: UI panel definitions
#
# Usage:
#   stackpanel.apps.my-app = {
#     path = "apps/my-app";
#     go.enable = true;
#   };
#
# appBuildProviders.go.my-app supplies the package for `nix build .#my-app`.
# Go dev environments and explicit test derivations use go.packages.devEnvs
# and go.packages.tests, keyed by app name; tests export as checks.<app>-test.
# ==============================================================================
{
  ...
}:
{
  imports = [
    ./module.nix
    ./ui.nix
  ];
}
