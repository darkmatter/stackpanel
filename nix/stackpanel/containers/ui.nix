# ==============================================================================
# ui.nix - Containers UI Panel Definitions
#
# Defines the panels that appear in the Stackpanel UI for this module.
#
# The APP_CONFIG panel is auto-generated from the SpField definitions in
# schema.nix. The status panel is hand-crafted to show runtime information.
# ==============================================================================
{
  lib,
  config,
  pkgs ? null,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  containersCfg = cfg.containers or { };
  settingsCfg = containersCfg.settings or { };

  # Import field definitions and panel generator
  containerSchema = import ./schema.nix { inherit lib; };
  panelsLib = import ../lib/panels.nix { inherit lib; };

  # Get apps with container.enable = true
  appsWithContainers = lib.filterAttrs (_: app: app.container.enable or false) (cfg.apps or { });
  hasContainerApps = appsWithContainers != { };

  # Get container images from config
  containerImages = containersCfg.images or { };
  imageCount = lib.length (lib.attrNames containerImages);
in
lib.mkIf (cfg.enable && hasContainerApps) {
  # ---------------------------------------------------------------------------
  # Status Panel - Overview of container configuration
  # (Hand-crafted: uses runtime data from container settings)
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Container Configuration";
    description = "Build and deploy OCI containers with Nix";
    icon = meta.icon;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "metrics";
        type = "FIELD_TYPE_STRING";
        value = builtins.toJSON [
          {
            label = "Backend";
            value = settingsCfg.backend or "nix2container";
            status = "ok";
          }
          {
            label = "Default Registry";
            value = settingsCfg.defaultRegistry or "docker-daemon:";
            status = "ok";
          }
          {
            label = "Container Apps";
            value = toString (lib.length (lib.attrNames appsWithContainers));
            status = if hasContainerApps then "ok" else "warn";
          }
          {
            label = "Images";
            value = toString imageCount;
            status = if imageCount > 0 then "ok" else "warn";
          }
        ];
      }
      {
        name = "commands";
        type = "FIELD_TYPE_JSON";
        value = builtins.toJSON [
          {
            name = "container-build";
            description = "Build a container image";
          }
          {
            name = "container-copy";
            description = "Build + push to registry";
          }
          {
            name = "container-run";
            description = "Build + run locally";
          }
          {
            name = "container-info";
            description = "Show container configuration";
          }
        ];
      }
    ];
  };

  # ---------------------------------------------------------------------------
  # App Config Panel - Per-app container configuration
  # (Auto-generated from schema.nix SpField definitions)
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-app-config" = panelsLib.mkPanelFromSpFields {
    module = meta.id;
    title = "Container Settings";
    icon = meta.icon;
    fields = containerSchema.fields;
    optionPrefix = "container";
    apps = appsWithContainers;
    # Exclude enable (hidden) and complex type fields not suitable for form editing
    exclude = [
      "enable"
      "startupCommand"
      "copyToRoot"
      "defaultCopyArgs"
      "env"
    ];
    order = meta.priority + 2;
    # Module documentation from schema
    readme = containerSchema.readme or null;
  };
}
