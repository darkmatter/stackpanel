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
  options,
  ...
}: let
  cfg = config.stackpanel.theme;

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

  # Import shared theme library
  themeLib = import ../lib/theme.nix {inherit pkgs lib;};
  starshipTheme = themeLib.mkStarshipTheme {};
in {
  config = lib.mkIf cfg.enable (lib.optionalAttrs isDevenv {
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
  });
}
