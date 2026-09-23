# ==============================================================================
# ui.nix - Prelude module UI panel
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel.prelude;
in
lib.mkIf cfg.enable {
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "${meta.name} Status";
    inherit (meta) description;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "enable";
        type = "FIELD_TYPE_STRING";
        label = "Enabled";
        value = "true";
      }
      {
        name = "theme";
        type = "FIELD_TYPE_STRING";
        label = "Theme";
        value = if cfg.theme != null then cfg.theme else "minted (default)";
      }
      {
        name = "menu";
        type = "FIELD_TYPE_STRING";
        label = "Menu";
        value = if cfg.menu.enable then "enabled" else "disabled";
      }
      {
        name = "docs";
        type = "FIELD_TYPE_STRING";
        label = "Docs";
        value = if cfg.docs.enable then "enabled" else "disabled";
      }
      {
        name = "prompt";
        type = "FIELD_TYPE_STRING";
        label = "Prompt";
        value = if cfg.prompt.enable then "enabled" else "disabled";
      }
    ];
  };
}
