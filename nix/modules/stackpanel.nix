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
}: let
  cfg = config.stackpanel;

  # Import the stackpanel CLI package (for MOTD)
  stackpanel-cli = pkgs.callPackage ../packages/stackpanel-cli {};
in {
  imports = [
    ./secrets
    ./aws.nix
    ./network.nix
    ./theme.nix
    ./caddy.nix
    ./ports.nix
    ./apps.nix
    ./global-services.nix
    ./ide.nix
    ./ci.nix
    ./state.nix
    ./cli-generate.nix
    ./recommended/devenv.nix
  ];

  # Base stackpanel options for devenv
  options.stackpanel = {
    enable = lib.mkEnableOption "stackpanel integration" // {default = true;};

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = ".stackpanel/state";
      description = "Directory for runtime state (gitignored)";
    };

    genDir = lib.mkOption {
      type = lib.types.str;
      default = ".stackpanel/gen";
      description = "Directory for generated files (gitignored, regenerated on each devenv run)";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = ".stackpanel";
      description = "Directory for stackpanel config (checked in)";
    };

    # Direnv configuration
    direnv = {
      hideEnvDiff = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hide the 'direnv: export +VAR...' log line (requires user's direnv.toml)";
      };
    };

    # MOTD help system
    motd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show MOTD with help text on shell entry";
      };

      commands = lib.mkOption {
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
        description = "List of available commands to show in MOTD";
      };

      features = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of enabled features to show in MOTD";
      };

      hints = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of hints to show in MOTD";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Environment variables for stackpanel paths
    # These can be overridden (e.g., in Docker) to point to mounted volumes
    env = {
      # Relative paths used as defaults - resolved to absolute in enterShell
      # Override these env vars when running in Docker with mounted volumes
      STACKPANEL_STATE_DIR_REL = cfg.stateDir;
      STACKPANEL_GEN_DIR_REL = cfg.genDir;
      STACKPANEL_DATA_DIR_REL = cfg.dataDir;
    };

    # Ensure state directory is gitignored
    # Use mkBefore to ensure this runs before other modules' enterShell hooks
    enterShell = lib.mkMerge [
      (lib.mkBefore ''
        # syntax: bash
        # Set absolute paths for stackpanel directories
        # These can be pre-set to override (e.g., in Docker with mounted volumes)
        export STACKPANEL_ROOT="''${STACKPANEL_ROOT:-$DEVENV_ROOT}"
        export STACKPANEL_STATE_DIR="''${STACKPANEL_STATE_DIR:-$STACKPANEL_ROOT/${cfg.stateDir}}"
        export STACKPANEL_GEN_DIR="''${STACKPANEL_GEN_DIR:-$STACKPANEL_ROOT/${cfg.genDir}}"
        export STACKPANEL_DATA_DIR="''${STACKPANEL_DATA_DIR:-$STACKPANEL_ROOT/${cfg.dataDir}}"

        mkdir -p "$STACKPANEL_STATE_DIR" "$STACKPANEL_GEN_DIR"
        # Ensure state/ is gitignored (gen/ is checked in)
        _gitignore="$STACKPANEL_DATA_DIR/.gitignore"
        if [[ ! -f "$_gitignore" ]] || ! grep -q "^state/$" "$_gitignore" 2>/dev/null; then
          echo "state/" > "$_gitignore"
        fi

        ${lib.optionalString cfg.direnv.hideEnvDiff ''
          # Ensure direnv is configured to hide env diff (less noisy output)
          _direnv_config="''${XDG_CONFIG_HOME:-$HOME/.config}/direnv/direnv.toml"
          if [[ ! -f "$_direnv_config" ]] || ! grep -q "hide_env_diff" "$_direnv_config" 2>/dev/null; then
            mkdir -p "$(dirname "$_direnv_config")"
            if [[ -f "$_direnv_config" ]]; then
              # Append to existing config if [global] section exists, otherwise add it
              if grep -q "^\[global\]" "$_direnv_config" 2>/dev/null; then
                sed -i.bak '/^\[global\]/a hide_env_diff = true' "$_direnv_config" && rm -f "$_direnv_config.bak"
              else
                echo -e "\n[global]\nhide_env_diff = true" >> "$_direnv_config"
              fi
            else
              echo -e "[global]\nhide_env_diff = true" > "$_direnv_config"
            fi
            echo "📝 Configured direnv to hide env diff (restart shell to apply)"
          fi
        ''}
      '')
      # Show MOTD after all modules have initialized (via Go CLI)
      (lib.mkAfter ''
        ${lib.optionalString cfg.motd.enable "${stackpanel-cli}/bin/stackpanel motd"}
      '')
    ];
  };
}
