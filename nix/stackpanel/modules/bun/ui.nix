# ==============================================================================
# ui.nix - Bun UI Panel Definitions
#
# Defines the panels that appear in the Stackpanel UI for this module.
#
# The app:runtime panel is generated from the same fields as the Nix options.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;

  bunSchema = import ./schema.nix { inherit lib; };

  # Filter apps to only Bun-enabled apps
  bunApps = lib.filterAttrs (_name: app: app.bun.enable or false) (cfg.apps or { });
  hasBunApps = bunApps != { };
  bunPkg = cfg.bun.package;
in
lib.mkIf (cfg.enable && cfg.modules.${meta.id}.enable && hasBunApps) {
  # ---------------------------------------------------------------------------
  # Status Panel - Overview of Bun environment
  # (Hand-crafted: uses the configured Bun package version)
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Bun Environment";
    inherit (meta) description;
    inherit (meta) icon;
    type = "PANEL_TYPE_STATUS";
    slot = "overview";
    order = meta.priority;
    fields = [
      {
        name = "metrics";
        type = "FIELD_TYPE_STRING";
        value = builtins.toJSON [
          {
            label = "Bun Version";
            value = bunPkg.version;
            status = "ok";
          }
          {
            label = "Apps";
            value = toString (lib.length (lib.attrNames bunApps));
            status = if bunApps != { } then "ok" else "warning";
          }
        ];
      }
    ];
  };

  # ---------------------------------------------------------------------------
  # App Config Panel - Per-app Bun configuration
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-app-config" = lib.stackpanel.panels.mkPanelFromSpFields {
    slot = "app:runtime";
    module = meta.id;
    title = "Bun Configuration";
    inherit (meta) icon;
    inherit (bunSchema) fields;
    optionPrefix = "bun";
    apps = bunApps;
    exclude = [
      "enable"
      "generateFiles"
    ];
    order = meta.priority + 2;
  };
}
