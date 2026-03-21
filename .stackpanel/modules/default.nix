# ==============================================================================
# .stackpanel/modules/default.nix
#
# Stackpanel user modules - evaluated with full NixOS module context.
#
# This file and all imports have access to:
#   - config: The current stackpanel configuration
#   - options: All stackpanel option definitions
#   - lib: Nixpkgs lib (mkIf, mkOption, types, etc.)
#   - pkgs: Nixpkgs package set
#
# Use this for:
#   - Complex configuration that needs conditionals (lib.mkIf)
#   - Custom scripts with dependencies (stackpanel.scripts)
#   - Generated files (stackpanel.files.entries)
#   - Anything that needs access to evaluated config values
#
# For simple config values, use config.nix instead.
# ==============================================================================
{
  config,
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
    ./prek-wrapper.nix
  ]
  ++ lib.optionals hasGeneratedProcessCompose [ genProcessComposePath ];

  # Config that requires pkgs (not serializable in config.nix)
  config = lib.mkIf config.stackpanel.enable {
    # PostgreSQL package - requires pkgs, so lives here instead of config.nix
    stackpanel.globalServices.postgres.package = pkgs.postgresql_17;

    # nixos-anywhere is needed by `stackpanel provision`.
    # Declaring it as a runtimeInput has two effects:
    #   1. nix build .#stackpanel-go → binary is wrapped so it finds nixos-anywhere
    #      at its Nix store path, no PATH setup required.
    #   2. devshell → nixos-anywhere is in PATH for `go run .` and interactive use.
    stackpanel.apps."stackpanel-go".go.runtimeInputs = [ pkgs.nixos-anywhere ];
  };
}
