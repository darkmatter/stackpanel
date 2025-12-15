# Theme module for devenv
#
# Usage in devenv.nix:
#   stackpanel.theme.enable = true;
#
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.stackpanel.theme;

  # Import shared theme library
  themeLib = import ../../lib/theme.nix {inherit pkgs lib;};
  starshipTheme = themeLib.mkStarshipTheme {};
in {
  options.stackpanel.theme = {
    enable = lib.mkEnableOption "Starship prompt for stackpanel devenv";

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Custom starship.toml config file (uses stackpanel default if not set)";
    };
  };

  config = lib.mkIf cfg.enable {
    packages = starshipTheme.requiredPackages;

    enterShell = ''
      # syntax: bash
      export STARSHIP_CONFIG=$DEVENV_STATE/starship.toml
      install -m 644 ${
        if cfg.configFile != null
        then cfg.configFile
        else starshipTheme.config
      } $DEVENV_STATE/starship.toml
      eval "$(starship init $SHELL)"
    '';
  };
}
