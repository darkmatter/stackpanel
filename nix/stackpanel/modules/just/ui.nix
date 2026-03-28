# ==============================================================================
# ui.nix - Just Module UI Panel
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel.just;
  enabledModules = lib.filterAttrs (_: m: m.enable) cfg.modules;
in
lib.mkIf (config.stackpanel.modules.${meta.id}.enable or false) {
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "${meta.name} Status";
    description = meta.description;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "enabled";
        type = "FIELD_TYPE_BOOLEAN";
        value = "true";
      }
      {
        name = "modules";
        type = "FIELD_TYPE_JSON";
        value = builtins.toJSON (lib.attrNames enabledModules);
      }
    ];
  };
}
