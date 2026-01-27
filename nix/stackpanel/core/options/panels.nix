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

      # Extended fields for PANEL_TYPE_APP_CONFIG
      label = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Human-readable label for the field (defaults to name if null)";
      };
      editable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the field can be modified from the UI";
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
        description = "Placeholder text for input fields";
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
      };

      # Display settings
      title = lib.mkOption {
        type = lib.types.str;
        description = "Display title for the panel";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional description shown below the title";
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Icon name from lucide-react (e.g., 'server', 'database')";
      };

      # Panel type and configuration
      type = lib.mkOption {
        type = panelTypeEnum;
        default = "PANEL_TYPE_STATUS";
        description = "Panel type (determines which component to render)";
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Display order within the module (lower = first)";
      };
      fields = lib.mkOption {
        type = lib.types.listOf panelFieldType;
        default = [ ];
        description = "Panel configuration fields passed to the component";
      };

      # Visibility
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this panel is enabled and should be shown";
      };

      # Optional: Apps data for PANEL_TYPE_APPS_GRID
      apps = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enabled = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
              config = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
              };
            };
          }
        );
        default = { };
        description = "Per-app data for apps grid panels";
      };
    };
  };

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Serialize a panel for JSON output
  serializePanel = id: panel: {
    id = id;
    module = panel.module;
    title = panel.title;
    description = panel.description;
    icon = panel.icon;
    type = panel.type;
    order = panel.order;
    enabled = panel.enabled;
    fields = map (f: {
      name = f.name;
      type = f.type;
      value = f.value;
      options = f.options;
      label = f.label;
      editable = f.editable;
      editPath = f.editPath;
      placeholder = f.placeholder;
    }) panel.fields;
    apps = lib.mapAttrs (name: appData: {
      enabled = appData.enabled;
      config = appData.config;
    }) panel.apps;
  };

  # Group panels by module
  groupPanelsByModule =
    panels:
    let
      # Get unique module names
      moduleNames = lib.unique (lib.mapAttrsToList (id: p: p.module) panels);

      # Get panels for a specific module
      panelsForModule = moduleName: lib.filterAttrs (id: p: p.module == moduleName) panels;
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
    description = "List of all panels sorted by order";
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
      lib.filterAttrs (id: p: p.enabled) cfg.panels
    );

    # Group by module
    stackpanel.panelsByModule =
      let
        enabledPanels = lib.filterAttrs (id: p: p.enabled) cfg.panels;
        serialized = lib.mapAttrs serializePanel enabledPanels;
      in
      groupPanelsByModule serialized;

    # Sorted list of panels
    stackpanel.panelsList =
      let
        enabledPanels = lib.filterAttrs (id: p: p.enabled) cfg.panels;
        serialized = lib.mapAttrs serializePanel enabledPanels;
        asList = lib.mapAttrsToList (id: panel: panel) serialized;
      in
      lib.sort (a: b: a.order < b.order) asList;

    # List of modules with panels
    stackpanel.panelModules =
      let
        enabledPanels = lib.filterAttrs (id: p: p.enabled) cfg.panels;
      in
      lib.unique (lib.mapAttrsToList (id: p: p.module) enabledPanels);
  };
}
