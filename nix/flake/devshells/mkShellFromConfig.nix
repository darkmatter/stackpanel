# ==============================================================================
# mkShellFromConfig.nix
#
# Creates a nix shell from an already-evaluated stackpanel.devshell config.
# Unlike mkDevShell.nix which runs evalModules, this takes a pre-evaluated
# devshell configuration and builds a shell directly.
#
# Usage:
#   mkShellFromConfig { inherit pkgs; } {
#     devshellConfig = config.stackpanel.devshell;
#     extraPackages = [ pkgs.jq ];
#   }
#
# The resulting shell includes:
#   - packages from devshellConfig.packages
#   - environment variable exports
#   - shell hooks (before, main, after phases)
# ==============================================================================
{ pkgs }:
{
  devshellConfig,
  extraPackages ? [ ],
}:
let
  lib = pkgs.lib;
  cfg = devshellConfig;

  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') (cfg.env or { })
  );

  shellHook = lib.concatStringsSep "\n\n" (
    lib.flatten [
      envExports
      (cfg.hooks.before or [ ])
      (cfg.hooks.main or [ ])
      (cfg.hooks.after or [ ])
    ]
  );
in
pkgs.mkShell {
  packages = (cfg.packages or [ ]) ++ (cfg._commandPkgs or [ ]) ++ extraPackages;
  nativeBuildInputs = cfg.nativeBuildInputs or [ ];
  buildInputs = cfg.buildInputs or [ ];
  shellHook = shellHook;

  passthru = {
    devshellConfig = cfg;
  };
}
