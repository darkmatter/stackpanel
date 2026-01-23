# ==============================================================================
# modules.nix
#
# Stackpanel Module System - the unified system for extending stackpanel.
#
# Modules are the primary way to extend stackpanel functionality. They can:
#   - Add devshell packages, hooks, and environment variables
#   - Generate files via stackpanel.files.entries
#   - Provide shell scripts/commands via stackpanel.scripts
#   - Define health checks via stackpanel.healthchecks
#   - Register UI panels for the web studio
#   - Extend per-app configuration via stackpanel.appModules
#
# Modules can be:
#   - Builtin: Shipped with stackpanel (e.g., postgres, redis, step-ca)
#   - Local: Defined in the project repository
#   - Remote: Installed from flake inputs or a module registry
#
# Example module definition:
#
#   stackpanel.modules.myModule = {
#     enable = true;
#     meta = {
#       name = "My Module";
#       description = "Does something useful";
#       icon = "box";
#       category = "development";
#     };
#     features.scripts = true;
#     panels = [{
#       id = "myModule-status";
#       title = "My Module Status";
#       type = "PANEL_TYPE_STATUS";
#       fields = [{ name = "metrics"; type = "FIELD_TYPE_JSON"; value = "..."; }];
#     }];
#   };
#
# This module replaces the older stackpanel.extensions system.
# For backward compatibility, stackpanel.extensions is aliased to stackpanel.modules.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;

  # ============================================================================
  # Type Definitions
  # ============================================================================

  # Module source types
  sourceTypeEnum = lib.types.enum [
    "builtin" # Shipped with stackpanel
    "local" # Defined in project
    "flake-input" # Installed via flake input
    "registry" # Installed from module registry
  ];

  # Module categories for UI grouping
  categoryEnum = lib.types.enum [
    "unspecified"
    "infrastructure"
    "ci-cd"
    "database"
    "secrets"
    "deployment"
    "development"
    "monitoring"
    "integration"
    "language" # Language-specific tooling (go, bun, python, etc.)
    "service" # Background services (postgres, redis, etc.)
  ];

  # Panel types for UI rendering (matches extension-panels)
  panelTypeEnum = lib.types.enum [
    "PANEL_TYPE_UNSPECIFIED"
    "PANEL_TYPE_STATUS"
    "PANEL_TYPE_APPS_GRID"
    "PANEL_TYPE_FORM"
    "PANEL_TYPE_TABLE"
    "PANEL_TYPE_CUSTOM"
  ];

  # Field types for panel configuration
  fieldTypeEnum = lib.types.enum [
    "FIELD_TYPE_UNSPECIFIED"
    "FIELD_TYPE_STRING"
    "FIELD_TYPE_NUMBER"
    "FIELD_TYPE_BOOLEAN"
    "FIELD_TYPE_SELECT"
    "FIELD_TYPE_MULTISELECT"
    "FIELD_TYPE_APP_FILTER"
    "FIELD_TYPE_COLUMNS"
    "FIELD_TYPE_JSON"
  ];

  # ============================================================================
  # Submodule Types
  # ============================================================================

  # Module metadata
  moduleMetaType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name of the module";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Human-readable description of what the module does";
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Lucide icon name for the module (e.g., 'database', 'box', 'cloud')";
      };
      category = lib.mkOption {
        type = categoryEnum;
        default = "unspecified";
        description = "Category for grouping in the UI";
      };
      author = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Author or maintainer of the module";
      };
      version = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Module version";
      };
      homepage = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "URL to module documentation or repository";
      };
    };
  };

  # Module source configuration
  moduleSourceType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = sourceTypeEnum;
        default = "builtin";
        description = "Source type for the module";
      };
      flakeInput = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Name of the flake input (for flake-input source type)";
      };
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Local path to the module (for local source type)";
      };
      registryId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Registry identifier (for registry source type, e.g., 'stackpanel/docker')";
      };
      ref = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Git ref (branch, tag, commit) for remote modules";
      };
    };
  };

  # Module feature flags - which stackpanel features this module uses
  moduleFeaturesType = lib.types.submodule {
    options = {
      files = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Module generates files via stackpanel.files";
      };
      scripts = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Module provides shell scripts/commands";
      };
      tasks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Module defines turborepo tasks";
      };
      healthchecks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Module defines health checks";
      };
      services = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Module configures background services/processes";
      };
      secrets = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Module manages secrets/variables";
      };
      packages = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Module adds devshell packages";
      };
      appModule = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Module extends per-app configuration via appModules";
      };
    };
  };

  # Panel field type
  panelFieldType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Field name (maps to component prop)";
      };
      type = lib.mkOption {
        type = fieldTypeEnum;
        default = "FIELD_TYPE_STRING";
        description = "Field type";
      };
      value = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Field value (JSON-encoded for complex types)";
      };
      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Options for select fields";
      };
    };
  };

  # Module panel type (for UI rendering)
  modulePanelType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Unique panel identifier";
      };
      title = lib.mkOption {
        type = lib.types.str;
        description = "Display title";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Panel description";
      };
      type = lib.mkOption {
        type = panelTypeEnum;
        default = "PANEL_TYPE_STATUS";
        description = "Panel type (determines which component to render)";
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Display order (lower = first)";
      };
      fields = lib.mkOption {
        type = lib.types.listOf panelFieldType;
        default = [ ];
        description = "Panel configuration fields";
      };
    };
  };

  # Per-app module data type
  moduleAppDataType = lib.types.submodule {
    options = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether module is enabled for this app";
      };
      config = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Module config for this app (string key-value pairs)";
      };
    };
  };

  # ============================================================================
  # Main Module Type
  # ============================================================================

  moduleType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        # Standard enable flag
        enable = lib.mkEnableOption "the ${name} module" // {
          default = false;
        };

        # Module metadata
        meta = lib.mkOption {
          type = moduleMetaType;
          default = {
            name = name;
          };
          description = "Module metadata for display in the UI";
        };

        # Source information
        source = lib.mkOption {
          type = moduleSourceType;
          default = { };
          description = "Module source configuration";
        };

        # Feature flags
        features = lib.mkOption {
          type = moduleFeaturesType;
          default = { };
          description = "Which stackpanel features this module uses";
        };

        # Dependencies
        requires = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Other modules that must be enabled for this module to work";
        };

        conflicts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Other modules that conflict with this module";
        };

        # Load order
        priority = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = "Load order priority (lower = earlier)";
        };

        # Tags for filtering
        tags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Tags for categorizing/filtering modules";
        };

        # Configuration schema for UI form generation
        configSchema = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            JSON Schema string for generating configuration forms in the UI.
            The schema should describe the module's configurable options.
          '';
          example = ''
            {
              "type": "object",
              "properties": {
                "port": { "type": "integer", "default": 5432 },
                "version": { "type": "string", "enum": ["15", "16"], "default": "16" }
              }
            }
          '';
        };

        # UI panels
        panels = lib.mkOption {
          type = lib.types.listOf modulePanelType;
          default = [ ];
          description = "UI panels provided by this module";
        };

        # Per-app data
        apps = lib.mkOption {
          type = lib.types.attrsOf moduleAppDataType;
          default = { };
          description = "Per-app module data (app name -> module data)";
        };

        # Link to healthcheck module
        healthcheckModule = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Name of the healthcheck module that provides health checks for this module.
            This links to stackpanel.healthchecks.modules.<name>.
          '';
        };
      };
    }
  );

  # ============================================================================
  # Computed Values
  # ============================================================================

  # Filter to only enabled modules
  enabledModules = lib.filterAttrs (_: mod: mod.enable) cfg.modules;

  # Get builtin modules
  builtinModules = lib.filterAttrs (_: mod: mod.source.type == "builtin") enabledModules;

  # Get external modules (local, flake-input, registry)
  externalModules = lib.filterAttrs (_: mod: mod.source.type != "builtin") enabledModules;

  # Compute serializable module data (for API/UI consumption)
  computeSerializableModule = name: mod: {
    id = name;
    enabled = mod.enable;
    meta = {
      name = mod.meta.name;
      description = mod.meta.description;
      icon = mod.meta.icon;
      category = mod.meta.category;
      author = mod.meta.author;
      version = mod.meta.version;
      homepage = mod.meta.homepage;
    };
    source = {
      type = mod.source.type;
      flakeInput = mod.source.flakeInput;
      path = mod.source.path;
      registryId = mod.source.registryId;
      ref = mod.source.ref;
    };
    features = {
      files = mod.features.files;
      scripts = mod.features.scripts;
      tasks = mod.features.tasks;
      healthchecks = mod.features.healthchecks;
      services = mod.features.services;
      secrets = mod.features.secrets;
      packages = mod.features.packages;
      appModule = mod.features.appModule;
    };
    requires = mod.requires;
    conflicts = mod.conflicts;
    priority = mod.priority;
    tags = mod.tags;
    configSchema = mod.configSchema;
    panels = map (panel: {
      id = panel.id;
      title = panel.title;
      description = panel.description;
      type = panel.type;
      order = panel.order;
      fields = map (field: {
        name = field.name;
        type = field.type;
        value = field.value;
        options = field.options;
      }) panel.fields;
    }) mod.panels;
    apps = lib.mapAttrs (_: appData: {
      enabled = appData.enabled;
      config = appData.config;
    }) mod.apps;
    healthcheckModule = mod.healthcheckModule;
  };

  # All modules as serializable attrset
  modulesComputed = lib.mapAttrs computeSerializableModule cfg.modules;

  # Enabled modules only
  modulesComputedEnabled = lib.mapAttrs computeSerializableModule enabledModules;

  # Flat list for API consumption
  modulesList = lib.mapAttrsToList computeSerializableModule cfg.modules;
  modulesListEnabled = lib.mapAttrsToList computeSerializableModule enabledModules;

in
{
  # ============================================================================
  # Options
  # ============================================================================

  options.stackpanel.modules = lib.mkOption {
    type = lib.types.attrsOf moduleType;
    default = { };
    description = ''
      Stackpanel modules that provide features and UI panels.

      Modules are the unified way to extend stackpanel functionality:
        - Add packages, scripts, and environment configuration
        - Generate files and manage secrets
        - Define health checks and background services
        - Provide UI panels for the web studio
        - Extend per-app configuration

      Each module can define:
        - `enable`: Whether the module is active
        - `meta`: Display metadata (name, description, icon, category)
        - `source`: Where the module comes from (builtin, local, flake-input, registry)
        - `features`: Which stackpanel systems it uses
        - `panels`: UI panels to render in the web studio
        - `configSchema`: JSON Schema for configuration form generation
        - `healthcheckModule`: Link to health checks

      Modules can be:
        - Builtin: Shipped with stackpanel
        - Local: Defined in your project
        - Remote: Installed via flake inputs or module registry
    '';
    example = lib.literalExpression ''
      {
        postgres = {
          enable = true;
          meta = {
            name = "PostgreSQL";
            description = "PostgreSQL database server";
            icon = "database";
            category = "database";
          };
          source.type = "builtin";
          features = {
            services = true;
            healthchecks = true;
            packages = true;
          };
          healthcheckModule = "postgres";
          panels = [{
            id = "postgres-status";
            title = "PostgreSQL Status";
            type = "PANEL_TYPE_STATUS";
            fields = [{
              name = "metrics";
              type = "FIELD_TYPE_JSON";
              value = "[{\"label\":\"Status\",\"value\":\"Running\",\"status\":\"ok\"}]";
            }];
          }];
        };

        my-custom-module = {
          enable = true;
          meta = {
            name = "My Custom Module";
            description = "Does something useful";
            category = "development";
          };
          source = {
            type = "flake-input";
            flakeInput = "my-module";
          };
        };
      }
    '';
  };

  # ============================================================================
  # Computed Read-Only Options
  # ============================================================================

  options.stackpanel.modulesComputed = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = modulesComputedEnabled;
    description = "Computed module configurations (only enabled modules, serializable)";
  };

  options.stackpanel.modulesComputedAll = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = modulesComputed;
    description = "Computed module configurations (all modules including disabled, serializable)";
  };

  options.stackpanel.modulesList = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    default = modulesListEnabled;
    description = "Flat list of enabled modules (for API consumption)";
  };

  options.stackpanel.modulesListAll = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    default = modulesList;
    description = "Flat list of all modules including disabled (for API consumption)";
  };

  options.stackpanel.modulesBuiltin = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = builtinModules;
    description = "Builtin modules shipped with stackpanel";
  };

  options.stackpanel.modulesExternal = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = externalModules;
    description = "External modules (local, flake-input, or registry)";
  };

  # ============================================================================
  # Config: Validation
  # ============================================================================

  # NOTE: Assertions are not available in devenv's module system.
  # Module dependency validation would need to be implemented differently,
  # perhaps using devenv's warning system or runtime checks.
  # For now, dependency checks are skipped.
  #
  # TODO: Implement module dependency validation using devenv-compatible mechanism
  # The validation logic should check:
  # - Required modules are enabled when a module that requires them is enabled
  # - Conflicting modules are not both enabled simultaneously
}
