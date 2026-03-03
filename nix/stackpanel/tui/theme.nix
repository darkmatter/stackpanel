# ==============================================================================
# theme.nix
#
# Terminal theme and prompt customization module.
#
# Options + implementation colocated in a single self-contained module.
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

  # Import proto schema for theme data types
  db = import ../db { inherit lib; };

  # Import shared theme library
  themeLib = import ../lib/theme.nix { inherit pkgs lib; };
  starshipTheme = themeLib.mkStarshipTheme { };
  resolvedConfig =
    if cfg.config-file != null then
      cfg.config-file
    else if cfg.preset == "starship-default" then
      null
    else
      starshipTheme.config;
  # Copy the config file into its own store path (not referencing `self`/flake source)
  # to avoid polluting the shellhook derivation with the flake source store path.
  resolvedConfigFile =
    if resolvedConfig == null then
      null
    else
      pkgs.writeTextFile {
        name = "starship-config";
        text = builtins.readFile resolvedConfig;
        destination = "/starship.toml";
      };
  resolvedConfigPath =
    if resolvedConfigFile == null then "" else "${resolvedConfigFile}/starship.toml";
in
{
  # ── Options ──────────────────────────────────────────────────────────────────
  # Theme options derived from proto schema
  # The proto defines: name, colors, starship, nerd_font, minimal
  # These are converted to kebab-case: nerd-font
  options.stackpanel.theme = db.mkOpt db.extend.theme {
    # Nix-specific extension: enable option (not in data schema)
    enable = lib.mkEnableOption "Starship prompt for stackpanel devenv";

    preset = lib.mkOption {
      type = lib.types.enum [
        "stackpanel"
        "starship-default"
      ];
      default = "stackpanel";
      description = "Starship preset to apply when no custom config file is provided";
    };

    # Nix-specific extension: path to custom config file
    config-file = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Custom starship.toml config file (uses stackpanel default if not set)";
    };
  };

  # ── Config ───────────────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable {
    stackpanel.devshell.packages = starshipTheme.requiredPackages;

    stackpanel.motd.features = [ "Starship prompt theme" ];

    stackpanel.devshell.hooks.main = [
      ''
        # syntax: bash
        # Set the config path for starship
        # Use STACKPANEL_STATE_DIR (native) or DEVENV_STATE (devenv)
        _starship_state_dir="''${STACKPANEL_STATE_DIR:-''${DEVENV_STATE:-$PWD/.stack/profile}}"
        mkdir -p "$_starship_state_dir"

        if [[ -n "${resolvedConfigPath}" ]]; then
          export STARSHIP_CONFIG="$_starship_state_dir/starship.toml"
          install -m 644 ${resolvedConfigPath} "$_starship_state_dir/starship.toml"
        else
          unset STARSHIP_CONFIG
        fi

        # Only initialize starship here if we're in a direct `devenv shell` (bash)
        # When using direnv, the user's shell rc file handles starship init
        if [[ -z "''${DIRENV_IN_ENVRC:-}" ]]; then
          eval "$(starship init bash)"
        fi
      ''
    ];
  };
}
