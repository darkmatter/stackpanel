{
  lib,
  types,
  computed,
}:
let
  inherit (types)
    extensionType
    ;
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
    default = computed.enabledExtensions;
    description = "Computed extension configurations (only enabled extensions)";
  };

  # Expose builtin extensions for inspection
  options.stackpanel.extensionsBuiltin = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = computed.builtinExtensions;
    description = "Builtin extensions shipped with stackpanel";
  };

  # Expose external extensions for inspection
  options.stackpanel.extensionsExternal = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = computed.externalExtensions;
    description = "External/local extensions added by the project";
  };

  # Expose discovered scripts for debugging/inspection
  options.stackpanel.extensionsDiscoveredScripts = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = computed.discoveredScripts;
    description = "Scripts auto-discovered from extension srcDir directories";
  };

  # Expose discovered healthchecks for debugging/inspection
  options.stackpanel.extensionsDiscoveredHealthchecks = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = computed.discoveredHealthchecks;
    description = "Healthchecks auto-discovered from extension srcDir directories";
  };
}
