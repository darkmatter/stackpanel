# ==============================================================================
# devenv-devshell-adapter.nix
#
# Low-level adapter that bridges stackpanel's devshell module system with
# devenv's native configuration. Maps devshell options to devenv equivalents.
#
# Mappings:
#   config.devshell.packages    → devenv packages
#   config.devshell.env         → devenv env
#   config.devshell.hooks.*     → devenv enterShell (before/main/after phases)
#   config.devshell.commands    → devenv scripts
#
# Imports the core stackpanel devshell module for option definitions.
# This is a lower-level module; prefer using modules/devenv/default.nix.
# ==============================================================================
{ devshell }:
{ config, lib, pkgs, ... }:
let
  hooks = config.devshell.hooks;

  enterShell = lib.concatStringsSep "\n\n" (lib.flatten [
    hooks.before
    hooks.main
    hooks.after
  ]);

  scripts =
    lib.mapAttrs (name: _cmd: {
      exec = ''exec ${name} "$@"'';
    }) (config.devshell.commands or {});
in
{
  # Import the core stackpanel devshell module
  imports = [
    devshell.core
  ];

  config = {
    packages = config.devshell.packages ++ (config.devshell._commandPkgs or []);
    env = config.devshell.env;
    enterShell = enterShell;
    scripts = scripts;
  };
}