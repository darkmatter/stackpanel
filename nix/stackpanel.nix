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
  options,
  ...
}: let
  cfg = config.stackpanel;

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

  # Import libraries
  stackpanel-cli = pkgs.callPackage ./packages/stackpanel-cli {};
  pathsLib = import ./lib/paths.nix { inherit lib; };
in {
  imports = [
    ./modules/secrets
    ./modules/aws.nix
    ./modules/network.nix
    ./modules/theme.nix
    ./modules/caddy.nix
    ./modules/ports.nix
    ./modules/apps.nix
    ./modules/global-services.nix
    ./modules/ide.nix
    ./modules/ci.nix
    ./modules/state.nix
    ./modules/cli-generate.nix
    ./modules/recommended/devenv.nix
  ];

  # Base stackpanel options for devenv
  options.stackpanel = {
    enable = lib.mkEnableOption "stackpanel integration" // {default = true;};

    root = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path to the project root. If set, this overrides PWD-based detection.

        For pure flake evaluation (like `nix flake check`), use the readStackpanelRoot
        flake module which reads this from a flake input:

        ```nix
        # flake.nix inputs
        inputs.stackpanel-root = {
          url = "file+file:///dev/null";
          flake = false;
        };

        # imports
        imports = [ inputs.stackpanel.flakeModules.readStackpanelRoot ];
        ```

        Then in .envrc: `echo "$PWD" > .stackpanel-root`
      '';
    };

    dirs = lib.mkOption {
      type = lib.types.submodule {
        options = {
          config = lib.mkOption {
            type = lib.types.path;
            default = ./infra/stackpanel;
            description = "Directory for stackpanel configuration files.";
          };
          home = lib.mkOption {
            type = lib.types.str;
            default = ".stackpanel";
            description = ''
              Root directory for runtime files (relative to project root).
              Contains state/ (gitignored) and gen/ (checked in) subdirectories.
            '';
          };
          state = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.dirs.home}/state";
            description = ''
              State directory path (relative to project root).
              Computed from dirs.home. This directory is gitignored and contains
              runtime state files that shouldn't be committed.
            '';
          };
          gen = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.dirs.home}/gen";
            description = ''
              Generated files directory path (relative to project root).
              Computed from dirs.home. This directory is checked in and contains
              generated files (IDE configs, schemas, etc.).
            '';
          };
        };
      };
      default = {};
      description = "Directories used by stackpanel.";
    };




    root-marker = lib.mkOption {
      type = lib.types.str;
      default = ".stackpanel-root";
      description = ''
        Filename for the root marker file written to the project root.
        Contains the absolute path to the project root, allowing tools
        to find the project from any subdirectory. Add to .dockerignore
        and .gitignore so containers create their own marker.
      '';
    };

    # Direnv configuration
    direnv = {
      hide-env-diff = lib.mkOption {
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

  config = lib.mkIf cfg.enable (lib.optionalAttrs isDevenv {
    # Environment variables for stackpanel paths
    env = {
      # Config dir is a Nix store path (build input)
      STACKPANEL_CONFIG_DIR = toString cfg.dirs.config;
      # Root directory name for reference
      STACKPANEL_ROOT_DIR_NAME = cfg.dirs.home;
      # Root marker filename
      STACKPANEL_ROOT_MARKER = cfg.root-marker;
    };

    # Ensure state directory is gitignored
    # Use mkBefore to ensure this runs before other modules' enterShell hooks
    enterShell = lib.mkMerge [
      (lib.mkBefore ''
        # Define path utility functions (available to all scripts in this shell)
        ${pathsLib.mkShellFindRoot {
          rootDir = cfg.dirs.home;
          rootMarker = cfg.root-marker;
        }}
        ${pathsLib.mkShellResolvePaths {
          rootDir = cfg.dirs.home;
        }}

        # Set absolute paths for stackpanel directories
        # Priority: 1) STACKPANEL_ROOT env var (pre-set), 2) cfg.root (Nix config), 3) $PWD
        ${if cfg.root != null then ''
        export STACKPANEL_ROOT="''${STACKPANEL_ROOT:-${cfg.root}}"
        '' else ''
        export STACKPANEL_ROOT="''${STACKPANEL_ROOT:-$PWD}"
        ''}
        export STACKPANEL_ROOT_DIR="$STACKPANEL_ROOT/${cfg.dirs.home}"
        export STACKPANEL_STATE_DIR="$STACKPANEL_ROOT/${cfg.dirs.state}"
        export STACKPANEL_GEN_DIR="$STACKPANEL_ROOT/${cfg.dirs.gen}"

        mkdir -p "$STACKPANEL_STATE_DIR" "$STACKPANEL_GEN_DIR"

        # Write root marker file at project root (allows tools to find project from any subdir)
        echo "$STACKPANEL_ROOT" > "$STACKPANEL_ROOT/${cfg.root-marker}"

        # Ensure state/ is gitignored in .stackpanel/
        _sp_gitignore="$STACKPANEL_ROOT_DIR/.gitignore"
        if [[ ! -f "$_sp_gitignore" ]]; then
          echo "state/" > "$_sp_gitignore"
        fi

        # Add root marker to project .gitignore if not already present
        _root_gitignore="$STACKPANEL_ROOT/.gitignore"
        if [[ -f "$_root_gitignore" ]]; then
          if ! grep -q "^${cfg.root-marker}$" "$_root_gitignore" 2>/dev/null; then
            echo "" >> "$_root_gitignore"
            echo "# Stackpanel root marker (machine-specific)" >> "$_root_gitignore"
            echo "${cfg.root-marker}" >> "$_root_gitignore"
          fi
        fi

        ${lib.optionalString cfg.direnv.hide-env-diff ''
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
  });
}
