# ==============================================================================
# theme.nix
#
# Theme options - Starship prompt customization for devenv shells.
#
# This module imports options from the proto schema (db/schemas/theme.proto.nix)
# and extends them with Nix-specific runtime options like config-file.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
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
}
