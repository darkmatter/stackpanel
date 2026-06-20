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
{ lib, ... }:
{
  # MOTD help system
  options.stackpanel.motd = {
    enable = lib.mkOption {
      description = ''
        Show message-of-the-day help text on shell entry.

        The CLI renders this from commands, features, and hints so users see the
        most useful devshell actions immediately after `nix develop` or direnv
        reloads.
      '';
      type = lib.types.bool;
      default = true;
      example = true;
    };

    commands = lib.mkOption {
      description = ''
        Commands displayed in the shell-entry MOTD.

        Use this for high-signal devshell commands, usually derived from
        stackpanel.scripts or curated module commands. Keep descriptions short so
        the MOTD stays scannable.
      '';
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = ''
                Command name shown in the MOTD.

                Should match the executable users can run from the devshell, such
                as a stackpanel.scripts key or generated wrapper.
              '';
              example = "dev";
            };
            description = lib.mkOption {
              type = lib.types.str;
              description = ''
                Short command summary shown beside the name in the MOTD.

                Prefer imperative, practical text that explains when to run it.
              '';
              example = "Start all local services";
            };
          };
        }
      );
      default = [ ];
      example = [
        {
          name = "dev";
          description = "Start all local services";
        }
        {
          name = "stackpanel commands";
          description = "Browse project scripts";
        }
      ];
    };

    features = lib.mkOption {
      description = ''
        Enabled feature labels shown in the MOTD.

        Use concise names for active devshell capabilities such as postgres,
        redis, minio, or secrets so users can see what the shell configured.
      '';
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "postgres"
        "redis"
        "secrets"
      ];
    };

    hints = lib.mkOption {
      description = ''
        Helpful hints displayed below MOTD commands and features.

        Use for practical next actions or local conventions, not long docs. Hints
        should point to commands or files users can act on immediately.
      '';
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "Run `stackpanel commands` to browse scripts."
        "Edit `.stack/config.nix` to change services."
      ];
    };
  };
}
