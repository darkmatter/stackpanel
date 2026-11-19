{ lib, config, ... }@args:
{
  id,
  label,
  icon,
  description,
  fields ? { },
  defaultTasks,
  deployMetadata ? (_: { }),
}:
let
  appFields = fields // {
    enable = lib.stackpanel.spField.bool {
      index = 1;
      inherit description;
      default = false;
      ui = null;
    };
  };
in
lib.stackpanel.mkModule {
  name = id;
  meta = {
    name = label;
    category = "framework";
    inherit icon description;
  };
  source.type = "builtin";
  defaultEnable = true;
  appOptions.framework.${id} = appFields;
  panels."${id}-app-config" =
    (lib.stackpanel.panels.mkPanelFromSpFields {
      module = id;
      title = "${label} Configuration";
      inherit icon;
      fields = appFields;
      optionPrefix = "framework.${id}";
      apps = lib.filterAttrs (_: app: app.framework.${id}.enable) config.stackpanel.apps;
    })
    // {
      slot = "app:framework";
    };
  config = _: {
    stackpanel.appFrameworks.${id} = {
      inherit
        label
        icon
        defaultTasks
        deployMetadata
        ;
      compatibleRuntimes = [
        "bun"
        "node"
      ];
    };
  };
} args
