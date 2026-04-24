# ==============================================================================
# theme.proto.nix
#
# Protobuf schema for theme configuration.
# Defines theme and Starship prompt configuration.
#
# NOTE: This schema uses the new attribute-set mkField API (proto.mkField).
# It's the recommended shape for new code — feels like lib.mkOption with a
# proto `number` (field index) added. See nix/stackpanel/db/lib/proto.nix for
# the full API reference.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "theme.proto";
  package = "stackpanel.db";

  boilerplate = ''
    # theme.nix - Shell theme configuration
    # type: stackpanel.theme
    # See: https://stackpanel.dev/docs/theme
    {
      # name = "default";
      # nerd-font = true;
      # minimal = false;
      #
      # colors = {
      #   primary = "#7aa2f7";
      #   secondary = "#bb9af7";
      #   success = "#9ece6a";
      #   warning = "#e0af68";
      #   error = "#f7768e";
      #   muted = "#565f89";
      # };
      #
      # starship = {
      #   add-newline = true;
      #   scan-timeout = 30;
      #   command-timeout = 500;
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    # Root theme configuration
    Theme = proto.mkMessage {
      name = "Theme";
      description = "Theme and Starship prompt configuration";
      fields = {
        name = proto.mkField {
          number = 1;
          type = proto.types.string;
          description = "Theme name";
          default = "default";
          example = "tokyo-night";
        };
        colors = proto.mkField {
          number = 2;
          type = proto.types.message "ColorScheme";
          description = "Color scheme configuration";
        };
        starship = proto.mkField {
          number = 3;
          type = proto.types.message "Starship";
          description = "Starship prompt configuration";
        };
        nerd_font = proto.mkField {
          number = 4;
          type = proto.types.bool;
          description = "Use Nerd Font icons in prompt";
          default = true;
        };
        minimal = proto.mkField {
          number = 5;
          type = proto.types.bool;
          description = "Use minimal prompt (fewer segments)";
        };
      };
    };

    # Color scheme configuration
    ColorScheme = proto.mkMessage {
      name = "ColorScheme";
      description = "Color scheme configuration";
      fields = {
        primary = proto.mkField {
          number = 1;
          type = proto.types.string;
          description = "Primary accent color";
          example = "#7aa2f7";
        };
        secondary = proto.mkField {
          number = 2;
          type = proto.types.string;
          description = "Secondary accent color";
          example = "#bb9af7";
        };
        success = proto.mkField {
          number = 3;
          type = proto.types.string;
          description = "Success/positive color";
          example = "#9ece6a";
        };
        warning = proto.mkField {
          number = 4;
          type = proto.types.string;
          description = "Warning color";
          example = "#e0af68";
        };
        error = proto.mkField {
          number = 5;
          type = proto.types.string;
          description = "Error/negative color";
          example = "#f7768e";
        };
        muted = proto.mkField {
          number = 6;
          type = proto.types.string;
          description = "Muted/subtle color";
          example = "#565f89";
        };
      };
    };

    # Starship prompt configuration
    Starship = proto.mkMessage {
      name = "Starship";
      description = "Starship prompt configuration";
      fields = {
        format = proto.mkField {
          number = 1;
          type = proto.types.string;
          description = "Custom prompt format string";
          optional = true;
        };
        right_format = proto.mkField {
          number = 2;
          type = proto.types.string;
          description = "Right-side prompt format";
          optional = true;
        };
        continuation_prompt = proto.mkField {
          number = 3;
          type = proto.types.string;
          description = "Continuation prompt for multi-line input";
        };
        scan_timeout = proto.mkField {
          number = 4;
          type = proto.types.int32;
          description = "Timeout for directory scanning (ms)";
          default = 30;
        };
        command_timeout = proto.mkField {
          number = 5;
          type = proto.types.int32;
          description = "Timeout for commands (ms)";
          default = 500;
        };
        add_newline = proto.mkField {
          number = 6;
          type = proto.types.bool;
          description = "Add blank line before prompt";
          default = true;
        };
      };
    };
  };
}
