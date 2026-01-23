# ==============================================================================
# extensions.nix
#
# Extension configuration options for Stackpanel.
#
# Extensions are feature modules that compose core stackpanel features:
#   - File generation (stackpanel.files.entries)
#   - Script generation (stackpanel.scripts)
#   - Tasks (stackpanel.tasks)
#   - Variables/secrets (stackpanel.secrets)
#   - Shell hooks (stackpanel.devshell.hooks)
#   - UI panels (stackpanel.extensions.*.panels)
#
# Extensions can be:
#   - Builtin: Shipped with stackpanel (e.g., sst, ci, docker)
#   - Local: Defined in the project
#   - External: Installed from GitHub or other sources
#
# Modules can register extensions with panels and per-app computed data:
#
#   stackpanel.extensions.sst = {
#     name = "SST Infrastructure";
#     enabled = true;
#     builtin = true;
#     features = { files = true; scripts = true; secrets = true; };
#     panels = [
#       {
#         id = "sst-status";
#         title = "SST Infrastructure";
#         type = "PANEL_TYPE_STATUS";
#         order = 1;
#         fields = [
#           { name = "metrics"; type = "FIELD_TYPE_STRING"; value = "..."; }
#         ];
#       }
#     ];
#   };
#
# The extensions are exposed via nix eval for the agent/web UI to consume.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;

  # Import extension source discovery library
  extensionSrc = import ../../lib/extension-src.nix { inherit lib; };

  # ============================================================================
  # Type Definitions (matching extensions.proto.nix)
  # ============================================================================

  # Extension source type
  sourceTypeEnum = lib.types.enum [
    "EXTENSION_SOURCE_TYPE_UNSPECIFIED"
    "EXTENSION_SOURCE_TYPE_BUILTIN"
    "EXTENSION_SOURCE_TYPE_LOCAL"
    "EXTENSION_SOURCE_TYPE_GITHUB"
    "EXTENSION_SOURCE_TYPE_NPM"
    "EXTENSION_SOURCE_TYPE_URL"
  ];

  # Extension category for UI grouping
  categoryEnum = lib.types.enum [
    "EXTENSION_CATEGORY_UNSPECIFIED"
    "EXTENSION_CATEGORY_INFRASTRUCTURE"
    "EXTENSION_CATEGORY_CI_CD"
    "EXTENSION_CATEGORY_DATABASE"
    "EXTENSION_CATEGORY_SECRETS"
    "EXTENSION_CATEGORY_DEPLOYMENT"
    "EXTENSION_CATEGORY_DEVELOPMENT"
    "EXTENSION_CATEGORY_MONITORING"
    "EXTENSION_CATEGORY_INTEGRATION"
  ];

  # Panel types for UI rendering
  panelTypeEnum = lib.types.enum [
    "PANEL_TYPE_UNSPECIFIED"
    "PANEL_TYPE_STATUS"
    "PANEL_TYPE_APPS_GRID"
    "PANEL_TYPE_FORM"
    "PANEL_TYPE_TABLE"
    "PANEL_TYPE_CUSTOM"
  ];

  # Field types for panel configuration
  fieldTypeEnum = lib.types.enum [
    "FIELD_TYPE_UNSPECIFIED"
    "FIELD_TYPE_STRING"
    "FIELD_TYPE_NUMBER"
    "FIELD_TYPE_BOOLEAN"
    "FIELD_TYPE_SELECT"
    "FIELD_TYPE_MULTISELECT"
    "FIELD_TYPE_APP_FILTER"
    "FIELD_TYPE_COLUMNS"
    "FIELD_TYPE_JSON"
  ];

  # ============================================================================
  # Submodule Types
  # ============================================================================

  # Extension source configuration
  extensionSourceType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = sourceTypeEnum;
        default = "EXTENSION_SOURCE_TYPE_BUILTIN";
        description = "Source type for the extension";
      };
      repo = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "GitHub repository (owner/repo) for github source type";
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "NPM package name for npm source type";
      };
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Local path for local source type";
      };
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "URL for url source type";
      };
      ref = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Git ref (branch, tag, commit) for github source type";
      };
      module-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the Nix module within the source";
      };
    };
  };

  # Extension features - which core stackpanel features this extension uses
  extensionFeaturesType = lib.types.submodule {
    options = {
      files = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension generates files via stackpanel.files";
      };
      scripts = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension provides shell scripts/commands";
      };
      tasks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension defines tasks";
      };
      secrets = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension manages secrets/variables";
      };
      shell-hooks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension adds shell hooks";
      };
      packages = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension adds devshell packages";
      };
      services = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension configures services/processes";
      };
      checks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension defines checks/validations";
      };
    };
  };

  # Panel field type
  panelFieldType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Field name (maps to component prop)";
      };
      type = lib.mkOption {
        type = fieldTypeEnum;
        default = "FIELD_TYPE_STRING";
        description = "Field type";
      };
      value = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Field value (JSON-encoded for complex types)";
      };
      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Options for select fields";
      };
    };
  };

  # Extension panel type
  extensionPanelType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Unique panel identifier";
      };
      title = lib.mkOption {
        type = lib.types.str;
        description = "Display title";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Panel description";
      };
      type = lib.mkOption {
        type = panelTypeEnum;
        default = "PANEL_TYPE_STATUS";
        description = "Panel type (determines which component to render)";
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Display order (lower = first)";
      };
      fields = lib.mkOption {
        type = lib.types.listOf panelFieldType;
        default = [ ];
        description = "Panel configuration fields";
      };
    };
  };

  # Per-app extension data type
  extensionAppDataType = lib.types.submodule {
    options = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether extension is enabled for this app";
      };
      config = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Extension config for this app (string key-value pairs)";
      };
    };
  };

  # Main extension type
  extensionType = lib.types.submodule {
    options = {
      # Identity
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name of the extension";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Human-readable description of what the extension does";
      };

      # Status
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this extension is enabled";
      };
      builtin = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this is a built-in extension shipped with stackpanel";
      };

      # Source information
      source = lib.mkOption {
        type = extensionSourceType;
        default = { };
        description = "Extension source configuration";
      };
      version = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Version constraint (e.g., '^1.0.0', '~2.3', 'latest')";
      };

      # Organization
      category = lib.mkOption {
        type = categoryEnum;
        default = "EXTENSION_CATEGORY_UNSPECIFIED";
        description = "Category for grouping in UI";
      };
      priority = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Load order priority (lower = earlier)";
      };
      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Tags for categorizing/filtering extensions";
      };
      dependencies = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Other extensions this depends on";
      };

      # Core feature flags
      features = lib.mkOption {
        type = extensionFeaturesType;
        default = { };
        description = "Which core stackpanel features this extension configures";
      };

      # UI configuration
      panels = lib.mkOption {
        type = lib.types.listOf extensionPanelType;
        default = [ ];
        description = "UI panels provided by this extension";
      };
      apps = lib.mkOption {
        type = lib.types.attrsOf extensionAppDataType;
        default = { };
        description = "Per-app extension data (app name -> extension data)";
      };

      # Source directory for file-based resources
      srcDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to extension's src/ directory for scripts, checks, and files.

          When specified, the extension system will auto-discover resources:
            - src/scripts/*.sh -> stackpanel.scripts.<extName>:<scriptName>
            - src/checks/*.sh -> stackpanel.healthchecks.<extName>:<checkName>
            - src/files/* -> available for stackpanel.files.entries

          Resources are automatically namespaced with the extension name.
          Explicit Nix definitions take priority over auto-discovered resources.

          Example:
            srcDir = ./src;  # Relative to extension module
        '';
        example = "./src";
      };
    };
  };

  # ============================================================================
  # Computed Values
  # ============================================================================

  # Filter to only enabled extensions
  enabledExtensions = lib.filterAttrs (_: ext: ext.enabled) cfg.extensions;

  # Get builtin extensions
  builtinExtensions = lib.filterAttrs (_: ext: ext.builtin) cfg.extensions;

  # Get external/local extensions
  externalExtensions = lib.filterAttrs (_: ext: !ext.builtin) cfg.extensions;

  # ============================================================================
  # Auto-Discovery from srcDir
  # ============================================================================

  # Discover scripts from all enabled extensions with srcDir
  discoveredScripts = lib.foldl' (
    acc: extName:
    let
      ext = cfg.extensions.${extName};
    in
    if ext.enabled && ext.srcDir or null != null then
      acc // (extensionSrc.discoverScripts extName ext.srcDir)
    else
      acc
  ) { } (lib.attrNames cfg.extensions);

  # Discover healthchecks from all enabled extensions with srcDir
  discoveredHealthchecks = lib.foldl' (
    acc: extName:
    let
      ext = cfg.extensions.${extName};
    in
    if ext.enabled && ext.srcDir or null != null then
      acc // (extensionSrc.discoverHealthchecks extName ext.srcDir)
    else
      acc
  ) { } (lib.attrNames cfg.extensions);

in
{
  # ============================================================================
  # Options
  # ============================================================================

  options.stackpanel.extensions = lib.mkOption {
    type = lib.types.attrsOf extensionType;
    default = { };
    description = ''
      Extensions that provide features and UI panels for stackpanel.

      Extensions are feature modules that compose core stackpanel features:
        - File generation (stackpanel.files.entries)
        - Script generation (stackpanel.scripts)
        - Tasks (stackpanel.tasks)
        - Variables/secrets (stackpanel.secrets)
        - Shell hooks (stackpanel.devshell.hooks)
        - UI panels (stackpanel.extensions.*.panels)

      Each extension can define:
        - `name`: Display name
        - `description`: What the extension does
        - `enabled`: Whether the extension is active
        - `builtin`: Whether it's shipped with stackpanel
        - `features`: Which core features it uses
        - `panels`: List of UI panels to render
        - `apps`: Per-app computed data

      Builtin extensions (like SST) register themselves automatically.
      External extensions can be added from GitHub or local paths.
    '';
    example = lib.literalExpression ''
      {
        sst = {
          name = "SST Infrastructure";
          enabled = true;
          builtin = true;
          category = "EXTENSION_CATEGORY_INFRASTRUCTURE";
          features = {
            files = true;
            scripts = true;
            secrets = true;
          };
          panels = [
            {
              id = "sst-status";
              title = "SST Infrastructure";
              type = "PANEL_TYPE_STATUS";
              fields = [
                { name = "metrics"; type = "FIELD_TYPE_STRING"; value = "[...]"; }
              ];
            }
          ];
        };

        my-extension = {
          name = "My Custom Extension";
          enabled = true;
          source = {
            type = "EXTENSION_SOURCE_TYPE_GITHUB";
            repo = "myorg/my-stackpanel-extension";
            ref = "main";
          };
        };
      }
    '';
  };

  # Expose computed/serializable extensions for nix eval
  options.stackpanel.extensionsComputed = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = enabledExtensions;
    description = "Computed extension configurations (only enabled extensions)";
  };

  # Expose builtin extensions for inspection
  options.stackpanel.extensionsBuiltin = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = builtinExtensions;
    description = "Builtin extensions shipped with stackpanel";
  };

  # Expose external extensions for inspection
  options.stackpanel.extensionsExternal = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = externalExtensions;
    description = "External/local extensions added by the project";
  };

  # Expose discovered scripts for debugging/inspection
  options.stackpanel.extensionsDiscoveredScripts = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = discoveredScripts;
    description = "Scripts auto-discovered from extension srcDir directories";
  };

  # Expose discovered healthchecks for debugging/inspection
  options.stackpanel.extensionsDiscoveredHealthchecks = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = discoveredHealthchecks;
    description = "Healthchecks auto-discovered from extension srcDir directories";
  };

  # ============================================================================
  # Config: Merge discovered resources and alias to modules
  # ============================================================================

  # Note: Auto-discovered resources are NOT automatically merged here.
  # Instead, extensions should explicitly use the discovery library:
  #
  #   stackpanel.scripts = extensionSrc.discoverScripts "my-ext" ./src;
  #
  # Or use the exposed computed values:
  #   config.stackpanel.extensionsDiscoveredScripts
  #   config.stackpanel.extensionsDiscoveredHealthchecks
  #
  # This avoids module ordering issues where scripts/healthchecks options
  # may not be defined yet when this module is evaluated.

  config = lib.mkIf cfg.enable {
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
