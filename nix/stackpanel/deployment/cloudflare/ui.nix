# ==============================================================================
# ui.nix - Cloudflare Deployment UI Panel Definitions
#
# Defines UI panels for Cloudflare Workers deployment configuration and status.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  deployCfg = cfg.deployment;

  # Import schema and panel generator
  cloudflareSchema = import ./schema.nix { inherit lib; };
  panelsLib = import ../../lib/panels.nix { inherit lib; };

  # Get apps configured for Cloudflare deployment
  cloudflareApps = lib.filterAttrs (
    _name: appCfg:
    (appCfg.deployment.enable or false)
    && (appCfg.deployment.provider or deployCfg.defaultProvider) == "cloudflare"
  ) (cfg.apps or { });

  hasCloudflareApps = cloudflareApps != { };

  # Build app status list
  appStatusList = lib.mapAttrsToList (
    name: appCfg:
    let
      cf = appCfg.deployment.cloudflare or { };
    in
    {
      name = name;
      workerName = cf.workerName or name;
      type = cf.type or "vite";
      route = cf.route or "-";
    }
  ) cloudflareApps;
in
lib.mkIf hasCloudflareApps {
  # -------------------------------------------------------------------------
  # Deployment Status Panel
  # -------------------------------------------------------------------------
  stackpanel.panels."cloudflare-status" = {
    module = meta.id;
    title = "Cloudflare Workers";
    description = "Edge deployments on Cloudflare Workers";
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    icon = "cloud";
    fields = [
      {
        name = "provider";
        type = "FIELD_TYPE_STRING";
        label = "Provider";
        value = "Cloudflare Workers";
      }
      {
        name = "accountId";
        type = "FIELD_TYPE_STRING";
        label = "Account ID";
        value =
          if deployCfg.cloudflare.accountId != null then
            lib.substring 0 8 deployCfg.cloudflare.accountId + "..."
          else
            "(from env)";
      }
      {
        name = "compatibilityDate";
        type = "FIELD_TYPE_STRING";
        label = "Compatibility Date";
        value = deployCfg.cloudflare.compatibilityDate or "2024-01-01";
      }
      {
        name = "appCount";
        type = "FIELD_TYPE_NUMBER";
        label = "Workers";
        value = toString (lib.length (lib.attrNames cloudflareApps));
      }
      {
        name = "apps";
        type = "FIELD_TYPE_JSON";
        label = "Configured Apps";
        value = builtins.toJSON appStatusList;
      }
    ];
  };

  # -------------------------------------------------------------------------
  # Deployment Configuration Form
  # -------------------------------------------------------------------------
  stackpanel.panels."cloudflare-config" = {
    module = meta.id;
    title = "Cloudflare Settings";
    description = "Configure Cloudflare Workers deployment settings";
    type = "PANEL_TYPE_FORM";
    order = meta.priority + 1;
    fields = [
      {
        name = "accountId";
        type = "FIELD_TYPE_STRING";
        label = "Account ID";
        description = "Cloudflare account ID (from dashboard)";
        value = deployCfg.cloudflare.accountId or "";
        configPath = "stackpanel.deployment.cloudflare.accountId";
      }
      {
        name = "compatibilityDate";
        type = "FIELD_TYPE_STRING";
        label = "Compatibility Date";
        description = "Workers API compatibility date";
        value = deployCfg.cloudflare.compatibilityDate or "2024-01-01";
        configPath = "stackpanel.deployment.cloudflare.compatibilityDate";
      }
      {
        name = "defaultRoute";
        type = "FIELD_TYPE_STRING";
        label = "Default Route";
        description = "Default custom domain pattern (e.g., *.example.com/*)";
        value = deployCfg.cloudflare.defaultRoute or "";
        configPath = "stackpanel.deployment.cloudflare.defaultRoute";
      }
    ];
  };

  # -------------------------------------------------------------------------
  # Per-App Workers Table
  # -------------------------------------------------------------------------
  stackpanel.panels."cloudflare-apps" = {
    module = meta.id;
    title = "Cloudflare Workers";
    description = "Apps deployed as Cloudflare Workers";
    type = "PANEL_TYPE_TABLE";
    order = meta.priority + 2;
    columns = [
      {
        key = "name";
        label = "App";
      }
      {
        key = "workerName";
        label = "Worker Name";
      }
      {
        key = "type";
        label = "Type";
      }
      {
        key = "route";
        label = "Route";
      }
    ];
    rows = appStatusList;
  };

  # -------------------------------------------------------------------------
  # Per-App Cloudflare Configuration Panel (for Deployment tab)
  # Auto-generated from schema.nix SpField definitions
  # -------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-app-config" = panelsLib.mkPanelFromSpFields {
    module = meta.id;
    title = "Cloudflare Configuration";
    icon = meta.ui.icon or "cloud";
    fields = cloudflareSchema.fields;
    optionPrefix = "deployment.cloudflare";
    apps = cloudflareApps;
    # Exclude complex types
    exclude = [
      "bindings"
      "secrets"
      "kvNamespaces"
      "d1Databases"
      "r2Buckets"
    ];
    order = meta.priority + 3;
  };
}
