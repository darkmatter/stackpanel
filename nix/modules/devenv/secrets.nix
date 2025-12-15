# Secrets management for devenv
#
# Note: For devenv, this is a simplified version.
# Full SOPS + codegen support is in the flake-parts modules.
#
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.stackpanel.secrets;
in {
  options.stackpanel.secrets = {
    enable = lib.mkEnableOption "secrets management";

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to SOPS encrypted secrets file";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to .env file for local development";
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [pkgs.sops pkgs.age];

    # Load .env file if specified
    enterShell = lib.optionalString (cfg.envFile != null) ''
      if [[ -f "${cfg.envFile}" ]]; then
        set -a
        source "${cfg.envFile}"
        set +a
      fi
    '';
  };
}
