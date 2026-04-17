# ==============================================================================
# ui.nix - UI Panel Definitions
#
# This file defines the UI panels and fields that appear in the Stackpanel UI.
# It's evaluated lazily - only when the UI needs to display this module's panels.
#
# Panel Types:
# - PANEL_TYPE_STATUS: Show status/health information
# - PANEL_TYPE_FORM: Editable configuration form
# - PANEL_TYPE_TABLE: Tabular data display
# - PANEL_TYPE_APPS_GRID: Grid of app cards
# - PANEL_TYPE_CUSTOM: Custom rendering (provide component name)
#
# Field Types:
# - FIELD_TYPE_STRING: Text input
# - FIELD_TYPE_NUMBER: Numeric input
# - FIELD_TYPE_BOOLEAN: Toggle/checkbox
# - FIELD_TYPE_SELECT: Single-select dropdown
# - FIELD_TYPE_MULTISELECT: Multi-select dropdown
# - FIELD_TYPE_APP_FILTER: App selector
# - FIELD_TYPE_COLUMNS: Multi-column layout
# - FIELD_TYPE_JSON: Raw JSON data
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel.modules.${meta.id};
in
lib.mkIf cfg.enable {
  # Register panel(s) for this module
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "${meta.name} Status";
    description = meta.description;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      # Example: Show enabled status
      {
        name = "enabled";
        type = "FIELD_TYPE_BOOLEAN";
        value = "true";
      }
      # Example: Show version
      # {
      #   name = "version";
      #   type = "FIELD_TYPE_STRING";
      #   value = meta.version;
      # }
      # Example: Show configured apps (if appModule is used)
      # {
      #   name = "apps";
      #   type = "FIELD_TYPE_JSON";
      #   value = builtins.toJSON (lib.attrNames enabledApps);
      # }
    ];
  };

  # Example: Configuration form panel
  # stackpanel.panels."${meta.id}-config" = {
  #   module = meta.id;
  #   title = "${meta.name} Configuration";
  #   type = "PANEL_TYPE_FORM";
  #   order = meta.priority + 1;
  #   fields = [
  #     {
  #       name = "option1";
  #       type = "FIELD_TYPE_STRING";
  #       label = "Option 1";
  #       value = cfg.option1 or "";
  #     }
  #     {
  #       name = "option2";
  #       type = "FIELD_TYPE_BOOLEAN";
  #       label = "Enable Feature";
  #       value = if cfg.enableFeature then "true" else "false";
  #     }
  #   ];
  # };
}
