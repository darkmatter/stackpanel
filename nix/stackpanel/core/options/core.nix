# ==============================================================================
# core.nix
#
# Core Stackpanel options - fundamental configuration for all projects.
#
# Defines the base options that control Stackpanel behavior:
#   - enable: Master switch for Stackpanel functionality
#   - root: Absolute project root path (optional override)
#   - dirs: Directory configuration (home, state, gen, config)
#   - direnv: Direnv integration settings
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

    # Module requirements - what variables each enabled module needs
    # This is populated by modules and serialized to config JSON for agent/UI
    moduleRequirements = lib.mkOption {
      description = ''
        Variable requirements declared by enabled modules.
        Modules add entries here to declare what environment variables they need.
        The agent/UI can query this to show what's missing.

        Format: { moduleName = { requires = [ ... ]; provides = [ ... ]; }; }
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            requires = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    key = lib.mkOption {
                      type = lib.types.str;
                      description = "Environment variable name";
                    };
                    description = lib.mkOption {
                      type = lib.types.str;
                      default = "";
                      description = "Description of the variable";
                    };
                    sensitive = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "Whether the value should be treated as a secret";
                    };
                    action = lib.mkOption {
                      type = lib.types.nullOr (
                        lib.types.submodule {
                          options = {
                            type = lib.mkOption {
                              type = lib.types.str;
                              description = "Action type: add-secret, add-variable, external";
                            };
                            label = lib.mkOption {
                              type = lib.types.str;
                              default = "";
                              description = "Button/link label";
                            };
                            url = lib.mkOption {
                              type = lib.types.nullOr lib.types.str;
                              default = null;
                              description = "External URL for creating the value";
                            };
                          };
                        }
                      );
                      default = null;
                      description = "Action to resolve this variable if missing";
                    };
                  };
                }
              );
              default = [ ];
              description = "Variables required by this module";
            };
            provides = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Environment variables provided by this module after setup";
            };
          };
        }
      );
      default = { };
    };

    project = lib.mkOption {
      description = ''
        Project metadata including type, owner, and repository information.
      '';
      type = lib.types.submodule {
        options = {
          name = lib.mkOption {
            description = "Project name (defaults to stackpanel.name)";
            type = lib.types.str;
            default = config.stackpanel.name;
          };
          type = lib.mkOption {
            description = "Project type (e.g., 'github', 'gitlab', 'local')";
            type = lib.types.str;
            default = "github";
          };
          owner = lib.mkOption {
            description = "Owner/organization of the project repository";
            type = lib.types.str;
            default = "";
            example = "darkmatter";
          };
          repo = lib.mkOption {
            description = "Repository name";
            type = lib.types.str;
            default = "";
            example = "stackpanel";
          };
        };
      };
      default = { };
    };

    github = lib.mkOption {
      description = ''
        DEPRECATED: Use stackpanel.project.owner and stackpanel.project.repo instead.

        GitHub repository in 'owner/repo' format for this project. This value is
        used as a key for certain features like stable port calculation and
        user sync.
      '';
      type = lib.types.str;
      default =
        let
          owner = config.stackpanel.project.owner;
          repo = config.stackpanel.project.repo;
        in
        if owner != "" && repo != "" then "${owner}/${repo}" else "";
      example = "darkmatter/stackpanel";
    };
    useDevenv = lib.mkOption {
      description = ''
        DEPRECATED: This option is no longer used. Devenv is always the shell backend.

        The flakeModule now always uses devenv for shell creation.
        This option is kept for backwards compatibility but has no effect.
      '';
      type = lib.types.bool;
      default = true;
      visible = false;
    };
    # ----------------------------------------------------------------------------
    # Root Path
    # ----------------------------------------------------------------------------
    root = lib.mkOption {
      description = ''
        Absolute path to the project root. If set, this overrides automatic detection.

        Automatic detection uses (in order):
        1. STACKPANEL_ROOT environment variable
        2. Git repository root (.git directory)
        3. flake.nix location
      '';
      type = lib.types.nullOr lib.types.str;
      default = null;
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

    git-hooks = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Git hooks configuration fragment (consumed by git-hooks.nix).";
    };

    checks = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      description = "Additional flake checks contributed by stackpanel modules.";
    };

    # Serializable configuration for the agent/CLI
    # Modules can add their config here for JSON serialization
    serializable = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Serializable configuration data for the agent and CLI.
        Modules can contribute their JSON-safe config here.
        This data is included in stackpanelConfig for external tools.
      '';
    };

    util = lib.mkOption {
      type = lib.types.anything;
      internal = true;
      visible = false; # Hide from documentation to avoid serialization issues
      description = "Internal stackpanel utilities.";
      default = {
        log = {
          debug = _: "";
          info = _: "";
          error = _: "";
          log = _: "";
        };
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
