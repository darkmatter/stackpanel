# ==============================================================================
# devenv.nix - Devenv Adapter
#
# Bridges stackpanel's module system with devenv's native configuration.
# This is the ONLY file that has devenv-specific knowledge.
#
# Import flow:
#   User's devenv config
#     → this adapter
#       → nix/stackpanel/default.nix (core module system, devenv-agnostic)
#
# Mappings:
#   config.stackpanel.devshell.packages    → devenv packages (includes scripts package)
#   config.stackpanel.devshell.env         → devenv env
#   config.stackpanel.devshell.hooks.*     → devenv enterShell (before/main/after phases)
#   config.stackpanel.scripts              → scripts package in devshell (handled by scripts.nix)
#   config.stackpanel.outputs              → devenv outputs
#
# Scripts are handled by nix/stackpanel/devshell/scripts.nix which creates a
# single package containing all scripts in bin/. This package is automatically
# added to devshell.packages when scriptsConfig.enable is true (default).
#
# Usage in flake-parts:
#   devenv.shells.default = {
#     imports = [ inputs.stackpanel.devenvModules.default ];
#     stackpanel.enable = true;
#     stackpanel.theme.enable = true;
#   };
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  hooks = config.stackpanel.hooks or config.stackpanel.devshell.hooks;

  enterShell = lib.concatStringsSep "\n\n" (
    lib.flatten [
      hooks.before
      hooks.main
      hooks.after
    ]
  );

  # Note: stackpanel.tasks are for Turborepo integration, not devenv tasks.
  # Devenv tasks have a different schema (exec, before, after).
  # If you need devenv-specific tasks, define them directly in your devenv.nix.

  # Outputs from stackpanel.outputs
  outputs = config.stackpanel.outputs or { };
in
{
  # Single entrypoint - imports all stackpanel modules
  # Features only activate when their .enable option is set
  # Note: devenv provides pkgs via its module system
  imports = [
    ../../stackpanel
  ];

  config = {
    packages = config.stackpanel.devshell.packages;
    env = config.stackpanel.devshell.env;
    enterShell = enterShell;
    outputs = outputs;
  };
}
