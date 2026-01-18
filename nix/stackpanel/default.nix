# ==============================================================================
# default.nix
#
# Main entry point for the stackpanel Nix module system.
#
# This module is ADAPTER-AGNOSTIC - it defines stackpanel.* options and
# populates stackpanel.devshell.* outputs, but does NOT depend on devenv,
# NixOS, or any other specific module system.
#
# Adapters (like nix/flake/modules/devenv.nix) import this and translate
# stackpanel.devshell.* to their specific output format.
#
# Import flow:
#   Adapter (devenv.nix, nixos.nix, etc.)
#     → this file (core module system)
#       → core/, network/, services/, etc.
#
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  initshell = lib.concatLines [
    ''
      echo "✅ Stackpanel Nix module system initialized"
    ''
  ];
in
{
  imports = [
    # Core devshell schema (packages, hooks, commands, files)
    ./devshell/core.nix

    # Core configuration and options
    ./core

    # Feature modules (all adapter-agnostic)
    ./network # step-ca, ports
    ./services # aws, caddy, global-services
    ./secrets # SOPS helper
    ./sst # SST infrastructure provisioning
    ./tui # TUI components
    ./ide # IDE integration (VS Code)
    ./modules/git-hooks.nix # git-hooks integration
    ./modules/ci-formatters.nix # CI formatter checks
    ./modules/go.nix # Go app support
    ./modules/process-compose.nix # App scripts + process-compose
    ./modules/turbo.nix # Turborepo task integration
    ./modules/example-extension.nix # Example extension demonstrating panels
  ];

  config.stackpanel.devshell.hooks.after = [
    initshell
  ];
}
