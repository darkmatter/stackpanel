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
#   - packages → devenv packages (includes scripts package)
#   - env → devenv env
#   - hooks → devenv enterShell
#
# Scripts are handled by nix/stackpanel/devshell/scripts.nix which creates a
# single package with all scripts in bin/, added to devshell.packages.
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
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;
in
{
  imports = [
    # Import stackpanel core (options + core config)
    ../stackpanel
  ];

  # Wire stackpanel.devshell.* config to devenv's native options
  config = lib.mkIf (cfg.enable or false) {
    # Map stackpanel.devshell packages to devenv packages
    # (scripts package is already included via scripts.nix)
    packages = cfg.devshell.packages;

    # Map stackpanel.devshell env to devenv env
    env = cfg.devshell.env;

    # Map stackpanel.devshell hooks to devenv enterShell
    enterShell = lib.concatStringsSep "\n\n" (
      lib.flatten [
        (cfg.devshell.hooks.before or [ ])
        (cfg.devshell.hooks.main or [ ])
        (cfg.devshell.hooks.after or [ ])
      ]
    );
  };
}
