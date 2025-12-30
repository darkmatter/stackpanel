# ==============================================================================
# devenv.nix
#
# Main devenv module for stackpanel. Bridges stackpanel's module system
# with devenv's native configuration.
#
# Uses nix/stackpanel/default.nix as the single entrypoint for all features.
# Features only activate when their .enable option is set.
#
# Mappings:
#   config.stackpanel.devshell.packages    → devenv packages
#   config.stackpanel.devshell.env         → devenv env
#   config.stackpanel.devshell.hooks.*     → devenv enterShell (before/main/after phases)
#   config.stackpanel.devshell.commands    → devenv scripts
#
# Usage in flake-parts:
#   devenv.shells.default = {
#     imports = [ inputs.stackpanel.devenvModules.default ];
#     stackpanel.enable = true;
#     stackpanel.theme.enable = true;
#     # etc.
#   };
# ==============================================================================
{
  config,
  lib,
  ...
}:
let
  hooks = config.stackpanel.devshell.hooks;

  enterShell = lib.concatStringsSep "\n\n" (
    lib.flatten [
      hooks.before
      hooks.main
      hooks.after
    ]
  );

  scripts = lib.mapAttrs (name: _cmd: {
    exec = ''exec ${name} "$@"'';
  }) (config.stackpanel.devshell.commands or { });
in
{
  # Single entrypoint - imports all stackpanel modules
  # Features only activate when their .enable option is set
  imports = [
    ../../stackpanel
  ];

  config = {
    packages = config.stackpanel.devshell.packages ++ (config.stackpanel.devshell._commandPkgs or [ ]);
    env = config.stackpanel.devshell.env;
    enterShell = enterShell;
    scripts = scripts;
  };
}
