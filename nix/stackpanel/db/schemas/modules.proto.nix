# ==============================================================================
# modules.proto.nix
#
# Protobuf schema for Stackpanel module configuration.
# Mirrors the Nix module system options for API/UI consumption.
#
# Modules are the primary way to extend stackpanel functionality:
#   - Add devshell packages, hooks, and environment variables
#   - Generate files via stackpanel.files.entries
#   - Provide shell scripts/commands via stackpanel.scripts
#   - Define health checks via stackpanel.healthchecks
#   - Register UI panels for the web studio
#   - Extend per-app configuration via stackpanel.appModules
#
# Data flow:
#   Read:  Nix evaluates stackpanel.modulesComputed -> JSON -> Agent serves via RPC
#   Write: UI edits -> Agent writes to .stack/data/modules.nix -> Nix re-evaluates
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "modules.proto";
  package = "stackpanel.db";

  boilerplate = ''
    # modules.nix - Module configuration
    # type: sp-module
    # See: https://stackpanel.dev/docs/modules
    #
    # Modules extend stackpanel with additional functionality.
    # Enable built-in modules or install from the registry.
    {
      # Example: Enable the OxLint module
      # oxlint = {
      #   enable = true;
      # };
      #
      # Example: Configure a module with settings
      # postgres = {
      #   enable = true;
      #   settings = {
      #     version = "16";
      #     port = "5432";
      #   };
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  # ===========================================================================
  # Enums
  # ===========================================================================
  enums = {
    # Module source types
    ModuleSourceType = proto.mkEnum {
      name = "ModuleSourceType";
      description = "Where the module comes from";
      values = [
        "MODULE_SOURCE_TYPE_UNSPECIFIED"
        "MODULE_SOURCE_TYPE_BUILTIN" # Shipped with stackpanel
        "MODULE_SOURCE_TYPE_LOCAL" # Defined in project
        "MODULE_SOURCE_TYPE_FLAKE_INPUT" # Installed via flake input
        "MODULE_SOURCE_TYPE_REGISTRY" # Installed from module registry
      ];
    };

    # Module categories for UI grouping
    ModuleCategory = proto.mkEnum {
      name = "ModuleCategory";
      description = "Category for grouping modules in the UI";
      values = [
        "MODULE_CATEGORY_UNSPECIFIED"
        "MODULE_CATEGORY_INFRASTRUCTURE"
        "MODULE_CATEGORY_CI_CD"
        "MODULE_CATEGORY_DATABASE"
        "MODULE_CATEGORY_SECRETS"
        "MODULE_CATEGORY_DEPLOYMENT"
        "MODULE_CATEGORY_DEVELOPMENT"
        "MODULE_CATEGORY_MONITORING"
        "MODULE_CATEGORY_INTEGRATION"
        "MODULE_CATEGORY_LANGUAGE" # Language-specific tooling
        "MODULE_CATEGORY_SERVICE" # Background services
      ];
    };

    # Panel types for UI rendering
    ModulePanelType = proto.mkEnum {
      name = "ModulePanelType";
      description = "Type of UI panel to render";
      values = [
        "MODULE_PANEL_TYPE_UNSPECIFIED"
        "MODULE_PANEL_TYPE_STATUS"
        "MODULE_PANEL_TYPE_APPS_GRID"
        "MODULE_PANEL_TYPE_FORM"
        "MODULE_PANEL_TYPE_TABLE"
        "MODULE_PANEL_TYPE_CUSTOM"
      ];
    };

    # Field types for panel configuration
    ModuleFieldType = proto.mkEnum {
      name = "ModuleFieldType";
      description = "Type of field in a panel";
      values = [
        "MODULE_FIELD_TYPE_UNSPECIFIED"
        "MODULE_FIELD_TYPE_STRING"
        "MODULE_FIELD_TYPE_NUMBER"
        "MODULE_FIELD_TYPE_BOOLEAN"
        "MODULE_FIELD_TYPE_SELECT"
        "MODULE_FIELD_TYPE_MULTISELECT"
        "MODULE_FIELD_TYPE_APP_FILTER"
        "MODULE_FIELD_TYPE_COLUMNS"
        "MODULE_FIELD_TYPE_JSON"
      ];
    };
  };

  # ===========================================================================
  # Messages
  # ===========================================================================
  messages = {
    # Module metadata for display in the UI
    ModuleMeta = proto.mkMessage {
      name = "ModuleMeta";
      description = "Display metadata for a module";
      fields = {
        name = proto.withExample "PostgreSQL" (proto.string 1 "Display name of the module");
        description = proto.optional (proto.withExample "Managed PostgreSQL service for local development" (proto.string 2 "Human-readable description"));
        icon = proto.optional (proto.withExample "database" (proto.string 3 "Lucide icon name (e.g., 'database', 'box')"));
        category = proto.message "ModuleCategory" 4 "Category for UI grouping";
        author = proto.optional (proto.withExample "Darkmatter" (proto.string 5 "Author or maintainer"));
        version = proto.optional (proto.withExample "1.2.0" (proto.string 6 "Module version"));
        homepage = proto.optional (proto.withExample "https://stackpanel.dev/docs/modules/postgres" (proto.string 7 "URL to documentation or repository"));
      };
    };

    # Module source configuration
    ModuleSource = proto.mkMessage {
      name = "ModuleSource";
      description = "Where the module comes from";
      fields = {
        type = proto.message "ModuleSourceType" 1 "Source type";
        flake_input = proto.optional (proto.withExample "stackpanel-postgres" (proto.string 2 "Flake input name (for flake-input type)"));
        path = proto.optional (proto.withExample "./modules/postgres" (proto.string 3 "Local path (for local type)"));
        registry_id = proto.optional (proto.withExample "stackpanel/postgres" (proto.string 4 "Registry ID (e.g., 'stackpanel/docker')"));
        ref = proto.optional (proto.withExample "main" (proto.string 5 "Git ref (branch, tag, commit)"));
      };
    };

    # Module feature flags
    ModuleFeatures = proto.mkMessage {
      name = "ModuleFeatures";
      description = "Which stackpanel features this module uses";
      fields = {
        files = proto.withExample true (proto.bool 1 "Generates files via stackpanel.files");
        scripts = proto.withExample true (proto.bool 2 "Provides shell scripts/commands");
        tasks = proto.withExample false (proto.bool 3 "Defines turborepo tasks");
        healthchecks = proto.withExample true (proto.bool 4 "Defines health checks");
        services = proto.withExample true (proto.bool 5 "Configures background services");
        secrets = proto.withExample false (proto.bool 6 "Manages secrets/variables");
        packages = proto.withExample true (proto.bool 7 "Adds devshell packages");
        app_module = proto.withExample false (proto.bool 8 "Extends per-app configuration");
      };
    };

    # Panel field definition
    ModulePanelField = proto.mkMessage {
      name = "ModulePanelField";
      description = "A field in a module panel";
      fields = {
        name = proto.withExample "version" (proto.string 1 "Field name (maps to component prop)");
        type = proto.message "ModuleFieldType" 2 "Field type";
        value = proto.withExample "16" (proto.string 3 "Field value (JSON-encoded for complex types)");
        options = proto.repeated (proto.withExample "16" (proto.string 4 "Options for select fields"));
      };
    };

    # Module panel for UI rendering
    ModulePanel = proto.mkMessage {
      name = "ModulePanel";
      description = "A UI panel provided by a module";
      fields = {
        id = proto.withExample "postgres-status" (proto.string 1 "Unique panel identifier");
        title = proto.withExample "Postgres" (proto.string 2 "Display title");
        description = proto.optional (proto.withExample "Process status, port, and connection string" (proto.string 3 "Panel description"));
        type = proto.message "ModulePanelType" 4 "Panel type (determines component)";
        order = proto.withExample 20 (proto.int32 5 "Display order (lower = first)");
        fields = proto.repeated (proto.message "ModulePanelField" 6 "Panel configuration fields");
      };
    };

    # Per-app module data
    ModuleAppData = proto.mkMessage {
      name = "ModuleAppData";
      description = "Module data for a specific app";
      fields = {
        enabled = proto.withExample true (proto.bool 1 "Whether module is enabled for this app");
        config = proto.map "string" "string" 2 "Module config (string key-value pairs)";
      };
    };

    # Main module configuration
    Module = proto.mkMessage {
      name = "Module";
      description = "Configuration for a stackpanel module";
      fields = {
        # Identity
        id = proto.withExample "postgres" (proto.string 1 "Module identifier (e.g., 'oxlint', 'postgres')");
        enable = proto.withExample true (proto.bool 2 "Whether the module is enabled");

        # Metadata
        meta = proto.message "ModuleMeta" 3 "Display metadata";

        # Source
        source = proto.message "ModuleSource" 4 "Source configuration";

        # Features
        features = proto.message "ModuleFeatures" 5 "Feature flags";

        # Dependencies
        requires = proto.repeated (proto.withExample "process-compose" (proto.string 6 "Required modules"));
        conflicts = proto.repeated (proto.withExample "mysql" (proto.string 7 "Conflicting modules"));

        # Ordering
        priority = proto.withExample 50 (proto.int32 8 "Load order priority (lower = earlier)");

        # Categorization
        tags = proto.repeated (proto.withExample "database" (proto.string 9 "Tags for filtering"));

        # Configuration
        config_schema = proto.optional (proto.withExample "{ \"type\": \"object\", \"properties\": { \"version\": { \"type\": \"string\" } } }" (proto.string 10 ''
          JSON Schema for generating configuration forms.
          Describes the module's configurable options.
        ''));
        settings = proto.map "string" "string" 11 ''
          Module-level settings (key-value pairs).
          These are passed to the Nix module configuration.
        '';

        # UI
        panels = proto.repeated (proto.message "ModulePanel" 12 "UI panels");

        # Per-app data
        apps = proto.map "string" "ModuleAppData" 13 "Per-app module data";

        # Health checks
        healthcheck_module = proto.optional (proto.withExample "postgres" (proto.string 14 "Linked healthcheck module name"));
      };
    };

    # Collection of modules
    Modules = proto.mkMessage {
      name = "Modules";
      description = "Map of module ID to module configuration";
      fields = {
        modules = proto.map "string" "Module" 1 "Map of module ID to config";
      };
    };

    # Request/Response messages for RPC
    EnableModuleRequest = proto.mkMessage {
      name = "EnableModuleRequest";
      description = "Request to enable a module";
      fields = {
        module_id = proto.withExample "postgres" (proto.string 1 "Module identifier to enable");
        settings = proto.map "string" "string" 2 "Initial settings (optional)";
      };
    };

    DisableModuleRequest = proto.mkMessage {
      name = "DisableModuleRequest";
      description = "Request to disable a module";
      fields = {
        module_id = proto.withExample "postgres" (proto.string 1 "Module identifier to disable");
      };
    };

    UpdateModuleSettingsRequest = proto.mkMessage {
      name = "UpdateModuleSettingsRequest";
      description = "Request to update module settings";
      fields = {
        module_id = proto.withExample "postgres" (proto.string 1 "Module identifier");
        settings = proto.map "string" "string" 2 "New settings";
      };
    };

    ModuleResponse = proto.mkMessage {
      name = "ModuleResponse";
      description = "Response containing a single module";
      fields = {
        module = proto.message "Module" 1 "The module";
        success = proto.withExample true (proto.bool 2 "Whether the operation succeeded");
        message = proto.optional (proto.withExample "Module enabled" (proto.string 3 "Status message"));
      };
    };

    # Module outputs - what a module creates/provides
    ModuleOutputFile = proto.mkMessage {
      name = "ModuleOutputFile";
      description = "A file generated by a module";
      fields = {
        path = proto.withExample ".stack/state/postgres.conf" (proto.string 1 "File path relative to project root");
        description = proto.optional (proto.withExample "Generated PostgreSQL config" (proto.string 2 "Description of the file"));
        type = proto.withExample "text" (proto.string 3 "File type: text, derivation, symlink");
      };
    };

    ModuleOutputScript = proto.mkMessage {
      name = "ModuleOutputScript";
      description = "A script provided by a module";
      fields = {
        name = proto.withExample "pg-reset" (proto.string 1 "Script name (command)");
        description = proto.optional (proto.withExample "Drop and recreate the development database" (proto.string 2 "Description of what the script does"));
      };
    };

    ModuleOutputHealthcheck = proto.mkMessage {
      name = "ModuleOutputHealthcheck";
      description = "A healthcheck defined by a module";
      fields = {
        id = proto.withExample "postgres-port" (proto.string 1 "Healthcheck ID");
        name = proto.withExample "PostgreSQL listening" (proto.string 2 "Display name");
        description = proto.optional (proto.withExample "TCP probe against the assigned port" (proto.string 3 "Description of what it checks"));
        severity = proto.withExample "critical" (proto.string 4 "Severity: critical, warning, info");
        type = proto.withExample "tcp" (proto.string 5 "Check type: script, http, tcp, nix");
      };
    };

    ModuleOutputPackage = proto.mkMessage {
      name = "ModuleOutputPackage";
      description = "A package added by a module";
      fields = {
        name = proto.withExample "postgresql_16" (proto.string 1 "Package name");
        version = proto.optional (proto.withExample "16.4" (proto.string 2 "Package version"));
        description = proto.optional (proto.withExample "PostgreSQL 16 server and client" (proto.string 3 "Package description"));
      };
    };

    ModuleOutputs = proto.mkMessage {
      name = "ModuleOutputs";
      description = "Aggregated outputs of what a module creates";
      fields = {
        module_id = proto.withExample "postgres" (proto.string 1 "Module identifier");
        files = proto.repeated (proto.message "ModuleOutputFile" 2 "Generated files");
        scripts = proto.repeated (proto.message "ModuleOutputScript" 3 "Provided scripts");
        healthchecks = proto.repeated (proto.message "ModuleOutputHealthcheck" 4 "Health checks");
        packages = proto.repeated (proto.message "ModuleOutputPackage" 5 "Added packages");
      };
    };

    GetModuleOutputsRequest = proto.mkMessage {
      name = "GetModuleOutputsRequest";
      description = "Request to get module outputs";
      fields = {
        module_id = proto.withExample "postgres" (proto.string 1 "Module identifier");
      };
    };
  };
}
