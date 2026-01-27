# ==============================================================================
# ui.nix - Bun UI Panel Definitions
#
# Defines the panels that appear in the Stackpanel UI for this module.
#
# The APP_CONFIG panel is auto-generated from the SpField definitions in
# bun-app.proto.nix. No manual field listing needed - the schema is the
# single source of truth for both Nix options and UI panels.
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;

  # Import field definitions and panel generator
  bunSchema = import ./schema.nix { inherit lib; };
  panelsLib = import ../../lib/panels.nix { inherit lib; };

  # Filter apps to only Bun-enabled apps
  bunApps = lib.filterAttrs (name: app: app.bun.enable or false) (cfg.apps or {});
  hasBunApps = bunApps != {};
in
lib.mkIf (cfg.enable && hasBunApps) {
  # ---------------------------------------------------------------------------
  # Status Panel - Overview of Bun environment
  # (Hand-crafted: uses runtime data like pkgs.bun.version)
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Bun Environment";
    description = meta.description;
    icon = meta.icon;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "metrics";
        type = "FIELD_TYPE_STRING";
        value = builtins.toJSON [
          {
            label = "Bun Version";
            value = pkgs.bun.version;
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
  # (Auto-generated from bun-app.proto.nix SpField definitions)
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-app-config" = panelsLib.mkPanelFromSpFields {
    module = meta.id;
    title = "Bun Configuration";
    icon = meta.icon;
    fields = bunSchema.fields;
    optionPrefix = "bun";
    apps = bunApps;
    exclude = [ "enable" ];
    order = meta.priority + 2;
  };
}
