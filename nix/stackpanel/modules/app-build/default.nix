# ==============================================================================
# default.nix - App Build Module Entry Point
#
# Nix-based app packaging and flake derivation routing.
#
# Provides per-app `build.*` options (serializable for UI) and Nix-only
# `package`/`checkPackage` overrides. Routes runtime and manually supplied
# packages to flake outputs, checks, and apps.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options, routing logic
#
# Usage:
#   # Runtime modules publish packages keyed by app name:
#   stackpanel.appBuildProviders.my-runtime.my-app = <derivation>;
#
#   # Users can override build options:
#   stackpanel.apps.my-app.build.srcRoot = "apps/my-app";
#   stackpanel.apps.my-app.build.outputVersion = "1.2.0";
# ==============================================================================
{
  ...
}:
{
  imports = [
    ./module.nix
  ];
}
