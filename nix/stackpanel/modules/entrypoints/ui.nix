# ==============================================================================
# ui.nix - Entrypoints UI Panel Definitions
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

  # Filter apps with entrypoints
  appsWithPaths = lib.filterAttrs (
    name: app: (app.path or null) != null
  ) (cfg.apps or { });
  
  appsWithEntrypoints = lib.filterAttrs (
    name: app: (app.entrypoint.enable or true)
  ) appsWithPaths;

  hasApps = appsWithEntrypoints != { };
in
lib.mkIf (cfg.enable && hasApps) {
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Entrypoints";
    description = meta.description;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "apps";
        type = "FIELD_TYPE_JSON";
        value = builtins.toJSON (
          lib.mapAttrsToList (name: appCfg: {
            name = name;
            path = "packages/scripts/entrypoints/${name}.sh";
            enabled = appCfg.entrypoint.enable or true;
          }) appsWithEntrypoints
        );
      }
    ];
  };
}
