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
  ] ++ lib.optionals hasGeneratedProcessCompose [ genProcessComposePath ];

  # Example: Add config using module features
  # config = lib.mkIf config.stackpanel.enable {
  #   stackpanel.scripts.my-script = {
  #     exec = "echo Hello from module!";
  #   };
  # };
}
