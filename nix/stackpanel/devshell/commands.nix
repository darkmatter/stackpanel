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
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.devshell;
  scriptsCfg = config.stackpanel.scripts or { };

  mkEnvExports =
    env:
    lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') env);

  mkTaskScript = cmd: ''
    set -euo pipefail
    ${lib.optionalString (cmd.runtimeInputs != [ ]) ''
      export PATH="${lib.makeBinPath cmd.runtimeInputs}:$PATH"
    ''}
    ${mkEnvExports cmd.env}
    ${cmd.exec}
  '';

  mkCmd =
    name: cmd:
    pkgs.writeShellApplication {
      name = name;
      runtimeInputs = cmd.runtimeInputs;
      text = ''
        set -euo pipefail
        ${mkEnvExports cmd.env}
        ${cmd.exec}
      '';
    };

  mkTask = name: cmd: {
    exec = mkTaskScript cmd;
  };

  pkgDefs = cfg.commands // scriptsCfg;
  cmdPkgs = lib.mapAttrsToList mkCmd pkgDefs;
  taskDefs = lib.mapAttrs mkTask cfg.commands;
  scriptDefs = lib.mapAttrs mkTask scriptsCfg;
in
{
  imports = [
    ../core/options
  ];
  config.stackpanel.devshell._commandPkgs = cmdPkgs;
  config.stackpanel.devshell._tasks = taskDefs;
  config.stackpanel.devshell._scripts = scriptDefs;
  config.stackpanel.devshell.hooks.after = [
    '' 
      echo "stackpanel commands loaded"
      stackpanel commands
    ''
  ];
}
