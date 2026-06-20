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
        description = "Where Stackpanel should load or identify this extension from.";
        example = "EXTENSION_SOURCE_TYPE_GITHUB";
      };
      repo = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "GitHub repository in owner/repo form when source type is GitHub.";
        example = "darkmatter/stackpanel-sst";
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "NPM package name when source type is NPM.";
        example = "@stackpanel/extension-sst";
      };
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Repo-relative or absolute path when source type is local.";
        example = "./stackpanel/extensions/sst";
      };
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Download or documentation URL when source type is URL.";
        example = "https://example.com/stackpanel-extension.tar.gz";
      };
      ref = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Git branch, tag, or commit for GitHub extension sources.";
        example = "v1.2.0";
      };
      module-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the extension Nix module within the source tree.";
        example = "nix/module.nix";
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
        example = true;
      };
      scripts = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension provides shell scripts/commands";
        example = true;
      };
      tasks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this extension contributes Turborepo task definitions.";
        example = true;
      };
      secrets = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this extension contributes variables or secret metadata.";
        example = true;
      };
      shell-hooks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this extension adds commands to devshell entry hooks.";
        example = true;
      };
      packages = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this extension adds packages to the devshell.";
        example = true;
      };
      services = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension configures services/processes";
        example = true;
      };
      checks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Extension defines checks/validations";
        example = true;
      };
    };
  };

  # Panel field type
  panelFieldType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Field name passed to the extension panel component as a prop key.";
        example = "status";
      };
      type = lib.mkOption {
        type = fieldTypeEnum;
        default = "FIELD_TYPE_STRING";
        description = "Renderer type the UI should use for this extension panel field.";
        example = "FIELD_TYPE_SELECT";
      };
      value = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Field value passed to the UI; complex values should be JSON-encoded strings.";
        example = "ready";
      };
      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Selectable values for select-style extension panel fields.";
        example = [ "dev" "staging" "prod" ];
      };
    };
  };

  # Extension panel type
  extensionPanelType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Unique panel identifier within this extension.";
        example = "sst-status";
      };
      title = lib.mkOption {
        type = lib.types.str;
        description = "Title shown at the top of this extension panel.";
        example = "SST Infrastructure";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional explanatory text shown below the extension panel title.";
        example = "Current SST deployment status and linked resources.";
      };
      type = lib.mkOption {
        type = panelTypeEnum;
        default = "PANEL_TYPE_STATUS";
        description = "Panel type (determines which component to render)";
        example = "PANEL_TYPE_TABLE";
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Display order among this extension's panels; lower values appear first.";
        example = 10;
      };
      fields = lib.mkOption {
        type = lib.types.listOf panelFieldType;
        default = [ ];
        description = "Fields passed to the UI component that renders this extension panel.";
        example = lib.literalExpression ''
          [
            { name = "status"; type = "FIELD_TYPE_STRING"; value = "ready"; }
            { name = "environment"; type = "FIELD_TYPE_SELECT"; options = [ "dev" "prod" ]; }
          ]
        '';
      };
    };
  };

  # Per-app extension data type
  extensionAppDataType = lib.types.submodule {
    options = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this extension is enabled for the app entry in app-scoped UI data.";
        example = false;
      };
      config = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "String metadata for this app/extension pair, serialized for UI panels.";
        example = lib.literalExpression ''
          {
            stage = "dev";
            region = "us-east-1";
          }
        '';
      };
    };
  };

  # Main extension type
  extensionType = lib.types.submodule {
    options = {
      # Identity
      name = lib.mkOption {
        type = lib.types.str;
        description = "Human-readable extension name shown in the Studio UI.";
        example = "SST Infrastructure";
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Human-readable description of what the extension does";
        example = "Adds SST deploy scripts, env vars, and status panels.";
      };

      # Status
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this extension is active and contributes computed module data.";
        example = false;
      };
      builtin = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this extension ships with Stackpanel rather than being project-provided.";
        example = true;
      };

      # Source information
      source = lib.mkOption {
        type = extensionSourceType;
        default = { };
        description = "Source configuration used to locate or install this extension.";
        example = lib.literalExpression ''
          {
            type = "EXTENSION_SOURCE_TYPE_GITHUB";
            repo = "darkmatter/stackpanel-sst";
            ref = "v1.2.0";
            module-path = "nix/module.nix";
          }
        '';
      };
      version = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Version constraint (e.g., '^1.0.0', '~2.3', 'latest')";
        example = "^1.2.0";
      };

      # Organization
      category = lib.mkOption {
        type = categoryEnum;
        default = "EXTENSION_CATEGORY_UNSPECIFIED";
        description = "Category used to group this extension in the UI.";
        example = "EXTENSION_CATEGORY_INFRASTRUCTURE";
      };
      priority = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Load order priority for extension processing; lower values load earlier.";
        example = 25;
      };
      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Tags used for extension search, filtering, and catalog grouping.";
        example = [ "sst" "aws" "deploy" ];
      };
      dependencies = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extension IDs that must be enabled before this extension can work correctly.";
        example = [ "aws" "secrets" ];
      };

      # Core feature flags
      features = lib.mkOption {
        type = extensionFeaturesType;
        default = { };
        description = "Feature flags declaring which Stackpanel subsystems this extension integrates with.";
        example = lib.literalExpression ''
          {
            scripts = true;
            tasks = true;
            secrets = true;
            checks = true;
          }
        '';
      };

      # UI configuration
      panels = lib.mkOption {
        type = lib.types.listOf extensionPanelType;
        default = [ ];
        description = "UI panels registered by this extension for the Studio.";
        example = lib.literalExpression ''
          [
            {
              id = "sst-status";
              title = "SST Infrastructure";
              type = "PANEL_TYPE_STATUS";
              fields = [ { name = "status"; value = "ready"; } ];
            }
          ]
        '';
      };
      apps = lib.mkOption {
        type = lib.types.attrsOf extensionAppDataType;
        default = { };
        description = "Per-app extension metadata keyed by app name for app-scoped panels.";
        example = lib.literalExpression ''
          {
            web = {
              enabled = true;
              config = { stage = "dev"; };
            };
          }
        '';
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
    description = ''
      Computed extension configurations after filtering disabled extensions.

      Intended for inspection by the agent/UI and for debugging module merge
      results; configure `stackpanel.extensions` instead.
    '';
    example = lib.literalExpression ''
      {
        sst = { name = "SST Infrastructure"; enabled = true; builtin = true; };
      }
    '';
  };

  # Expose builtin extensions for inspection
  options.stackpanel.extensionsBuiltin = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = builtinExtensions;
    description = "Enabled and disabled builtin extensions shipped with stackpanel.";
    example = lib.literalExpression ''
      {
        sst = { name = "SST Infrastructure"; builtin = true; };
      }
    '';
  };

  # Expose external extensions for inspection
  options.stackpanel.extensionsExternal = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = externalExtensions;
    description = "External or local extensions added by the project configuration.";
    example = lib.literalExpression ''
      {
        my-extension = {
          name = "My Extension";
          source = { type = "EXTENSION_SOURCE_TYPE_LOCAL"; path = "./extensions/my-extension"; };
        };
      }
    '';
  };

  # Expose discovered scripts for debugging/inspection
  options.stackpanel.extensionsDiscoveredScripts = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = discoveredScripts;
    description = "Scripts auto-discovered from extension `srcDir` directories.";
    example = lib.literalExpression ''
      {
        "my-ext:deploy" = {
          exec = "./extensions/my-ext/src/scripts/deploy.sh";
        };
      }
    '';
  };

  # Expose discovered healthchecks for debugging/inspection
  options.stackpanel.extensionsDiscoveredHealthchecks = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = discoveredHealthchecks;
    description = "Healthchecks auto-discovered from extension `srcDir` directories.";
    example = lib.literalExpression ''
      {
        "my-ext:ready" = {
          command = "./extensions/my-ext/src/checks/ready.sh";
        };
      }
    '';
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
              inherit (src) path;
            }
          else if src.type == "EXTENSION_SOURCE_TYPE_GITHUB" then
            {
              type = "flake-input";
              # GitHub repos would need to be added as flake inputs
              path = src.repo;
              inherit (src) ref;
            }
          else
            { type = "builtin"; };
      in
      {
        enable = ext.enabled;
        meta = {
          inherit (ext) name;
          inherit (ext) description;
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
