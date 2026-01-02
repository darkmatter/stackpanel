# ==============================================================================
# core.nix
#
# Core Stackpanel options - fundamental configuration for all projects.
#
# Defines the base options that control Stackpanel behavior:
#   - enable: Master switch for Stackpanel functionality
#   - root: Absolute project root path (optional override)
#   - root-marker: Filename for the root marker file (.stackpanel-root)
#   - dirs: Directory configuration (home, state, gen, config)
#   - direnv: Direnv integration settings
#   - gitignore: Whether to auto-add root marker to .gitignore
#
# The root marker system allows tools to find the project root from any
# subdirectory by walking up the tree looking for the marker file.
#
# Directory layout:
#   .stackpanel/           (dirs.home)
#   ├── state/             (dirs.state - gitignored, runtime state)
#   └── gen/               (dirs.gen - checked in, generated files)
# ==============================================================================
{
  lib,
  config,
  ...
}:
{
  # Base stackpanel options for devenv
  options.stackpanel = {
    enable = lib.mkEnableOption "Enable Stackpanel" // {
      default = true;
    };
    debug = lib.mkEnableOption "Enable Stackpanel Debug Mode" // {
      default = false;
    };

    name = lib.mkOption {
      description = ''
        Name of your project. May be used for naming things and diplay purposes.
      '';
      type = lib.types.str;
      default = "my-project";
    };

    github = lib.mkOption {
      description = ''
        GitHub repository in 'owner/repo' format for this project. This value is
        used as a key for certain features like stable port calculation and
        user sync.
      '';
      type = lib.types.str;
      default = "";
      example = "darkmatter/stackpanel";
    };
    useDevenv = lib.mkOption {
      description = ''

        For internal use:

        Whether to use devenv as the shell backend. When true, devenv features
        like languages, processes, and tasks are available. When false, uses a
        lean native nix shell with only stackpanel features.

        Defaults to true unless SKIP_DEVENV environment variable is set.
      '';
      type = lib.types.bool;
      default = builtins.getEnv "SKIP_DEVENV" != "true";
    };
    # ----------------------------------------------------------------------------
    # Root Path
    # ----------------------------------------------------------------------------
    root = lib.mkOption {
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
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    root-marker = lib.mkOption {
      description = ''
        Filename for the root marker file written to the project root.
        Contains the absolute path to the project root, allowing tools
        to find the project from any subdirectory. Add to .dockerignore
        and .gitignore so containers create their own marker.
      '';
      type = lib.types.str;
      default = ".stackpanel-root";
    };
    # Whether to append the marker to the project's .gitignore (off by default)
    gitignore = {
      addProjectMarker = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };

    # ----------------------------------------------------------------------------
    # Directories
    # ----------------------------------------------------------------------------
    dirs = lib.mkOption {
      type = lib.types.submodule (
        { config, ... }:
        {
          options = {
            config = lib.mkOption {
              description = "Directory for stackpanel configuration files.";
              type = lib.types.path;
              default = ../../../../.stackpanel/config.nix;
            };
            home = lib.mkOption {
              description = ''
                Root directory for stackpanel files (relative to project root).
                This is the ONLY configurable directory option.

                Subdirectories are automatically computed:
                  - state/ (gitignored) - runtime state files
                  - gen/   (checked in) - generated IDE configs, schemas
                  - data/ (checked in) -  nix-backed configuration db

                Example: ".stackpanel" → state at ".stackpanel/state"
              '';
              type = lib.types.str;
              default = ".stackpanel";
            };
            # ================================================================
            # COMPUTED PATHS (read-only, derived from home)
            # These cannot be configured - change `home` instead.
            # ================================================================
            state = lib.mkOption {
              description = ''
                Full state directory path (relative to project root).
                Computed as: dirs.home + "/state"
                This is read-only - configure dirs.home instead.
              '';
              type = lib.types.str;
              default = "${config.home}/state";
              readOnly = true;
            };
            data = lib.mkOption {
              description = ''
                Full data directory path (relative to project root).
                Computed as: dirs.home + "/data"
                This is read-only - configure dirs.home instead.
              '';
              type = lib.types.str;
              default = "${config.home}/data";
              readOnly = true;
            };
            gen = lib.mkOption {
              description = ''
                Full generated files directory path (relative to project root).
                Computed as: dirs.home + "/gen"
                This is read-only - configure dirs.home instead.
              '';
              type = lib.types.str;
              default = "${config.home}/gen";
              readOnly = true;
            };
          };
        }
      );
      default = { };
      description = "Directories used by stackpanel.";
    };

    # Direnv configuration
    direnv = {
      hide-env-diff = lib.mkOption {
        description = "Hide the 'direnv: export +VAR...' log line (requires user's direnv.toml)";
        type = lib.types.bool;
        default = true;
      };
    };
  };

  # ============================================================================
  # Flake helper: optionalLocalConfig
  #
  # Use this in your devenv.nix imports to conditionally import a local config:
  #
  #   imports = [
  #     inputs.stackpanel.devenvModules.default
  #   ] ++ stackpanelLib.optionalLocalConfig ./.stackpanel/config.local.nix;
  #
  # The file .stackpanel/config.local.nix is automatically gitignored.
  # ============================================================================
}
