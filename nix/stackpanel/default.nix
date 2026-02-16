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

    # App-level features (Caddy vhost registration, CI)
    ./apps/apps.nix

    # Feature modules (all adapter-agnostic)
    ./network # step-ca, ports
    ./services # aws, caddy, global-services
    ./secrets # SOPS helper
    ./sst # SST infrastructure provisioning
    ./alchemy # Alchemy IaC shared configuration (@gen/alchemy)
    ./infra # Alchemy-based infrastructure module system
    ./docker # Dockerfile fallback (skopeo, OCI images)
    ./containers # nix2container via devenv (primary container building)
    ./deployment # Deployment providers (Fly.io, etc.)
    ./languages # Language toolchains (go, javascript, typescript)
    ./tui # TUI components
    ./ide # IDE integration (VS Code)
    ./docs # Documentation generation (README, etc.)

    # Feature modules - auto-discovered from ./modules/
    # Supports both single files (module.nix) and directories (module/default.nix)
    # See modules/default.nix for the discovery logic
    ./modules

    # NOTE: Devenv integration modules (devenv-services.nix, devenv-languages.nix,
    # devenv-pre-commit.nix) are NOT auto-imported here. They require devenvSchema
    # to be passed via specialArgs, which only happens when using wrapDevenv.
    # Import them explicitly when using lib.wrapDevenv:
    #
    #   wrappedDevenv = inputs.stackpanel.lib.wrapDevenv { inherit inputs; };
    #   devShells.default = wrappedDevenv.lib.mkShell { ... };
    #
    # The wrapped lib automatically includes these modules.
  ];

  config.stackpanel.devshell.hooks.after = [
    initshell
  ];
}
