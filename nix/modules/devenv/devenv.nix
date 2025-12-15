# Devenv modules for stackpanel
#
# For local imports in devenv.yaml:
#   imports:
#     - ./nix/modules/devenv
#
# For remote imports via flake input:
#   inputs:
#     stackpanel:
#       url: github:darkmatter/stackpanel
#   imports:
#     - stackpanel/nix/modules/devenv
#
{
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [./secrets.nix ./aws.nix ./network.nix ./theme.nix];

  # Base stackpanel options for devenv
  options.stackpanel = {
    enable = lib.mkEnableOption "stackpanel integration" // {default = true;};

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = ".stackpanel/state";
      description = "Directory for runtime state (gitignored)";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = ".stackpanel";
      description = "Directory for stackpanel config (checked in)";
    };
  };

  config = lib.mkIf config.stackpanel.enable {
    # Ensure state directory is gitignored
    enterShell = ''
      mkdir -p ${config.stackpanel.stateDir}
      if [[ ! -f "${config.stackpanel.dataDir}/.gitignore" ]]; then
        echo "state/" > "${config.stackpanel.dataDir}/.gitignore"
      fi
    '';
  };
}
