# ==============================================================================
# ui.nix - Turbo UI Panel Definitions
#
# Defines the panels that appear in the Stackpanel UI for this module.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  tasksCfg = cfg.tasks or { };
  hasTasks = tasksCfg != { };
in
lib.mkIf (cfg.enable && hasTasks) {
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Turborepo";
    description = meta.description;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "tasks";
        type = "FIELD_TYPE_JSON";
        value = builtins.toJSON (lib.attrNames tasksCfg);
      }
      {
        name = "ui";
        type = "FIELD_TYPE_STRING";
        value = cfg.turbo.ui or "tui";
      }
    ];
  };
}
