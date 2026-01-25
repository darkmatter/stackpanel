# ==============================================================================
# default.nix - Module Entry Point
#
# This is the main entry point for the module. It imports and composes all
# the module's components:
#
# - meta.nix: Static metadata (always loaded for discovery)
# - module.nix: Options and configuration
# - ui.nix: UI panel definitions (lazy loaded)
#
# For simple modules, you can inline everything here instead of splitting
# into separate files. The directory structure is recommended for:
# - Modules with per-app options
# - Modules with complex configuration
# - Modules that need extensive documentation
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
in
{
  imports = [
    ./module.nix
    ./ui.nix
  ];

  # The module.nix handles all configuration including module registration.
  # This file exists primarily as the entry point that composes the pieces.
  #
  # For modules that need additional setup, you can add config here:
  #
  # config = lib.mkIf config.stackpanel.modules.${meta.id}.enable {
  #   # Additional configuration that doesn't fit in module.nix
  # };
}
