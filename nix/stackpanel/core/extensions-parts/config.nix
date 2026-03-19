{
  lib,
  cfg,
}:
{
  # =========================================================================
  # Backward Compatibility: Alias extensions to modules
  # =========================================================================
  # Extensions defined in stackpanel.extensions are automatically converted
  # to stackpanel.modules entries. This allows existing code using extensions
  # to continue working while we migrate to the unified modules system.
  #
  # The conversion maps extension fields to module fields:
  #   extension.name        -> module.meta.name
  #   extension.description -> module.meta.description
  #   extension.enabled     -> module.enable
  #   extension.builtin     -> module.source.type = "builtin"
  #   extension.category    -> module.meta.category (converted)
  #   extension.features    -> module.features
  #   extension.panels      -> module.panels
  #   extension.apps        -> module.apps
  #   extension.priority    -> module.priority
  #   extension.tags        -> module.tags
  #   extension.dependencies -> module.requires
  # =========================================================================

  config = lib.mkIf cfg.enable {
    stackpanel.modules = lib.mapAttrs (
      name: ext:
      let
        # Convert extension category enum to module category enum
        convertCategory =
          cat:
          let
            mapping = {
              "EXTENSION_CATEGORY_UNSPECIFIED" = "unspecified";
              "EXTENSION_CATEGORY_INFRASTRUCTURE" = "infrastructure";
              "EXTENSION_CATEGORY_CI_CD" = "ci-cd";
              "EXTENSION_CATEGORY_DATABASE" = "database";
              "EXTENSION_CATEGORY_SECRETS" = "secrets";
              "EXTENSION_CATEGORY_DEPLOYMENT" = "deployment";
              "EXTENSION_CATEGORY_DEVELOPMENT" = "development";
              "EXTENSION_CATEGORY_MONITORING" = "monitoring";
              "EXTENSION_CATEGORY_INTEGRATION" = "integration";
            };
          in
          mapping.${cat} or "unspecified";

        # Convert extension source to module source
        convertSource =
          src:
          if ext.builtin or false then
            { type = "builtin"; }
          else if src.type == "EXTENSION_SOURCE_TYPE_LOCAL" then
            {
              type = "local";
              path = src.path;
            }
          else if src.type == "EXTENSION_SOURCE_TYPE_GITHUB" then
            {
              type = "flake-input";
              # GitHub repos would need to be added as flake inputs
              path = src.repo;
              ref = src.ref;
            }
          else
            { type = "builtin"; };
      in
      {
        enable = ext.enabled;
        meta = {
          name = ext.name;
          description = ext.description;
          category = convertCategory ext.category;
        };
        source = convertSource (ext.source or { });
        features = {
          files = ext.features.files or false;
          scripts = ext.features.scripts or false;
          tasks = ext.features.tasks or false;
          healthchecks = ext.features.checks or false;
          services = ext.features.services or false;
          secrets = ext.features.secrets or false;
          packages = ext.features.packages or false;
          appModule = false;
        };
        priority = ext.priority or 100;
        tags = ext.tags or [ ];
        requires = ext.dependencies or [ ];
        panels = ext.panels or [ ];
        apps = ext.apps or { };
      }
    ) cfg.extensions;
  };
}
