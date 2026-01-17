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
{
  imports = [
    ./generate-docs.nix
  ];

  # Example: Add config using module features
  # config = lib.mkIf config.stackpanel.enable {
  #   stackpanel.scripts.my-script = {
  #     exec = "echo Hello from module!";
  #   };
  # };
}
