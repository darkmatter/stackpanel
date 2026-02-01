# ==============================================================================
# ui.nix - Fly.io Deployment UI Panel Definitions
#
# Defines UI panels for Fly.io deployment configuration and status.
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
  flySchema = import ./schema.nix { inherit lib; };
  panelsLib = import ../../lib/panels.nix { inherit lib; };

  # Get apps configured for Fly.io deployment
  flyApps = lib.filterAttrs (
    _name: appCfg:
    (appCfg.deployment.enable or false)
    && (appCfg.deployment.provider or deployCfg.defaultProvider) == "fly"
  ) (cfg.apps or { });

  hasFlyApps = flyApps != { };

  # Build app status list
  appStatusList = lib.mapAttrsToList (
    name: appCfg:
    let
      fly = appCfg.deployment.fly or { };
    in
    {
      name = name;
      appName = fly.appName or name;
      region = fly.region or deployCfg.fly.defaultRegion or "iad";
      memory = fly.memory or "512mb";
    }
  ) flyApps;
in
lib.mkIf hasFlyApps {
  # -------------------------------------------------------------------------
  # Deployment Status Panel
  # -------------------------------------------------------------------------
  stackpanel.panels."fly-status" = {
    module = meta.id;
    title = "Fly.io Deployments";
    description = "Container-based deployments on Fly.io";
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    icon = "server";
    fields = [
      {
        name = "provider";
        type = "FIELD_TYPE_STRING";
        label = "Provider";
        value = "Fly.io";
      }
      {
        name = "organization";
        type = "FIELD_TYPE_STRING";
        label = "Organization";
        value = deployCfg.fly.organization or "(default)";
      }
      {
        name = "defaultRegion";
        type = "FIELD_TYPE_STRING";
        label = "Default Region";
        value = deployCfg.fly.defaultRegion or "iad";
      }
      {
        name = "appCount";
        type = "FIELD_TYPE_NUMBER";
        label = "Apps";
        value = toString (lib.length (lib.attrNames flyApps));
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
  stackpanel.panels."fly-config" = {
    module = meta.id;
    title = "Fly.io Settings";
    description = "Configure Fly.io deployment settings";
    type = "PANEL_TYPE_FORM";
    order = meta.priority + 1;
    fields = [
      {
        name = "organization";
        type = "FIELD_TYPE_STRING";
        label = "Organization";
        description = "Fly.io organization name";
        value = deployCfg.fly.organization or "";
        configPath = "stackpanel.deployment.fly.organization";
      }
      {
        name = "defaultRegion";
        type = "FIELD_TYPE_SELECT";
        label = "Default Region";
        description = "Default region for new deployments";
        value = deployCfg.fly.defaultRegion or "iad";
        configPath = "stackpanel.deployment.fly.defaultRegion";
        options = [
          {
            value = "iad";
            label = "Ashburn, Virginia (iad)";
          }
          {
            value = "lax";
            label = "Los Angeles (lax)";
          }
          {
            value = "ord";
            label = "Chicago (ord)";
          }
          {
            value = "sea";
            label = "Seattle (sea)";
          }
          {
            value = "ewr";
            label = "Secaucus, NJ (ewr)";
          }
          {
            value = "lhr";
            label = "London (lhr)";
          }
          {
            value = "ams";
            label = "Amsterdam (ams)";
          }
          {
            value = "fra";
            label = "Frankfurt (fra)";
          }
          {
            value = "nrt";
            label = "Tokyo (nrt)";
          }
          {
            value = "sin";
            label = "Singapore (sin)";
          }
          {
            value = "syd";
            label = "Sydney (syd)";
          }
        ];
      }
    ];
  };

  # -------------------------------------------------------------------------
  # Per-App Deployment Table
  # -------------------------------------------------------------------------
  stackpanel.panels."fly-apps" = {
    module = meta.id;
    title = "Fly.io Apps";
    description = "Apps deployed to Fly.io";
    type = "PANEL_TYPE_TABLE";
    order = meta.priority + 2;
    columns = [
      {
        key = "name";
        label = "App";
      }
      {
        key = "appName";
        label = "Fly App Name";
      }
      {
        key = "region";
        label = "Region";
      }
      {
        key = "memory";
        label = "Memory";
      }
    ];
    rows = appStatusList;
  };

  # -------------------------------------------------------------------------
  # Per-App Fly.io Configuration Panel (for Deployment tab)
  # Auto-generated from schema.nix SpField definitions
  # -------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-app-config" = panelsLib.mkPanelFromSpFields {
    module = meta.id;
    title = "Fly.io Configuration";
    icon = meta.icon;
    fields = flySchema.fields;
    optionPrefix = "deployment.fly";
    apps = flyApps;
    # Exclude env (hidden complex type)
    exclude = [ "env" ];
    order = meta.priority + 3;
  };
}
