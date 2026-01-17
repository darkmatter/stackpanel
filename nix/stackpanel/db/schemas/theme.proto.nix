# ==============================================================================
# theme.proto.nix
#
# Protobuf schema for theme configuration.
# Defines theme and Starship prompt configuration.
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
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  messages = {
    # Root theme configuration
    Theme = proto.mkMessage {
      name = "Theme";
      description = "Theme and Starship prompt configuration";
      fields = {
        name = proto.string 1 "Theme name";
        colors = proto.message "ColorScheme" 2 "Color scheme configuration";
        starship = proto.message "Starship" 3 "Starship prompt configuration";
        nerd_font = proto.bool 4 "Use Nerd Font icons in prompt";
        minimal = proto.bool 5 "Use minimal prompt (fewer segments)";
      };
    };

    # Color scheme configuration
    ColorScheme = proto.mkMessage {
      name = "ColorScheme";
      description = "Color scheme configuration";
      fields = {
        primary = proto.string 1 "Primary accent color";
        secondary = proto.string 2 "Secondary accent color";
        success = proto.string 3 "Success/positive color";
        warning = proto.string 4 "Warning color";
        error = proto.string 5 "Error/negative color";
        muted = proto.string 6 "Muted/subtle color";
      };
    };

    # Starship prompt configuration
    Starship = proto.mkMessage {
      name = "Starship";
      description = "Starship prompt configuration";
      fields = {
        format = proto.optional (proto.string 1 "Custom prompt format string");
        right_format = proto.optional (proto.string 2 "Right-side prompt format");
        continuation_prompt = proto.string 3 "Continuation prompt for multi-line input";
        scan_timeout = proto.int32 4 "Timeout for directory scanning (ms)";
        command_timeout = proto.int32 5 "Timeout for commands (ms)";
        add_newline = proto.bool 6 "Add blank line before prompt";
      };
    };
  };
}
