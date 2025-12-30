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
{ lib, config, ... }:
{

  # Base stackpanel options for devenv
  options.stackpanel = {
    enable = lib.mkEnableOption "Enable Stackpanel" // {
      default = true;
    };
    debug = lib.mkEnableOption "Enable Stackpanel Debug Mode" // {
      default = false;
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
              default = ../../../../infra/stackpanel;
            };
            home = lib.mkOption {
              description = ''
                Root directory for runtime files (relative to project root).
                Contains state/ (gitignored) and gen/ (checked in) subdirectories.
              '';
              type = lib.types.str;
              default = ".stackpanel";
            };
            state = lib.mkOption {
              description = ''
                State directory path (relative to project root).
                Computed from dirs.home. This directory is gitignored and contains
                runtime state files that shouldn't be committed.
              '';
              type = lib.types.str;
              default = "${config.home}/state";
            };
            gen = lib.mkOption {
              description = ''
                Generated files directory path (relative to project root).
                Computed from dirs.home. This directory is checked in and contains
                generated files (IDE configs, schemas, etc.).
              '';
              type = lib.types.str;
              default = "${config.home}/gen";
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
}
