# ==============================================================================
# panels.nix
#
# UI Panel configuration for core Stackpanel modules.
#
# This is separate from extensions - panels here are for built-in modules like
# Go, Caddy, Healthchecks, Theme, etc. Extensions (like SST) define their own
# panels within their extension configuration.
#
# Core modules register panels like this:
#
#   stackpanel.panels.go-status = {
#     module = "go";
#     title = "Go Environment";
#     type = "PANEL_TYPE_STATUS";
#     order = 10;
#     fields = [
#       { name = "metrics"; type = "FIELD_TYPE_STRING"; value = "..."; }
#     ];
#   };
#
# The panels are exposed via nix eval for the agent/web UI to consume.
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

  # Panel types for UI rendering
  panelTypeEnum = lib.types.enum [
    "PANEL_TYPE_UNSPECIFIED"
    "PANEL_TYPE_STATUS"
    "PANEL_TYPE_APPS_GRID"
    "PANEL_TYPE_FORM"
    "PANEL_TYPE_TABLE"
    "PANEL_TYPE_CUSTOM"
    "PANEL_TYPE_APP_CONFIG"
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
    "FIELD_TYPE_CODE"
  ];

  # Panel field type
  panelFieldType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Field name passed to the panel component as a prop key.";
        example = "metrics";
      };
      type = lib.mkOption {
        type = fieldTypeEnum;
        default = "FIELD_TYPE_STRING";
        description = ''
          Field renderer hint for the Studio UI.

          - `FIELD_TYPE_STRING`, `FIELD_TYPE_NUMBER`, `FIELD_TYPE_BOOLEAN`: scalar display/input values.
          - `FIELD_TYPE_SELECT`, `FIELD_TYPE_MULTISELECT`: selectable values from `options`.
          - `FIELD_TYPE_APP_FILTER`: app selector/filter control.
          - `FIELD_TYPE_COLUMNS`: table column metadata.
          - `FIELD_TYPE_JSON`: JSON-encoded structured data.
          - `FIELD_TYPE_CODE`: code or config text.
        '';
        example = "FIELD_TYPE_SELECT";
      };
      value = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "";
        description = ''
          Field value passed to the UI.

          Values are serialized as strings for transport. Use `builtins.toJSON`
          for arrays/objects consumed by JSON-aware panel renderers. `null`
          means unset.
        '';
        example = lib.literalExpression ''
          builtins.toJSON [
            { label = "PostgreSQL"; value = "running"; status = "ok"; }
            { label = "Redis"; value = "stopped"; status = "warning"; }
          ]
        '';
      };
      options = lib.mkOption {
        type = lib.types.listOf (
          lib.types.either lib.types.str (
            lib.types.submodule {
              options = {
                value = lib.mkOption {
                  type = lib.types.str;
                  description = "Machine-readable option value submitted by the UI.";
                  example = "prod";
                };
                label = lib.mkOption {
                  type = lib.types.str;
                  description = "Human-readable label shown for this option in the UI.";
                  example = "Production";
                };
              };
            }
          )
        );
        default = [ ];
        description = ''
          Selectable values for `FIELD_TYPE_SELECT` and `FIELD_TYPE_MULTISELECT` fields.

          Use strings when the display label and submitted value are identical,
          or `{ value, label }` objects when the UI label should differ from the
          persisted value.
        '';
        example = lib.literalExpression ''
          [
            "dev"
            "staging"
            { value = "prod"; label = "Production"; }
          ]
        '';
      };

      # Extended fields for PANEL_TYPE_APP_CONFIG
      label = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Human-readable field label; when null, the UI falls back to `name`.";
        example = "Database URL";
      };
      editable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the Studio UI may submit edits for this field.";
        example = true;
      };
      editPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Dot-separated path within the app's config for writes.
          E.g., "go.mainPackage" tells the agent to patch
          apps.<appId>.go.mainPackage in the data file.
        '';
      };
      placeholder = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Placeholder text shown in editable text input fields.";
        example = "postgres://localhost:5432/app";
      };
      configPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Nix config path where UI edits should be saved.";
        example = "stackpanel.apps.web.port";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Help text shown below the field in the Studio UI.";
        example = "Used by local development and preview deploys.";
      };
      example = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Example value shown as inline help for this field.";
        example = "3000";
      };
    };
  };

  # Module panel type - a panel belonging to a core module
  modulePanelType = lib.types.submodule {
    options = {
      # Which module this panel belongs to
      module = lib.mkOption {
        type = lib.types.str;
        description = ''
          The core module this panel belongs to (e.g., "go", "caddy", "healthchecks").
          Used for grouping panels in the UI.
        '';
        example = "healthchecks";
      };

      # Display settings
      title = lib.mkOption {
        type = lib.types.str;
        description = "Title shown at the top of this core module panel.";
        example = "Go Environment";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional summary shown below the panel title.";
        example = "Healthcheck status for configured services.";
      };
      readme = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Module documentation in markdown format.
          Rendered in the UI panel to help users understand the module's configuration.
        '';
        example = lib.literalExpression ''
          "## Healthchecks\n\nCritical failures mark the module unhealthy. Warning failures mark it degraded."
        '';
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Icon name from lucide-react, without the React component suffix.";
        example = "activity";
      };

      # Panel type and configuration
      type = lib.mkOption {
        type = panelTypeEnum;
        default = "PANEL_TYPE_STATUS";
        description = ''
          Panel renderer used by the Studio UI.

          - `PANEL_TYPE_STATUS`: status/metric summary cards.
          - `PANEL_TYPE_APPS_GRID`: app cards keyed by `apps`.
          - `PANEL_TYPE_FORM`: editable or read-only fields.
          - `PANEL_TYPE_TABLE`: tabular data from `columns` and `rows`.
          - `PANEL_TYPE_APP_CONFIG`: app configuration editor fields.
          - `PANEL_TYPE_CUSTOM`: custom renderer selected by the frontend.
        '';
        example = "PANEL_TYPE_TABLE";
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Display order within the module; lower values render first.";
        example = 10;
      };
      fields = lib.mkOption {
        type = lib.types.listOf panelFieldType;
        default = [ ];
        description = ''
          Field definitions passed to the panel renderer.

          For status panels, fields often carry JSON-encoded metric arrays. For
          form and app-config panels, fields describe editable inputs and their
          `configPath`/`editPath` targets.
        '';
        example = lib.literalExpression ''
          [
            {
              name = "environment";
              label = "Environment";
              type = "FIELD_TYPE_SELECT";
              value = "dev";
              options = [ "dev" "staging" "prod" ];
              editable = true;
              configPath = "stackpanel.apps.web.env";
            }
          ]
        '';
      };

      # Visibility
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this panel is included in computed UI output.";
        example = false;
      };

      # Optional: Columns for PANEL_TYPE_TABLE
      columns = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              key = lib.mkOption {
                type = lib.types.str;
                description = "Column key used to read values from each row object.";
                example = "status";
              };
              label = lib.mkOption {
                type = lib.types.str;
                description = "Human-readable column header shown in table panels.";
                example = "Status";
              };
            };
          }
        );
        default = [ ];
        description = "Column definitions used by `PANEL_TYPE_TABLE`; each `key` must match keys present in `rows`.";
        example = lib.literalExpression ''
          [
            { key = "name"; label = "Service"; }
            { key = "status"; label = "Status"; }
          ]
        '';
      };

      # Optional: Rows for PANEL_TYPE_TABLE
      rows = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.str);
        default = [ ];
        description = "Rows rendered by `PANEL_TYPE_TABLE`, with string values keyed by `columns[*].key`.";
        example = lib.literalExpression ''
          [
            { name = "postgres"; status = "ok"; port = "5432"; }
            { name = "redis"; status = "warning"; port = "6379"; }
          ]
        '';
      };

      # Optional: Apps data for PANEL_TYPE_APPS_GRID
      apps = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enabled = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether this app entry is visible in the apps-grid panel.";
                example = true;
              };
              config = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "String metadata for this app entry, consumed by the apps-grid panel.";
                example = {
                  port = "3000";
                  url = "http://localhost:3000";
                };
              };
            };
          }
        );
        default = { };
        description = ''
          Per-app metadata rendered by `PANEL_TYPE_APPS_GRID` panels.

          Attribute names are app IDs. `config` values are strings so the
          serialized panel output remains JSON-friendly and predictable.
        '';
        example = lib.literalExpression ''
          {
            web = {
              enabled = true;
              config = {
                port = "3000";
                url = "http://localhost:3000";
                framework = "tanstack-start";
              };
            };
          }
        '';
      };
    };
  };

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Serialize a panel for JSON output
  serializePanel = id: panel: {
    inherit id;
    inherit (panel) module;
    inherit (panel) title;
    inherit (panel) description;
    inherit (panel) readme;
    inherit (panel) icon;
    inherit (panel) type;
    inherit (panel) order;
    inherit (panel) enabled;
    fields = map (f: {
      inherit (f) name;
      inherit (f) type;
      inherit (f) value;
      inherit (f) options;
      inherit (f) label;
      inherit (f) editable;
      inherit (f) editPath;
      inherit (f) placeholder;
      inherit (f) configPath;
      inherit (f) description;
      inherit (f) example;
    }) panel.fields;
    apps = lib.mapAttrs (_name: appData: {
      inherit (appData) enabled;
      inherit (appData) config;
    }) panel.apps;
    inherit (panel) columns;
    inherit (panel) rows;
  };

  # Group panels by module
  groupPanelsByModule =
    panels:
    let
      # Get unique module names
      moduleNames = lib.unique (lib.mapAttrsToList (_id: p: p.module) panels);

      # Get panels for a specific module
      panelsForModule = moduleName: lib.filterAttrs (_id: p: p.module == moduleName) panels;
    in
    lib.genAttrs moduleNames panelsForModule;

in
{
  # ============================================================================
  # Options
  # ============================================================================

  options.stackpanel.panels = lib.mkOption {
    type = lib.types.attrsOf modulePanelType;
    default = { };
    description = ''
      UI panels for core Stackpanel modules.

      Panels are UI components that display information about a module's state,
      configuration, or managed resources. Unlike extension panels, these belong
      to built-in modules like Go, Caddy, Healthchecks, etc.

      Example:
        stackpanel.panels.go-status = {
          module = "go";
          title = "Go Environment";
          type = "PANEL_TYPE_STATUS";
          order = 10;
          fields = [
            { name = "metrics"; type = "FIELD_TYPE_STRING"; value = "..."; }
          ];
        };
    '';
    example = lib.literalExpression ''
      {
        go-status = {
          module = "go";
          title = "Go Environment";
          type = "PANEL_TYPE_STATUS";
          order = 10;
          fields = [
            {
              name = "metrics";
              type = "FIELD_TYPE_STRING";
              value = builtins.toJSON [
                { label = "Go Version"; value = "1.22"; status = "ok"; }
                { label = "Apps"; value = "3"; status = "ok"; }
              ];
            }
          ];
        };
        caddy-status = {
          module = "caddy";
          title = "Reverse Proxy";
          type = "PANEL_TYPE_STATUS";
          order = 20;
          fields = [ ... ];
        };
      }
    '';
  };

  # Computed/serializable panels for nix eval
  options.stackpanel.panelsComputed = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    description = "Serializable panels for UI consumption";
  };

  # Panels grouped by module
  options.stackpanel.panelsByModule = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
    readOnly = true;
    description = "Panels grouped by their parent module";
  };

  # List of panels (for iteration)
  options.stackpanel.panelsList = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    description = "List of enabled panels sorted by display order for UI iteration.";
  };

  # List of modules that have panels
  options.stackpanel.panelModules = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    description = "List of module names that have registered panels";
  };

  # ============================================================================
  # Config
  # ============================================================================

  config = {
    # Serialize panels for UI
    stackpanel.panelsComputed = lib.mapAttrs serializePanel (
      lib.filterAttrs (_id: p: p.enabled) cfg.panels
    );

    # Group by module
    stackpanel.panelsByModule =
      let
        enabledPanels = lib.filterAttrs (_id: p: p.enabled) cfg.panels;
        serialized = lib.mapAttrs serializePanel enabledPanels;
      in
      groupPanelsByModule serialized;

    # Sorted list of panels
    stackpanel.panelsList =
      let
        enabledPanels = lib.filterAttrs (_id: p: p.enabled) cfg.panels;
        serialized = lib.mapAttrs serializePanel enabledPanels;
        asList = lib.mapAttrsToList (_id: panel: panel) serialized;
      in
      lib.sort (a: b: a.order < b.order) asList;

    # List of modules with panels
    stackpanel.panelModules =
      let
        enabledPanels = lib.filterAttrs (_id: p: p.enabled) cfg.panels;
      in
      lib.unique (lib.mapAttrsToList (_id: p: p.module) enabledPanels);
  };
}
