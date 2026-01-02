# ==============================================================================
# theme.nix
#
# Terminal theme and prompt customization module for devenv.
#
# This module configures Starship prompt for development shells, providing
# a consistent and informative terminal experience. The theme shows git
# status, current directory, language versions, and more.
#
# Features:
#   - Pre-configured Starship theme
#   - Custom config file support
#   - Automatic initialization in bash shells
#   - Direnv-aware (avoids double initialization)
#
# Usage:
#   stackpanel.theme = {
#     enable = true;
#     config-file = ./my-starship.toml;  # Optional custom config
#   };
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.theme;

  # Import shared theme library
  themeLib = import ../lib/theme.nix { inherit pkgs lib; };
  starshipTheme = themeLib.mkStarshipTheme { };
in
{
  config = lib.mkIf cfg.enable {
    stackpanel.devshell.packages = starshipTheme.requiredPackages;

    stackpanel.motd.features = [ "Starship prompt theme" ];

    stackpanel.devshell.hooks.main = [
      ''
        # syntax: bash
        # Set the config path for starship
        # Use STACKPANEL_STATE_DIR (native) or DEVENV_STATE (devenv)
        _starship_state_dir="''${STACKPANEL_STATE_DIR:-''${DEVENV_STATE:-$PWD/.stackpanel/state}}"
        export STARSHIP_CONFIG="$_starship_state_dir/starship.toml"
        mkdir -p "$_starship_state_dir"
        install -m 644 ${
          if cfg.config-file != null then cfg.config-file else starshipTheme.config
        } "$_starship_state_dir/starship.toml"

        # Only initialize starship here if we're in a direct `devenv shell` (bash)
        # When using direnv, the user's shell rc file handles starship init
        if [[ -z "''${DIRENV_IN_ENVRC:-}" ]]; then
          eval "$(starship init bash)"
        fi
      ''
    ];
  };
}
