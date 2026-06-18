# ==============================================================================
# .stack/modules/default.nix
#
# Project-specific Nix modules that extend the stackpanel module system.
# Use this for config that needs pkgs, inputs, or conditionals — things
# that cannot be expressed in the plain-attrset config.nix.
#
# IMPORTANT (separation of concerns):
#   - Code under `nix/` outside `nix/internal/` is considered user-facing /
#     part of the stackpanel framework that external projects consume.
#   - Code under `nix/internal/` is for developing stackpanel itself only.
#   - The generators below are MAINTAINER tools. They keep the user-visible
#     starter templates (nix/flake/templates) and the embedded content in the
#     CLI binary up to date with the option schema.
#   - They are explicitly imported from nix/internal here rather than living
#     directly under .stack/modules, so that .stack/modules remains the place
#     for *project* configuration, not stackpanel-repo maintenance scripts.
#
# Available arguments:
#   - config, options, lib, pkgs, inputs
# ==============================================================================
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Import generated process-compose config if it exists
  genProcessComposePath = ../gen/process-compose.nix;
  hasGeneratedProcessCompose = builtins.pathExists genProcessComposePath;

  # Internal-only devshell extensions (stackpanel maintainers).
  # These are not shipped to users and make repo-layout assumptions.
  internalGenerators = [
    ../../nix/internal/devshell/scripts/generate-docs.nix
    ../../nix/internal/devshell/scripts/generate-config-example.nix
    ../../nix/internal/devshell/scripts/generate-template-configs.nix
  ];
in
{
  imports = [
    ./prek-wrapper.nix
  ]
  ++ internalGenerators
  ++ lib.optionals hasGeneratedProcessCompose [ genProcessComposePath ];

  # Config that requires pkgs (not serializable in config.nix)
  config = lib.mkIf config.stackpanel.enable {
    # PostgreSQL package - requires pkgs, so lives here instead of config.nix
    stackpanel.globalServices.postgres.package = pkgs.postgresql_17;

    # Snapshot review tooling for Nix deployment regression tests.
    stackpanel.devshell.packages = [
      inputs.namaka.packages.${pkgs.system}.default
    ];

    # Wrap the stackpanel-go binary so it finds colmena and nixos-anywhere at
    # their Nix store paths even outside of a devshell (e.g. nix run / nix build).
    # The deploy module separately injects these into the devshell of any repo
    # that configures a NixOS deployment backend, so users don't need to add them
    # manually in their own .stack/modules/.
    #
    # Use pkgs.colmena (from nixpkgs, binary-cached) for the CLI tool.
    # The flake input's colmena.lib.makeHive is only needed at eval time
    # in global-outputs.nix and doesn't require the binary package.
    stackpanel.apps."stackpanel-go".go.runtimeInputs = [
      pkgs.colmena
      pkgs.nixos-anywhere
    ];
  };
}
