# ==============================================================================
# ui.nix - App Commands UI Panel Definitions
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

  # Filter apps that have commands defined
  appsWithCommands = lib.filterAttrs (
    _: app:
    let
      cmds = app.commands or null;
    in
    cmds != null && cmds != { }
  ) (cfg.apps or { });

  hasAppsWithCommands = appsWithCommands != { };
in
lib.mkIf (cfg.enable && hasAppsWithCommands) {
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "App Commands";
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
            path = appCfg.path or "apps/${name}";
            commands = lib.attrNames (
              lib.filterAttrs (_: cmd: cmd != null && (cmd.enable or true)) (appCfg.commands or { })
            );
          }) appsWithCommands
        );
      }
    ];
  };
}
