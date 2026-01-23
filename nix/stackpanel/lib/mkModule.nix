# ==============================================================================
# mkModule.nix
#
# Helper library for creating Stackpanel modules with less boilerplate.
#
# This provides a convenient wrapper around the stackpanel.modules system
# that handles common patterns:
#   - Setting up enable/disable logic
#   - Registering metadata
#   - Adding per-app options via appModules
#   - Contributing to devshell, scripts, healthchecks, etc.
#
# Usage:
#
#   # Simple module
#   { lib, ... }:
#   lib.stackpanel.mkModule {
#     name = "myModule";
#     meta = {
#       name = "My Module";
#       description = "Does something useful";
#       category = "development";
#     };
#     features = { scripts = true; };
#     config = cfg: {
#       stackpanel.scripts.my-command = { ... };
#     };
#   }
#
#   # Module with per-app options
#   { lib, ... }:
#   lib.stackpanel.mkModule {
#     name = "docker";
#     meta = { ... };
#     appModule = { lib, ... }: {
#       options.docker = lib.mkOption {
#         type = lib.types.submodule { ... };
#       };
#     };
#     config = cfg: {
#       stackpanel.files.entries = ...;
#     };
#   }
#
#   # Module with settings
#   { lib, ... }:
#   lib.stackpanel.mkModule {
#     name = "postgres";
#     meta = { ... };
#     settings = {
#       version = {
#         type = lib.types.enum [ "15" "16" ];
#         default = "16";
#         description = "PostgreSQL version";
#       };
#       port = {
#         type = lib.types.port;
#         default = 5432;
#       };
#     };
#     config = cfg: {
#       # cfg.settings.version, cfg.settings.port available here
#     };
#   }
#
# ==============================================================================
{ lib }:
{
  # ===========================================================================
  # mkModule - Create a Stackpanel module with standard patterns
  # ===========================================================================
  mkModule =
    {
      # Required: Module identifier (used in stackpanel.modules.<name>)
      name,

      # Required: Module metadata
      meta,

      # Optional: Feature flags (which stackpanel systems this module uses)
      features ? { },

      # Optional: Module source info
      source ? {
        type = "local";
      },

      # Optional: Settings that users can configure
      # Each key becomes an option under stackpanel.modules.<name>.settings.<key>
      # Value should be an attrset with { type, default?, description? }
      settings ? { },

      # Optional: Per-app options module
      # This will be added to stackpanel.appModules
      appModule ? null,

      # Optional: Default enable state (default: false)
      defaultEnable ? false,

      # Optional: Dependencies on other modules
      requires ? [ ],

      # Optional: Conflicting modules
      conflicts ? [ ],

      # Optional: Load priority (lower = earlier)
      priority ? 100,

      # Optional: Tags for filtering
      tags ? [ ],

      # Optional: JSON Schema for config UI form generation
      configSchema ? null,

      # Optional: Link to healthcheck module name
      healthcheckModule ? null,

      # Required: Configuration function
      # Receives the module's config (cfg) and returns config attrset
      # cfg has: cfg.enable, cfg.settings.*, cfg.meta, etc.
      config,
    }:
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.stackpanel.modules.${name};

      # Build settings options from the settings attrset
      settingsOptions = lib.mapAttrs (
        settingName: settingDef:
        lib.mkOption {
          type = settingDef.type;
          default = settingDef.default or null;
          description = settingDef.description or "Configuration for ${settingName}";
          example = settingDef.example or null;
        }
      ) settings;

      # Determine features.appModule based on whether appModule is provided
      computedFeatures = features // {
        appModule = appModule != null;
      };
    in
    {
      # =========================================================================
      # Options
      # =========================================================================

      options.stackpanel.modules.${name} = {
        # Standard enable option
        enable = lib.mkEnableOption meta.name // {
          default = defaultEnable;
        };

        # Settings submodule (if settings were provided)
        settings = lib.mkOption {
          type = lib.types.submodule { options = settingsOptions; };
          default = { };
          description = "Configuration settings for ${meta.name}";
        };
      };

      # =========================================================================
      # Config
      # =========================================================================

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          # Module metadata and features
          {
            stackpanel.modules.${name} = {
              inherit meta source;
              features = computedFeatures;
              inherit
                requires
                conflicts
                priority
                tags
                ;
              configSchema =
                if configSchema != null then
                  (if builtins.isString configSchema then configSchema else builtins.toJSON configSchema)
                else
                  null;
              healthcheckModule = healthcheckModule;
            };
          }

          # Register appModule if provided
          (lib.optionalAttrs (appModule != null) { stackpanel.appModules = [ appModule ]; })

          # User-provided configuration
          (config cfg)
        ]
      );
    };

  # ===========================================================================
  # mkSimpleModule - Even simpler module creation for basic use cases
  # ===========================================================================
  mkSimpleModule =
    {
      name,
      displayName,
      description ? null,
      category ? "development",
      icon ? null,
      config,
    }:
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.stackpanel.modules.${name};
    in
    {
      options.stackpanel.modules.${name}.enable = lib.mkEnableOption displayName;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            stackpanel.modules.${name} = {
              meta = {
                name = displayName;
                inherit description icon category;
              };
              source.type = "local";
            };
          }
          (config cfg)
        ]
      );
    };
}
