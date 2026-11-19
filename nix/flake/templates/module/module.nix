{ lib, config, ... }@args:
lib.stackpanel.mkModule {
  name = "example";
  meta.name = "Example";

  ui.widgets.appCount.metric = {
    label = "Configured apps";
    value = builtins.length (builtins.attrNames config.stackpanel.apps);
  };
} args
