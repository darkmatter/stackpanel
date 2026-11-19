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
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  containersCfg = cfg.containers or { };
  settingsCfg = containersCfg.settings or { };

  # Import field definitions and panel generator
  builderIds = builtins.attrNames cfg.containerBuilders;
  containerSchema = import ./schema.nix { inherit lib builderIds; };
  panelsLib = lib.stackpanel.panels;

  # Get apps with container.enable = true
  appsWithContainers = lib.filterAttrs (_: app: app.container.enable or false) (cfg.apps or { });
  hasContainerApps = appsWithContainers != { };

  # Get container images from config
  containerImages = containersCfg.images or { };
  imageCount = lib.length (lib.attrNames containerImages);
in
lib.mkIf (cfg.enable && cfg.modules.${meta.id}.enable) {
  # ---------------------------------------------------------------------------
  # Status Panel - Overview of container configuration
  # (Hand-crafted: uses runtime data from container settings)
  # ---------------------------------------------------------------------------
  stackpanel.panels."${meta.id}-status" = {
    module = meta.id;
    title = "Container Configuration";
    description = "Build and deploy OCI containers with Nix";
    inherit (meta) icon;
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
            label = "Image Builders";
            value = lib.concatStringsSep ", " builderIds;
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
        value = builtins.toJSON (
          lib.optionals (imageCount > 0) [
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
          ]
        );
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
    inherit (meta) icon;
    inherit (containerSchema) fields;
    optionPrefix = "container";
    apps = cfg.apps or { };
    # Complex option types aren't editable in this form.
    exclude = [
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
