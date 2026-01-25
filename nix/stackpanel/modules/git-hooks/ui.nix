# ==============================================================================
# ui.nix - Git Hooks UI Panel Definitions
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
  gitHooksCfg = cfg.git-hooks or { enable = false; };
in
lib.mkIf (cfg.enable && (gitHooksCfg.enable or false)) {
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Git Hooks";
    description = meta.description;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "enabled";
        type = "FIELD_TYPE_BOOLEAN";
        value = if gitHooksCfg.enable or false then "true" else "false";
      }
      {
        name = "hooks";
        type = "FIELD_TYPE_JSON";
        value = builtins.toJSON {
          pre-commit = lib.attrNames (gitHooksCfg.hooks.pre-commit or { });
          pre-push = lib.attrNames (gitHooksCfg.hooks.pre-push or { });
        };
      }
    ];
  };
}
