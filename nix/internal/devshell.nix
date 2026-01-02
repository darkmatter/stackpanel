# ==============================================================================
# devshell.nix
#
# Local development shell configuration for the stackpanel repository itself.
# This is the "dogfooding" config - we use our own modules to develop stackpanel.
#
# Architecture:
#   1. Use merged-config.nix as single source of truth
#   2. Extract devshell outputs from stackpanel
#   3. Merge with devenv config (explicit inclusion only)
#
# This keeps stackpanel and devenv separate:
#   - Stackpanel evaluates its modules independently
#   - Devenv only receives final devshell outputs + devenv-specific config
#   - No stackpanel options leak into devenv's module system
#
# Usage in flake.nix:
#   devenv.shells.default.imports = [ (import ./nix/internal/devshell.nix { inherit inputs; }) ];
# ==============================================================================
{ inputs, mergedConfig ? null }:
{ pkgs, lib, config, ... }:
let
  # Import merged config (single source of truth)
  # Passed as parameter or imported directly
  actualMergedConfig = 
    if mergedConfig != null 
    then mergedConfig
    else import ../../nix/flake/merged-config.nix { inherit pkgs lib inputs; };

  # Extract sections
  stackpanelConfig = actualMergedConfig.stackpanel;
  devenvConfig = actualMergedConfig.devenv;
  
  # Extract only the devshell outputs from stackpanel
  devshellOutputs = stackpanelConfig.devshell;
in
{
  imports = [
    # Internal project-specific devenv modules (apps/docs, tools, etc.)
    ./devenv/devenv.nix
  ];

  # Apply stackpanel devshell outputs directly to devenv
  # Note: Merge packages from both stackpanel and devenv config
  packages = devshellOutputs.packages 
    ++ (devshellOutputs._commandPkgs or [])
    ++ (devenvConfig.packages or []);
  
  env = devshellOutputs.env // (devenvConfig.env or {});
  
  enterShell = lib.concatStringsSep "\n\n" (
    lib.flatten [
      devshellOutputs.hooks.before
      devshellOutputs.hooks.main
      devshellOutputs.hooks.after
    ]
  ) + "\n\n" + (devenvConfig.enterShell or "");
  
  scripts = lib.mapAttrs (name: _cmd: {
    exec = ''exec ${name} "$@"'';
  }) (devshellOutputs.commands or {});

  # ===========================================================================
  # Devenv-specific options (from .stackpanel/config.nix devenv section)
  # These are native devenv options, not stackpanel options (except packages/env/enterShell which are merged above)
  # ===========================================================================
} // (builtins.removeAttrs devenvConfig ["packages" "env" "enterShell"])
