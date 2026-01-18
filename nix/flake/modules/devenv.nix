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
#   config.stackpanel.devshell.packages    → devenv packages
#   config.stackpanel.devshell.env         → devenv env
#   config.stackpanel.devshell.hooks.*     → devenv enterShell (before/main/after phases)
#   config.stackpanel.devshell.commands    → devenv scripts
#   config.stackpanel.scripts              → devenv scripts
#   config.stackpanel.outputs              → devenv outputs
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

  tasksFromCommands = config.stackpanel.devshell._tasks or { };
  tasks = tasksFromCommands // (config.stackpanel.tasks or { });

  scriptsFromStackpanel = config.stackpanel.devshell._scripts or { };

  # Top-level stackpanel.scripts (user-defined)
  userScripts = config.stackpanel.scripts or { };

  mkTaskCommand = name: {
    exec = ''
      if command -v tasks >/dev/null 2>&1; then
        exec tasks run ${lib.escapeShellArg name} -- "$@"
      elif command -v devenv-tasks-fast-build >/dev/null 2>&1; then
        exec devenv-tasks-fast-build run ${lib.escapeShellArg name} -- "$@"
      elif command -v devenv >/dev/null 2>&1; then
        exec devenv tasks run ${lib.escapeShellArg name} -- "$@"
      else
        echo "error: no devenv task runner found (tasks or devenv)" >&2
        exit 127
      fi
    '';
  };

  scriptsFromCommands = lib.mapAttrs (name: _cmd: mkTaskCommand name) tasksFromCommands;

  # Merge all script sources: commands → internal scripts → user scripts
  scripts = scriptsFromCommands // scriptsFromStackpanel // userScripts;

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
    tasks = tasks;
    scripts = scripts;
    outputs = outputs;
  };
}
