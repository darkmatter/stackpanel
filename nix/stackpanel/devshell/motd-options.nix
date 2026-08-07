# ==============================================================================
# motd-options.nix — Contribution façade for Prelude MOTD / catalogue
#
# Modules write stackpanel.motd.{commands,features,hints}. The flake integration
# maps those into flake-parts prelude.* via
# nix/stackpanel/modules/prelude/facade.nix (no Lip Gloss renderer).
#
# Shell entry runs Prelude `motd` when prelude.enable && motd.enable.
# Live status for probes/Studio: `stackpanel motd --json`.
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.motd = {
    enable = lib.mkOption {
      description = ''
        Run Prelude `motd` on shell entry (requires stackpanel.prelude.enable).

        Catalogue contributions below are always merged into prelude.* when
        Prelude packages are built; this flag only gates the shell-entry banner.
      '';
      type = lib.types.bool;
      default = true;
      example = true;
    };

    commands = lib.mkOption {
      description = ''
        Commands for Prelude Getting Started / `menu` / `x` (façade → prelude.commands).

        Use high-signal devshell commands. Keep descriptions short. Keys are
        sanitized from `name` (spaces → dashes).
      '';
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = ''
                Command / executable name (becomes prelude catalogue key + exec).
              '';
              example = "dev";
            };
            description = lib.mkOption {
              type = lib.types.str;
              description = "Short summary shown beside the command.";
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
        Feature labels mapped to Prelude MOTD env chips (e.g. postgres, redis).
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
        Hints merged into Prelude MOTD description text.
      '';
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "Run `menu` or `x --list` to browse commands."
        "Edit `.stack/config.nix` to change services."
      ];
    };
  };
}
