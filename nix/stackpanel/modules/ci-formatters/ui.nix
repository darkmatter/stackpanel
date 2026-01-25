# ==============================================================================
# ui.nix - CI Formatters UI Panel Definitions
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
  appsComputed = cfg.appsComputed or { };

  formatters = lib.flatten (
    lib.mapAttrsToList (_: app: app.wrappedTooling.formatters or [ ]) appsComputed
  );
in
lib.mkIf (cfg.enable && formatters != [ ]) {
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "CI Formatters";
    description = meta.description;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "formatters";
        type = "FIELD_TYPE_JSON";
        value = builtins.toJSON (map (f: f.name or "unknown") formatters);
      }
    ];
  };
}
