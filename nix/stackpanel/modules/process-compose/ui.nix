# ==============================================================================
# ui.nix - Process Compose UI Panel Definitions
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
  pcCfg = cfg.process-compose or { };
  preludeTheme = cfg.prelude.theme or null;
in
lib.mkIf (cfg.enable && (pcCfg.enable or false)) {
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Process Compose";
    inherit (meta) description;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "command";
        type = "FIELD_TYPE_STRING";
        value = pcCfg.commandName or "dev";
      }
      {
        name = "processes";
        type = "FIELD_TYPE_JSON";
        value = builtins.toJSON (lib.attrNames (pcCfg.processes or { }));
      }
      {
        name = "formatWatcher";
        type = "FIELD_TYPE_BOOLEAN";
        value = if (pcCfg.formatWatcher.enable or true) then "true" else "false";
      }
      {
        name = "theme";
        type = "FIELD_TYPE_STRING";
        value =
          if pcCfg.theme != null then
            pcCfg.theme
          else if preludeTheme != null then
            preludeTheme
          else
            "minted";
      }
    ];
  };
}
