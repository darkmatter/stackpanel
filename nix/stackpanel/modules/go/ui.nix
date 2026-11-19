# ==============================================================================
# ui.nix - Go UI Panel Definitions
#
# Defines the panels that appear in the Stackpanel UI for this module.
#
# The app:runtime panel is generated from the same fields as the Nix options.
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
  goSchema = import ./schema.nix { inherit lib; };

  # Filter apps to only Go apps
  goApps = lib.filterAttrs (_name: app: app.go.enable or false) (cfg.apps or { });
  hasGoApps = goApps != { };
in
lib.mkIf (cfg.enable && cfg.modules.${meta.id}.enable && hasGoApps) {
  # ---------------------------------------------------------------------------
  # Native overview of the configured Go environment
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Go Environment";
    inherit (meta) description;
    inherit (meta) icon;
    slot = "overview";
    order = meta.priority;
    spec.widgets = {
      summary.stack = {
        direction = "horizontal";
        children = [
          "version"
          "apps"
        ];
      };
      version.metric = {
        label = "Go Version";
        value = pkgs.go.version;
      };
      apps.metric = {
        label = "Apps";
        value = builtins.length (builtins.attrNames goApps);
      };
    };
  };

  # ---------------------------------------------------------------------------
  # App Config Panel - Per-app Go configuration
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-app-config" = lib.stackpanel.panels.mkPanelFromSpFields {
    slot = "app:runtime";
    module = meta.id;
    title = "Go Configuration";
    inherit (meta) icon;
    inherit (goSchema) fields;
    optionPrefix = "go";
    apps = goApps;
    exclude = [ "enable" ];
    order = meta.priority + 2;
  };
}
