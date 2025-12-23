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
  themeLib = import ../lib/theme.nix {inherit pkgs lib;};
  starshipTheme = themeLib.mkStarshipTheme {};
in {
  options.stackpanel.theme = {
    enable = lib.mkEnableOption "Starship prompt for stackpanel devenv";

    config-file = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Custom starship.toml config file (uses stackpanel default if not set)";
    };
  };

  config = lib.mkIf cfg.enable {
    packages = starshipTheme.requiredPackages;

    stackpanel.motd.features = ["Starship prompt theme"];

    enterShell = ''
      # syntax: bash
      # Set the config path for starship
      export STARSHIP_CONFIG=$DEVENV_STATE/starship.toml
      install -m 644 ${
        if cfg.config-file != null
        then cfg.config-file
        else starshipTheme.config
      } $DEVENV_STATE/starship.toml

      # Only initialize starship here if we're in a direct `devenv shell` (bash)
      # When using direnv, the user's shell rc file handles starship init
      if [[ -z "''${DIRENV_IN_ENVRC:-}" ]]; then
        eval "$(starship init bash)"
      fi
    '';
  };
}
