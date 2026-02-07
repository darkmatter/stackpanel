# ==============================================================================
# theme.nix
#
# Theme utilities for shell customization - pure functions that work with any
# Nix module system (flake-parts, devenv, NixOS, etc.)
#
# Provides Starship prompt configuration and theming for development shells.
# Includes both default configuration and customization options.
#
# Features:
#   - Default Starship configuration for stackpanel projects
#   - Theme package generation with init scripts
#   - Shell initialization snippets for bash/zsh/fish
#
# Usage:
#   let themeLib = import ./theme.nix { inherit pkgs lib; };
#   in themeLib.mkStarshipTheme { configFile = ./my-starship.toml; }
# ==============================================================================
{
  pkgs,
  lib,
}:
{
  # Default starship configuration for stackpanel
  defaultStarshipConfig = ../tui/starship.toml;

  # Create starship theme packages and scripts
  mkStarshipTheme =
    {
      # Path to starship.toml config file (optional, uses default if not provided)
      configFile ? null,
    }:
    let
      starshipConfig = if configFile != null then configFile else ../tui/starship.toml;

      # Script to initialize starship with our config
      initStarship = pkgs.writeShellScriptBin "init-stackpanel-starship" ''
        set -euo pipefail

        config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/stackpanel"
        mkdir -p "$config_dir"

        # Copy our starship config
        cp "${starshipConfig}" "$config_dir/starship.toml"

        echo "Starship config installed to $config_dir/starship.toml"
        # echo "Add this to your shell rc file:"
        # echo '  export STARSHIP_CONFIG="$config_dir/starship.toml"'
        # echo '  eval "$(starship init bash)"  # or zsh/fish'
        if [[ -z "$STARSHIP_SHELL" ]]; then
          eval "$(starship init $SHELL)"
        fi
      '';
    in
    {
      inherit initStarship;
      # The config file itself for direct use
      config = starshipConfig;
      # Required packages
      requiredPackages = [ pkgs.starship ];
      # All packages together
      allPackages = [
        initStarship
        pkgs.starship
      ];
      # Shell initialization snippet (for use in shell hooks)
      shellInit = configPath: ''
        export STARSHIP_CONFIG="${configPath}"
        eval "$(${pkgs.starship}/bin/starship init bash)"
      '';
    };
}
