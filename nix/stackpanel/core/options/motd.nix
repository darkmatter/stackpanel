# ==============================================================================
# motd.nix
#
# Message of the Day (MOTD) configuration - shell entry help display.
#
# Configures the help message shown when entering the devenv shell. The MOTD
# provides at-a-glance information about available commands, enabled features,
# and helpful hints.
#
# Options:
#   - enable: Show MOTD on shell entry (default: true)
#   - commands: List of { name, description } for available commands
#   - features: List of enabled feature names to display
#   - hints: List of helpful hints to show
#
# The actual rendering is done by the CLI, which formats the MOTD with
# colors and proper alignment.
# ==============================================================================
{lib,...}: {
  # MOTD help system
  options.stackpanel.motd = {
    enable = lib.mkOption {
      description = "Show MOTD with help text on shell entry";
      type = lib.types.bool;
      default = true;
    };

    commands = lib.mkOption {
      description = "List of available commands to show in MOTD";
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Command name";
          };
          description = lib.mkOption {
            type = lib.types.str;
            description = "Command description";
          };
        };
      });
      default = [];
    };

    features = lib.mkOption {
      description = "List of enabled features to show in MOTD";
      type = lib.types.listOf lib.types.str;
      default = [];
    };

    hints = lib.mkOption {
      description = "List of hints to show in MOTD";
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };
}