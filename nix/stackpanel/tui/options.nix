# ==============================================================================
# theme.nix
#
# Theme options - Starship prompt customization for devenv shells.
#
# This module imports options from the proto schema (db/schemas/theme.proto.nix)
# and extends them with Nix-specific runtime options like config-file.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
#
# Example:
#   stackpanel.theme = {
#     enable = true;
#     preset = "stackpanel";
#     nerd-font = true;
#     minimal = false;
#   };
# ==============================================================================
{ lib, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../db { inherit lib; };
in
{
  # Theme options derived from proto schema
  # The proto defines: name, colors, starship, nerd_font, minimal
  # These are converted to kebab-case: nerd-font
  options.stackpanel.theme = db.mkOpt db.extend.theme {
    # Nix-specific extension: enable option (not in data schema)
    enable = lib.mkEnableOption "Starship prompt for stackpanel devenv" // {
      description = ''
        Enable Stackpanel-managed Starship prompt setup for the devshell.
        Direct `nix develop` shells initialize Starship automatically; direnv
        shells only install/export config and leave prompt initialization to the
        user's shell rc file to avoid double initialization.
      '';
      example = true;
    };

    preset = lib.mkOption {
      type = lib.types.enum [
        "stackpanel"
        "starship-default"
      ];
      default = "stackpanel";
      description = ''
        Built-in Starship preset to use when `config-file` is null.
        `"stackpanel"` installs the bundled Stackpanel prompt theme;
        `"starship-default"` leaves `STARSHIP_CONFIG` unset and uses Starship's
        upstream defaults.
      '';
      example = "stackpanel";
    };

    # Nix-specific extension: path to custom config file
    config-file = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional custom `starship.toml` file. When set, Stackpanel copies this
        file into the workspace state dir and exports `STARSHIP_CONFIG` to that
        copy, so prompt config does not point at mutable source paths.
      '';
      example = lib.literalExpression "./config/starship.toml";
    };
  };
}
