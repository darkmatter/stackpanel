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

        # Flake inputs required by this module (for auto-installation)
        flakeInputs = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Input name in flake.nix (e.g., \"my-module\")";
                };
                url = lib.mkOption {
                  type = lib.types.str;
                  description = "Flake URL (e.g., \"github:author/my-module\")";
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
