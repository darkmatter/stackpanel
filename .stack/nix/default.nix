# ==============================================================================
# .stack/nix/default.nix
#
# Project-specific Nix modules that extend the stackpanel module system.
# Use this for config that needs pkgs, inputs, or conditionals -- things
# that cannot be expressed in the plain-attrset config.nix.
#
# Available arguments:
#   - config:  The current stackpanel configuration
#   - options: All stackpanel option definitions
#   - lib:     Nixpkgs lib (mkIf, mkOption, types, etc.)
#   - pkgs:    Nixpkgs package set
#   - inputs:  Flake inputs (available but not used here currently)
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
  # This allows the web UI to generate config that takes effect on rebuild
  genProcessComposePath = ../gen/process-compose.nix;
  hasGeneratedProcessCompose = builtins.pathExists genProcessComposePath;
in
{
  imports = [
    ./generate-docs.nix
    ./generate-config-example.nix
    ./prek-wrapper.nix
  ]
  ++ lib.optionals hasGeneratedProcessCompose [ genProcessComposePath ];

  # Config that requires pkgs (not serializable in config.nix)
  config = lib.mkIf config.stackpanel.enable {
    # PostgreSQL package - requires pkgs, so lives here instead of config.nix
    stackpanel.globalServices.postgres.package = pkgs.postgresql_17;

    # Snapshot review tooling for Nix deployment regression tests.
    stackpanel.devshell.packages = [
      inputs.namaka.packages.${pkgs.system}.default
    ];

    # Runtime dependencies of `stackpanel` CLI.
    # Declaring them as runtimeInputs has two effects:
    #   1. nix build .#stackpanel-go → binary is wrapped so it finds these tools
    #      at their Nix store paths, no PATH setup required.
    #   2. devshell → tools are in PATH for `go run .` and interactive use.
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
