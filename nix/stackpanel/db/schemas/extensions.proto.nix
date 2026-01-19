# ==============================================================================
# extensions.proto.nix
#
# Protobuf schema for extensions/plugins configuration.
#
# Extensions are feature modules that compose core stackpanel features:
#   - File generation (stackpanel.files.entries)
#   - Script generation (stackpanel.scripts)
#   - Tasks (stackpanel.tasks)
#   - Variables/secrets (stackpanel.secrets)
#   - Shell hooks (stackpanel.devshell.hooks)
#   - UI panels (stackpanel.extensions.*.panels)
#
# Extensions can be:
#   - Builtin: Shipped with stackpanel (e.g., sst, ci, docker)
#   - Local: Defined in the project
#   - External: Installed from GitHub or other sources
#
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "extensions.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = {
    # Source type for extensions
    ExtensionSourceType = proto.mkEnum {
      name = "ExtensionSourceType";
      description = "Source type for extensions";
      values = [
        "EXTENSION_SOURCE_TYPE_UNSPECIFIED"
        "EXTENSION_SOURCE_TYPE_BUILTIN"
        "EXTENSION_SOURCE_TYPE_LOCAL"
        "EXTENSION_SOURCE_TYPE_GITHUB"
        "EXTENSION_SOURCE_TYPE_NPM"
        "EXTENSION_SOURCE_TYPE_URL"
      ];
    };

    # Extension category for organization
    ExtensionCategory = proto.mkEnum {
      name = "ExtensionCategory";
      description = "Category of extension for grouping in UI";
      values = [
        "EXTENSION_CATEGORY_UNSPECIFIED"
        "EXTENSION_CATEGORY_INFRASTRUCTURE"
        "EXTENSION_CATEGORY_CI_CD"
        "EXTENSION_CATEGORY_DATABASE"
        "EXTENSION_CATEGORY_SECRETS"
        "EXTENSION_CATEGORY_DEPLOYMENT"
        "EXTENSION_CATEGORY_DEVELOPMENT"
        "EXTENSION_CATEGORY_MONITORING"
        "EXTENSION_CATEGORY_INTEGRATION"
      ];
    };

    # Panel types for UI rendering
    PanelType = proto.mkEnum {
      name = "PanelType";
      description = "Type of UI panel component to render";
      values = [
        "PANEL_TYPE_UNSPECIFIED"
        "PANEL_TYPE_STATUS"
        "PANEL_TYPE_APPS_GRID"
        "PANEL_TYPE_FORM"
        "PANEL_TYPE_TABLE"
        "PANEL_TYPE_CUSTOM"
      ];
    };

    # Field types for panel configuration
    FieldType = proto.mkEnum {
      name = "FieldType";
      description = "Type of configuration field";
      values = [
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
    };
  };

  messages = {
    # ──────────────────────────────────────────────────────────────────────────
    # Root extensions configuration
    # ──────────────────────────────────────────────────────────────────────────
    Extensions = proto.mkMessage {
      name = "Extensions";
      description = "Extensions and plugins configuration";
      fields = {
        enabled = proto.bool 1 "Enable extensions system";
        auto_update = proto.bool 2 "Automatically check for extension updates";
        registry = proto.optional (proto.string 3 "Default extension registry URL");
        extensions = proto.map "string" "Extension" 4 "Installed extensions by key";
      };
    };

    # ──────────────────────────────────────────────────────────────────────────
    # Extension definition
    # ──────────────────────────────────────────────────────────────────────────
    Extension = proto.mkMessage {
      name = "Extension";
      description = "Extension configuration and metadata";
      fields = {
        # Identity
        name = proto.string 1 "Display name of the extension";
        description = proto.optional (
          proto.string 2 "Human-readable description of what the extension does"
        );

        # Status
        enabled = proto.bool 3 "Whether this extension is enabled";
        builtin = proto.bool 4 "Whether this is a built-in extension shipped with stackpanel";

        # Source information
        source = proto.message "ExtensionSource" 5 "Extension source configuration";
        version = proto.optional (proto.string 6 "Version constraint (e.g., '^1.0.0', '~2.3', 'latest')");

        # Organization
        category = proto.message "ExtensionCategory" 7 "Category for grouping in UI";
        priority = proto.int32 8 "Load order priority (lower = earlier)";
        tags = proto.repeated (proto.string 9 "Tags for filtering extensions");
        dependencies = proto.repeated (proto.string 10 "Other extensions this depends on");

        # UI configuration
        panels = proto.repeated (proto.message "ExtensionPanel" 11 "UI panels provided by this extension");
        apps =
          proto.map "string" "ExtensionAppData" 12
            "Per-app extension data (app name -> extension data)";

        # Feature flags - what core features this extension uses
        features = proto.message "ExtensionFeatures" 13 "Core features this extension configures";
      };
    };

    # ──────────────────────────────────────────────────────────────────────────
    # Extension source configuration
    # ──────────────────────────────────────────────────────────────────────────
    ExtensionSource = proto.mkMessage {
      name = "ExtensionSource";
      description = "Extension source configuration";
      fields = {
        type = proto.message "ExtensionSourceType" 1 "Source type for the extension";
        repo = proto.optional (proto.string 2 "GitHub repository (owner/repo) for github source type");
        package = proto.optional (proto.string 3 "NPM package name for npm source type");
        path = proto.optional (proto.string 4 "Local path for local source type");
        url = proto.optional (proto.string 5 "URL for url source type");
        ref = proto.optional (proto.string 6 "Git ref (branch, tag, commit) for github source type");
        module_path = proto.optional (proto.string 7 "Path to the Nix module within the source");
      };
    };

    # ──────────────────────────────────────────────────────────────────────────
    # Extension features - what core stackpanel features this extension uses
    # ──────────────────────────────────────────────────────────────────────────
    ExtensionFeatures = proto.mkMessage {
      name = "ExtensionFeatures";
      description = "Flags indicating which core stackpanel features this extension configures";
      fields = {
        files = proto.bool 1 "Extension generates files via stackpanel.files";
        scripts = proto.bool 2 "Extension provides shell scripts/commands";
        tasks = proto.bool 3 "Extension defines tasks";
        secrets = proto.bool 4 "Extension manages secrets/variables";
        shell_hooks = proto.bool 5 "Extension adds shell hooks";
        packages = proto.bool 6 "Extension adds devshell packages";
        services = proto.bool 7 "Extension configures services/processes";
        checks = proto.bool 8 "Extension defines checks/validations";
      };
    };

    # ──────────────────────────────────────────────────────────────────────────
    # UI Panel configuration
    # ──────────────────────────────────────────────────────────────────────────
    ExtensionPanel = proto.mkMessage {
      name = "ExtensionPanel";
      description = "UI panel configuration for the web interface";
      fields = {
        id = proto.string 1 "Unique panel identifier";
        title = proto.string 2 "Display title";
        description = proto.optional (proto.string 3 "Panel description");
        type = proto.message "PanelType" 4 "Panel type (determines which component to render)";
        order = proto.int32 5 "Display order (lower = first)";
        fields = proto.repeated (proto.message "PanelField" 6 "Panel configuration fields");
      };
    };

    # Panel field configuration
    PanelField = proto.mkMessage {
      name = "PanelField";
      description = "Configuration field for a panel";
      fields = {
        name = proto.string 1 "Field name (maps to component prop)";
        type = proto.message "FieldType" 2 "Field type";
        value = proto.string 3 "Field value (JSON-encoded for complex types)";
        options = proto.repeated (proto.string 4 "Options for select fields");
      };
    };

    # ──────────────────────────────────────────────────────────────────────────
    # Per-app extension data
    # ──────────────────────────────────────────────────────────────────────────
    ExtensionAppData = proto.mkMessage {
      name = "ExtensionAppData";
      description = "Extension data specific to an application";
      fields = {
        enabled = proto.bool 1 "Whether extension is enabled for this app";
        config = proto.map "string" "string" 2 "Extension config for this app (string key-value pairs)";
      };
    };
  };
}
