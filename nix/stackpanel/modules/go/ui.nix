# ==============================================================================
# ui.nix - Go UI Panel Definitions
#
# Defines the panels that appear in the Stackpanel UI for this module.
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

  # Filter apps to only Go apps
  goApps = lib.filterAttrs (name: app: app.go.enable or false) (cfg.apps or { });
  hasGoApps = goApps != { };
in
lib.mkIf (cfg.enable && hasGoApps) {
  # ---------------------------------------------------------------------------
  # Status Panel - Overview of Go environment
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
  # Apps Grid Panel - List of Go applications
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-apps" = {
    module = meta.id;
    title = "Go Applications";
    icon = "boxes";
    type = "PANEL_TYPE_APPS_GRID";
    order = meta.priority + 1;
    fields = [
      {
        name = "columns";
        type = "FIELD_TYPE_COLUMNS";
        value = builtins.toJSON [
          "name"
          "path"
          "version"
          "port"
        ];
      }
    ];
    # Per-app computed data
    apps = lib.mapAttrs (name: app: {
      enabled = true;
      config = {
        path = app.path or "";
        version = app.go.version or "0.1.0";
        binaryName = app.go.binaryName or name;
        mainPackage = app.go.mainPackage or ".";
      };
    }) goApps;
  };
}
