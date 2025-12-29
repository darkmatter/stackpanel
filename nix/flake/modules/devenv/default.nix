# ==============================================================================
# default.nix (devenv module)
#
# Primary devenv adapter module providing the stackpanel.* options namespace.
# This is the main entry point for using stackpanel features within devenv.
#
# Imports:
#   - stackpanel core options (stackpanel.*)
#   - recommended settings module (stackpanel.devenv.recommended)
#
# Wires stackpanel.devshell config to native devenv options:
#   - packages → devenv packages
#   - env → devenv env
#   - hooks → devenv enterShell
#   - commands → devenv scripts
#
# Usage in devenv.nix:
#   { inputs, ... }:
#   {
#     imports = [ inputs.stackpanel.devenvModules.default ];
#     stackpanel.enable = true;
#     stackpanel.apps.web = { domain = "myapp"; };
#   }
#
# Note: devenv.yaml is used for configuring inputs, not for stackpanel options.
# ==============================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.stackpanel;
in
{
  imports = [
    # Import stackpanel core (options + core config)
    ../../../stackpanel/core
    # Import service implementation modules (these add packages based on options)
    ../../../stackpanel/services/aws.nix
    ../../../stackpanel/services/caddy.nix
    ../../../stackpanel/services/global-services.nix
    ../../../stackpanel/network/network.nix
    ../../../stackpanel/tui/default.nix
    ../../../stackpanel/ide/ide.nix
    ../../../stackpanel/apps/apps.nix
    # Import recommended settings module (stackpanel.devenv.recommended)
    ./recommended.nix
  ];

  # Wire stackpanel.devshell.* config to devenv's native options
  config = lib.mkIf (cfg.enable or false) {
    # Map stackpanel.devshell packages to devenv packages
    packages = cfg.devshell.packages ++ (cfg.devshell._commandPkgs or []);

    # Map stackpanel.devshell env to devenv env
    env = cfg.devshell.env;

    # Map stackpanel.devshell hooks to devenv enterShell
    enterShell = lib.concatStringsSep "\n\n" (lib.flatten [
      (cfg.devshell.hooks.before or [])
      (cfg.devshell.hooks.main or [])
      (cfg.devshell.hooks.after or [])
    ]);

    # Map stackpanel.devshell commands to devenv scripts
    scripts = lib.mapAttrs (_: cmd: { exec = cmd.exec; })
      (cfg.devshell.commands or {});
  };
}