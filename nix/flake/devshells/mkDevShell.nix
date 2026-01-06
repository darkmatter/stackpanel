# ==============================================================================
# mkDevShell.nix
#
# Factory function for creating Nix development shells with stackpanel modules.
# Uses lib.evalModules to evaluate a set of NixOS-style modules and produces
# a pkgs.mkShell derivation with packages, hooks, and environment variables.
#
# Usage:
#   mkDevShell { inherit pkgs; } {
#     modules = [ ./my-module.nix ];
#     specialArgs = { myArg = "value"; };
#     extraPackages = [ pkgs.jq ];  # additional packages to include
#   }
#
# The resulting shell includes:
#   - packages and nativeBuildInputs from devshell config
#   - environment variable exports
#   - shell hooks (before, main, after phases)
#   - passthru with devshellConfig and moduleConfig for introspection
# ==============================================================================
{ pkgs }:
{
  modules ? [ ],
  specialArgs ? { },
  extraPackages ? [ ],
}:
let
  lib = pkgs.lib;

  evaluated = lib.evalModules {
    modules = [
      # Always-on stackpanel core
      ../../stackpanel/core/default.nix
    ]
    ++ modules;
    specialArgs = {
      inherit pkgs;
    }
    // specialArgs;
  };

  # Access stackpanel.devshell config
  cfg = evaluated.config.stackpanel.devshell;

  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') cfg.env
  );

  shellHook = lib.concatStringsSep "\n\n" (
    lib.flatten [
      # mkShell needs env exports here
      envExports
      cfg.hooks.before
      cfg.hooks.main
      cfg.hooks.after
    ]
  );
in
pkgs.mkShell {
  packages = cfg.packages ++ (cfg._commandPkgs or [ ]) ++ extraPackages;
  nativeBuildInputs = cfg.nativeBuildInputs;
  buildInputs = cfg.buildInputs;
  shellHook = shellHook;

  passthru.devshellConfig = cfg;
  passthru.moduleConfig = evaluated.config;
  passthru.extraPackages = extraPackages;
}
