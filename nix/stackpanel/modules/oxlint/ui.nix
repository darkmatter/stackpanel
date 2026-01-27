# ==============================================================================
# ui.nix - OxLint UI Panel Definitions
#
# Defines the panels that appear in the Stackpanel UI for this module.
#
# The APP_CONFIG panel is auto-generated from the SpField definitions in
# oxlint-app.proto.nix. The status panel remains hand-crafted.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;

  # Import field definitions and panel generator
  oxlintSchema = import ./schema.nix { inherit lib; };
  panelsLib = import ../../lib/panels.nix { inherit lib; };

  # Get apps with oxlint enabled
  oxlintApps = lib.filterAttrs (_: app: app.linting.oxlint.enable or false) (cfg.apps or { });
  hasOxlintApps = oxlintApps != { };
in
lib.mkIf (cfg.enable && hasOxlintApps) {
  # ---------------------------------------------------------------------------
  # Status Panel - Overview of OxLint environment
  # (Hand-crafted: uses runtime data from app configs)
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # App Config Panel - Per-app OxLint configuration
  # (Auto-generated from oxlint-app.proto.nix SpField definitions)
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-app-config" = panelsLib.mkPanelFromSpFields {
    module = meta.id;
    title = "OxLint Configuration";
    icon = meta.icon;
    fields = oxlintSchema.fields;
    optionPrefix = "linting.oxlint";
    apps = oxlintApps;
    exclude = [ "enable" "turboTask" ];
    order = meta.priority + 2;
  };
}
