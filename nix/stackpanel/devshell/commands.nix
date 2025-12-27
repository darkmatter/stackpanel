# ==============================================================================
# commands.nix
#
# Custom shell command builder for devshell.
#
# This module transforms stackpanel.devshell.commands definitions into
# executable shell scripts that are added to the development environment PATH.
# Each command is wrapped with proper error handling and environment setup.
#
# Commands are defined with exec, runtimeInputs, and env attributes, and
# are automatically made available as shell commands.
# ==============================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.stackpanel.devshell;

  mkCmd = name: cmd:
    pkgs.writeShellApplication {
      name = name;
      runtimeInputs = cmd.runtimeInputs;
      text = ''
        set -euo pipefail
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') cmd.env)}
        ${cmd.exec}
      '';
    };

  cmdPkgs = lib.mapAttrsToList mkCmd cfg.commands;
in
{
  imports = [
    ../core/options
  ];
  config.stackpanel.devshell._commandPkgs = cmdPkgs;
}