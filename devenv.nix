# ==============================================================================
# devenv.nix
#
# Standalone devenv configuration for `devenv shell` workflow.
#
# This file is for the `devenv shell` command (with devenv.yaml).
# For `nix develop`, the flakeModule creates a pure stackpanel shell.
#
# Architecture:
#   - Imports stackpanel's devenv adapter (bridges stackpanel → devenv)
#   - Loads stackpanel config from .stackpanel/_internal.nix
#   - Imports project-specific devenv modules (processes, services)
#
# Usage:
#   devenv shell    # Enter the devenv shell
#   devenv up       # Start processes (web, docs, etc.)
# ==============================================================================
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [
    # Devenv adapter - bridges stackpanel.devshell.* to devenv options
    ./nix/flake/modules/devenv.nix

    # Project-specific devenv modules (processes, services, languages)
    ./nix/internal/devenv/devenv.nix
  ];

  # Load stackpanel config from .stackpanel/
  stackpanel = import ./.stackpanel/_internal.nix { inherit pkgs lib; };

  # Fix for devenv 1.11.2 + rolling nixpkgs: nixseparatedebuginfod was renamed
  overlays = [
    (final: prev: {
      nixseparatedebuginfod = prev.nixseparatedebuginfod2 or prev.nixseparatedebuginfod or null;
    })
  ];

  # Workaround for devenv bug: process-compose.nix accesses configFile
  # before checking if enable is true
  process.managers.process-compose.configFile = lib.mkForce (
    pkgs.writeText "empty-pc.yaml" "version: '0.5'\nprocesses: {}"
  );
}
