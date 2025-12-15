# Theme module - starship prompt theming and shell customizations
# Standalone module - no flake-parts dependency
#
# Usage:
#   stackpanel.theme = {
#     enable = true;
#     # Optional: custom starship config
#     starshipConfig = ./my-starship.toml;
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.theme;

  # Import shared theme library
  themeLib = import ../../lib/theme.nix {inherit pkgs lib;};

  # Create theme using shared library
  starshipTheme = themeLib.mkStarshipTheme {configFile = cfg.starshipConfig;};
in {
  options.stackpanel.theme = {
    enable = lib.mkEnableOption "stackpanel theme (starship prompt, etc.)";

    starshipConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Custom starship.toml config file. Uses stackpanel default if not set.";
    };

    # Internal options set by the module
    _starshipConfig = lib.mkOption {
      type = lib.types.path;
      internal = true;
      description = "The resolved starship config path";
    };

    _shellInit = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      internal = true;
      description = "Shell initialization function";
    };
  };

  config = lib.mkIf cfg.enable {
    # Export packages for use in devShells
    stackpanel.packages = {
      init-stackpanel-starship = starshipTheme.initStarship;
    };

    # Export the starship config path for use in shell hooks
    stackpanel.theme._starshipConfig = starshipTheme.config;
    stackpanel.theme._shellInit = starshipTheme.shellInit;
  };
}
