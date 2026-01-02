# ==============================================================================
# theme.nix
#
# Theme options - Starship prompt customization for devenv shells.
#
# Configures the Starship prompt for a consistent and informative shell
# experience. Uses a Stackpanel-specific theme by default.
#
# Options:
#   - enable: Enable Starship prompt for stackpanel devenv
#   - config-file: Custom starship.toml config file (optional)
#
# When enabled without a custom config, uses the Stackpanel default theme
# which shows relevant information like git status, Nix shell indicator,
# and project-specific context.
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.theme = {
    enable = lib.mkEnableOption "Starship prompt for stackpanel devenv";

    config-file = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Custom starship.toml config file (uses stackpanel default if not set)";
    };
  };
}
