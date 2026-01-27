# ==============================================================================
# ui.nix - Go UI Panel Definitions
#
# Defines the panels that appear in the Stackpanel UI for this module.
#
# The APP_CONFIG panel is auto-generated from the SpField definitions in
# go-app.proto.nix. No manual field listing needed - the schema is the
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
  goSchema = import ./schema.nix { inherit lib; };
  panelsLib = import ../../lib/panels.nix { inherit lib; };

  # Filter apps to only Go apps
  goApps = lib.filterAttrs (name: app: app.go.enable or false) (cfg.apps or { });
  hasGoApps = goApps != { };
in
lib.mkIf (cfg.enable && hasGoApps) {
  # ---------------------------------------------------------------------------
  # Status Panel - Overview of Go environment
  # (Hand-crafted: uses runtime data like pkgs.go.version)
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Go Environment";
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
            label = "Go Version";
            value = pkgs.go.version;
            status = "ok";
          }
          {
            label = "Apps";
            value = toString (lib.length (lib.attrNames goApps));
            status = "ok";
          }
        ];
      }
    ];
  };

  # ---------------------------------------------------------------------------
  # App Config Panel - Per-app Go configuration
  # (Auto-generated from go-app.proto.nix SpField definitions)
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-app-config" = panelsLib.mkPanelFromSpFields {
    module = meta.id;
    title = "Go Configuration";
    icon = meta.icon;
    fields = goSchema.fields;
    optionPrefix = "go";
    apps = goApps;
    exclude = [ "enable" ];
    order = meta.priority + 2;
  };
}
