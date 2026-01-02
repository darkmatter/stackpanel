# ==============================================================================
# devshell.nix
#
# Local development shell configuration for the stackpanel repository itself.
# This is the "dogfooding" config - we use our own modules to develop stackpanel.
#
# Import flow:
#   flake.nix (devenv.shells.default.imports)
#     → this file
#       → nix/flake/modules/devenv.nix (devenv adapter)
#         → nix/stackpanel/default.nix (core stackpanel module system)
#
# Usage in flake.nix:
#   devenv.shells.default.imports = [ (import ./nix/internal/devshell.nix { inherit inputs; }) ];
# ==============================================================================
{ inputs }:
{ pkgs, lib, config, ... }:
let
  # Import config.nix which returns { stackpanel, devenv, git-hooks }
  fullConfig = import ./main.nix { inherit pkgs lib config inputs; };

  # Extract each section with defaults
  stackpanelConfig = fullConfig.stackpanel or {};
  devenvConfig = fullConfig.devenv or {};
  gitHooksConfig = fullConfig.git-hooks or {};
in
{
  imports = [
    # Devenv adapter - bridges stackpanel.devshell.* options to devenv
    # The adapter imports nix/stackpanel/default.nix internally
    # This MUST be imported for `stackpanel.*` options to be available in devenv
    ../flake/modules/devenv.nix

    # Internal project-specific devenv modules (apps/docs, tools, etc.)
    ./devenv/devenv.nix
  ];

  # Stackpanel options (from .stackpanel/config.nix)
  stackpanel = stackpanelConfig;

  # ===========================================================================
  # Devenv-specific options (from .stackpanel/config.nix devenv section)
  # These are native devenv options, not stackpanel options
  # ===========================================================================
} // devenvConfig
