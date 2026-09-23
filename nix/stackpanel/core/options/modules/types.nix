{
  lib,
}:
let
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

  # Module metadata
  moduleMetaType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Human-readable module name shown in the Studio UI.";
        example = "PostgreSQL";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Human-readable summary of what the module configures or provides.";
        example = "Runs a local PostgreSQL service and exposes connection variables.";
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Lucide icon name used for this module in the Studio UI.";
        example = "database";
      };
      category = lib.mkOption {
        type = categoryEnum;
        default = "unspecified";
        description = "Category used to group this module in module lists and filters.";
        example = "database";
      };
      author = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Author or maintainer displayed for third-party modules.";
        example = "darkmatter";
      };
      version = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Module version string displayed in the UI and serialized metadata.";
        example = "1.0.0";
      };
      homepage = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "URL to module documentation, homepage, or source repository.";
        example = "https://github.com/darkmatter/stackpanel";
      };
    };
  };

  # Module source configuration
  moduleSourceType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = sourceTypeEnum;
        default = "builtin";
        description = "Where Stackpanel should consider this module to come from.";
        example = "builtin";
      };
      flakeInput = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Flake input name that provides this module when source.type is `flake-input`.";
        example = "stackpanel-postgres";
      };
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Repo-relative or absolute path to the module when source.type is `local`.";
        example = "./.stack/modules/postgres";
      };
      registryId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Registry identifier used to install this module when source.type is `registry`.";
        example = "stackpanel/docker";
      };
      ref = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Git branch, tag, or commit used for remote module sources.";
        example = "main";
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
        description = "Whether this module contributes Turborepo task definitions.";
        example = true;
      };
      healthchecks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this module contributes runtime healthchecks.";
        example = true;
      };
      services = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Module configures background services/processes";
      };
      secrets = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this module contributes variables or secret metadata.";
        example = true;
      };
      packages = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this module adds packages to the devshell.";
        example = true;
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
        description = "Field name passed to the module panel component as a prop key.";
        example = "metrics";
      };
      type = lib.mkOption {
        type = fieldTypeEnum;
        default = "FIELD_TYPE_STRING";
        description = "Renderer type the UI should use for this module panel field.";
        example = "FIELD_TYPE_JSON";
      };
      value = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Field value passed to the UI; complex values should be JSON-encoded strings.";
        example = "[{\"label\":\"Status\",\"value\":\"Running\"}]";
      };
      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Selectable values for select-style module panel fields.";
        example = [
          "dev"
          "prod"
        ];
      };
    };
  };

  # Module panel type (for UI rendering)
  modulePanelType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Unique panel identifier within this module.";
        example = "postgres-status";
      };
      title = lib.mkOption {
        type = lib.types.str;
        description = "Title shown at the top of this module panel.";
        example = "PostgreSQL Status";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional explanatory text shown below the module panel title.";
        example = "Connection and migration health for local PostgreSQL.";
      };
      type = lib.mkOption {
        type = panelTypeEnum;
        default = "PANEL_TYPE_STATUS";
        description = "Panel type (determines which component to render)";
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Display order among this module's panels; lower values appear first.";
        example = 10;
      };
      fields = lib.mkOption {
        type = lib.types.listOf panelFieldType;
        default = [ ];
        description = "Fields passed to the UI component that renders this module panel.";
      };
    };
  };

  # Per-app module data type
  moduleAppDataType = lib.types.submodule {
    options = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this module is enabled for the app entry in app-scoped UI data.";
        example = true;
      };
      config = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "String metadata for this app/module pair, serialized for UI panels.";
        example = {
          port = "5432";
          database = "app";
        };
      };
    };
  };

  # Main Module Type
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
            inherit name;
          };
          description = "Module metadata used for display, discovery, and filtering in the UI.";
        };

        # Source information
        source = lib.mkOption {
          type = moduleSourceType;
          default = { };
          description = "Source information used to identify or install this module.";
        };

        # Feature flags
        features = lib.mkOption {
          type = moduleFeaturesType;
          default = { };
          description = "Feature flags declaring which Stackpanel subsystems this module integrates with.";
        };

        # Dependencies
        requires = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Module IDs that must be enabled before this module can work correctly.";
          example = [
            "secrets"
            "caddy"
          ];
        };

        conflicts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Module IDs that cannot be enabled at the same time as this module.";
          example = [ "mysql" ];
        };

        # Flake inputs required by this module (for auto-installation)
        flakeInputs = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Input name to add under `inputs` in flake.nix.";
                  example = "my-module";
                };
                url = lib.mkOption {
                  type = lib.types.str;
                  description = "Flake URL used for this required module input.";
                  example = "github:author/my-module";
                };
                followsNixpkgs = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Whether to add inputs.nixpkgs.follows = \"nixpkgs\"";
                };
              };
            }
          );
          default = [ ];
          description = "Flake inputs required by this module. Used for auto-installation from the registry.";
        };

        # Load order
        priority = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = "Load order priority for module processing; lower values load earlier.";
          example = 50;
        };

        # Tags for filtering
        tags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Tags used for module search, filtering, and catalog grouping.";
          example = [
            "database"
            "local-dev"
          ];
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
          description = "UI panels registered by this module for the Studio.";
        };

        # Per-app data
        apps = lib.mkOption {
          type = lib.types.attrsOf moduleAppDataType;
          default = { };
          description = "Per-app module metadata keyed by app name for app-scoped panels.";
        };

        # Link to healthcheck module
        healthcheckModule = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Name of the doctor module that provides health checks for this module.
            This links to stackpanel.doctor.<name>.
          '';
        };
      };
    }
  );
in
{
  inherit
    sourceTypeEnum
    categoryEnum
    panelTypeEnum
    fieldTypeEnum
    moduleMetaType
    moduleSourceType
    moduleFeaturesType
    panelFieldType
    modulePanelType
    moduleAppDataType
    moduleType
    ;
}
