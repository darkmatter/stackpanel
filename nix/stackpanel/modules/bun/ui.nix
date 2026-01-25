# ==============================================================================
# ui.nix - Bun Module UI Panels
#
# Defines panels displayed in the Stackpanel UI for Bun apps.
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  sp = config.stackpanel;

  # Filter apps to only Bun-enabled apps
  bunApps = lib.filterAttrs (name: app: app.bun.enable or false) (sp.apps or {});
  hasBunApps = bunApps != {};
in
lib.mkIf (sp.enable && hasBunApps) {
  # ---------------------------------------------------------------------------
  # Status Panel - Overview of Bun environment
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
  # Apps Grid Panel - List of Bun applications
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-apps" = lib.mkIf (bunApps != { }) {
    module = meta.id;
    title = "Bun Applications";
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
        version = app.bun.version or "0.1.0";
        binaryName = app.bun.binaryName or name;
        mainPackage = app.bun.mainPackage or ".";
        buildPhase = app.bun.buildPhase or "bun run build";
        startScript = app.bun.startScript or "bun run start";
      };
    }) bunApps;
  };
}
