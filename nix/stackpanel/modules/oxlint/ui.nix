# ==============================================================================
# ui.nix - OxLint UI Panel Definitions
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

  # Get apps with oxlint enabled
  oxlintApps = lib.filterAttrs (_: app: app.linting.oxlint.enable or false) (cfg.apps or { });
  hasOxlintApps = oxlintApps != { };
in
lib.mkIf (cfg.enable && hasOxlintApps) {
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "OxLint Status";
    description = "JavaScript/TypeScript linting with OxLint";
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "apps";
        type = "FIELD_TYPE_JSON";
        value = builtins.toJSON (
          lib.mapAttrsToList (name: appCfg: {
            name = name;
            path = appCfg.path or "apps/${name}";
            plugins = appCfg.linting.oxlint.plugins;
            gitHook = appCfg.linting.oxlint.gitHook;
            turboTask = appCfg.linting.oxlint.turboTask;
          }) oxlintApps
        );
      }
      {
        name = "commands";
        type = "FIELD_TYPE_JSON";
        value = builtins.toJSON [
          {
            name = "lint";
            description = "Run OxLint on all apps";
          }
          {
            name = "lint-fix";
            description = "Run OxLint --fix on all apps";
          }
        ];
      }
    ];
  };
}
