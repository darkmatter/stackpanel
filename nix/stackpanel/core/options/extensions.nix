# ==============================================================================
# extensions.nix
#
# Extension configuration options for Stackpanel UI panels.
#
# Extensions can define UI panels that are rendered in the web interface.
# Each panel has a type (determines which component to render) and fields
# (typed configuration that maps to component props).
#
# Modules can register extensions with panels and per-app computed data:
#
#   stackpanel.extensions.go = {
#     name = "Go";
#     enabled = true;
#     panels = [
#       {
#         id = "go-apps";
#         title = "Go Applications";
#         type = "PANEL_TYPE_APPS_GRID";
#         order = 1;
#         fields = [
#           { name = "filter"; type = "FIELD_TYPE_APP_FILTER"; value = "go.enable"; }
#         ];
#       }
#     ];
#     apps = {
#       my-go-app = {
#         enabled = true;
#         config = { path = "apps/my-go-app"; version = "1.0.0"; };
#       };
#     };
#   };
#
# The extensions are exposed via nix eval for the agent/web UI to consume.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;
  db = import ../../db { inherit lib; };

  # Panel field type (derived from proto)
  panelFieldType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Field name (maps to component prop)";
      };
      type = lib.mkOption {
        type = lib.types.enum [
          "FIELD_TYPE_UNSPECIFIED"
          "FIELD_TYPE_STRING"
          "FIELD_TYPE_NUMBER"
          "FIELD_TYPE_BOOLEAN"
          "FIELD_TYPE_SELECT"
          "FIELD_TYPE_MULTISELECT"
          "FIELD_TYPE_APP_FILTER"
          "FIELD_TYPE_COLUMNS"
        ];
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

  # Extension panel type (derived from proto)
  extensionPanelType = lib.types.submodule {
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
        type = lib.types.enum [
          "PANEL_TYPE_UNSPECIFIED"
          "PANEL_TYPE_APPS_GRID"
          "PANEL_TYPE_STATUS"
          "PANEL_TYPE_FORM"
        ];
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

  # Per-app extension data type
  extensionAppDataType = lib.types.submodule {
    options = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether extension is enabled for this app";
      };
      config = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Extension config for this app (string key-value pairs)";
      };
    };
  };

  # Extension type (derived from proto, with panels and apps fields)
  extensionType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name of the extension";
      };
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this extension is enabled";
      };
      priority = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Load order priority (lower = earlier)";
      };
      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Tags for categorizing/filtering extensions";
      };
      panels = lib.mkOption {
        type = lib.types.listOf extensionPanelType;
        default = [ ];
        description = "UI panels provided by this extension";
      };
      apps = lib.mkOption {
        type = lib.types.attrsOf extensionAppDataType;
        default = { };
        description = "Per-app extension data (app name -> extension data)";
      };
    };
  };

  # Computed extensions for serialization (only enabled extensions)
  enabledExtensions = lib.filterAttrs (_: ext: ext.enabled) cfg.extensions;
in
{
  options.stackpanel.extensions = lib.mkOption {
    type = lib.types.attrsOf extensionType;
    default = { };
    description = ''
      Extensions that provide UI panels for the web interface.

      Each extension can define:
        - `name`: Display name
        - `enabled`: Whether the extension is active
        - `panels`: List of UI panels to render
        - `apps`: Per-app computed data

      Modules register extensions to expose their features in the UI.
    '';
    example = lib.literalExpression ''
      {
        go = {
          name = "Go";
          enabled = true;
          panels = [
            {
              id = "go-apps";
              title = "Go Applications";
              type = "PANEL_TYPE_APPS_GRID";
              fields = [
                { name = "columns"; type = "FIELD_TYPE_COLUMNS"; value = "[\"name\",\"path\"]"; }
              ];
            }
          ];
          apps = {
            my-app = {
              enabled = true;
              config = { path = "apps/my-app"; version = "1.0.0"; };
            };
          };
        };
      }
    '';
  };

  # Expose computed/serializable extensions for nix eval
  options.stackpanel.extensionsComputed = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = enabledExtensions;
    description = "Computed extension configurations (only enabled extensions)";
  };
}
