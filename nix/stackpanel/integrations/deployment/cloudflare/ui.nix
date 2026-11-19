# ==============================================================================
# ui.nix - Cloudflare Deployment UI Panel Definitions
#
# Defines UI panels for Cloudflare Workers deployment configuration and status.
# ==============================================================================
{
  lib,
  cfg,
  meta,
  cloudflareApps,
  cloudflareSchema,
}:
let
  deployCfg = cfg.deployment;

  # Build app status list
  appStatusList = lib.mapAttrsToList (
    name: appCfg:
    let
      cf = appCfg.deployment.cloudflare or { };
    in
    {
      inherit name;
      workerName = cf.workerName or name;
      type = lib.defaultTo "-" cfg.appsComputed.${name}.framework;
      route = if cf.route or null != null then cf.route else "-";
    }
  ) cloudflareApps;
in
{
  # -------------------------------------------------------------------------
  # Deployment Status Panel
  # -------------------------------------------------------------------------
  cloudflare-status = {
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
        value = deployCfg.cloudflare.compatibilityDate or "2025-04-01";
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
  cloudflare-config = {
    module = meta.id;
    title = "Cloudflare Settings";
    description = "Configure Cloudflare Workers deployment settings";
    type = "PANEL_TYPE_FORM";
    slot = "configuration";
    order = meta.priority + 1;
    fields = [
      {
        name = "accountId";
        type = "FIELD_TYPE_STRING";
        label = "Account ID";
        description = "Cloudflare account ID (from dashboard)";
        value = deployCfg.cloudflare.accountId or "";
        configPath = "deployment.cloudflare.accountId";
      }
      {
        name = "compatibilityDate";
        type = "FIELD_TYPE_STRING";
        label = "Compatibility Date";
        description = "Workers API compatibility date";
        value = deployCfg.cloudflare.compatibilityDate or "2025-04-01";
        configPath = "deployment.cloudflare.compatibilityDate";
      }
      {
        name = "defaultRoute";
        type = "FIELD_TYPE_STRING";
        label = "Default Route";
        description = "Default custom domain pattern (e.g., *.example.com/*)";
        value = deployCfg.cloudflare.defaultRoute or "";
        configPath = "deployment.cloudflare.defaultRoute";
      }
    ];
  };

  # -------------------------------------------------------------------------
  # Per-App Workers Table
  # -------------------------------------------------------------------------
  cloudflare-apps = {
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
  "${meta.id}-app-config" = lib.stackpanel.panels.mkPanelFromSpFields {
    module = meta.id;
    slot = "app:deployment";
    title = "Cloudflare Configuration";
    icon = meta.ui.icon or "cloud";
    inherit (cloudflareSchema) fields;
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
