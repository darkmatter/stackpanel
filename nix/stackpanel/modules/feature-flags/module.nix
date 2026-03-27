# ==============================================================================
# feature-flags/module.nix
#
# Generates packages/gen/featureflags from shared defaults (or overrides
# provided via stackpanel.feature-flags.definitions) and writes files through
# stackpanel.files.entries.
#
# Generated files:
#   packages/gen/featureflags/package.json
#   packages/gen/featureflags/src/feature-flags.tsx
#   packages/gen/featureflags/src/index.ts
#   packages/gen/featureflags/tsconfig.json
#   packages/gen/featureflags/README.md
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;
  meta = import ./meta.nix;
  featureFlagsOutputDir = cfg."feature-flags".output-dir or "packages/gen/featureflags";

  # Catalog versions for dependencies used by the generated package.json template.
  # These must stay in sync with the "catalog:" references in
  # lib/codegen/templates/feature-flags/package.json.tmpl
  featureFlagsCatalogDeps = {
    "@tanstack/react-router" = "^1.143.6";
    "react" = "19.2.4";
  };

  featureFlagsPackage = import ../../lib/codegen/feature-flags-package.nix {
    inherit lib config;
  };

  shouldGenerate = featureFlagsPackage.enabled;

in

{
  # ==========================================================================
  # Options
  # ==========================================================================
  options.stackpanel."feature-flags" = {
    definitions = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.attrs);
      default = null;
      description = ''
        Optional override for Studio feature-flag definitions used by the generated
        `@gen/featureflags` package.

        Example entry shape:

        ```nix
        {
          key = "studio.overview.layout";
          kind = "variant";
          label = "Overview layout";
          description = "...";
          defaultValue = "classic";
          rollout = 100;
          variants = [ "classic" "compact" ];
        }
        ```

        Boolean flag examples are supported by setting `kind = "boolean"` and
        omitting `variants`.
      '';
      example = [
        {
          key = "studio.overview.layout";
          kind = "variant";
          label = "Overview layout";
          description = "Select between classic and compact studio overview layouts";
          defaultValue = "classic";
          rollout = 100;
          variants = [
            "classic"
            "compact"
          ];
        }
      ];
    };

    output-dir = lib.mkOption {
      type = lib.types.str;
      default = "packages/gen/featureflags";
      description = ''
        Output directory for the generated feature-flags package (relative to
        project root).

        Examples:
          "packages/gen/featureflags"     — monorepo workspace package
          "packages/featureflags"         — alternate package location
      '';
      example = "packages/featureflags";
    };

    package-name = lib.mkOption {
      type = lib.types.str;
      default = "@gen/featureflags";
      description = ''
        NPM package name for the generated feature-flags package.
      '';
      example = "@gen/featureflags";
    };
  };

  # ==========================================================================
  # Config
  # ==========================================================================
  config = lib.mkIf shouldGenerate {
    # Catalog entries — register actual versions for "catalog:" references
    stackpanel.bun.catalog = lib.mkIf cfg.enable featureFlagsCatalogDeps;

    # Register generated files with the Stackpanel file system bridge.
    stackpanel.files.entries = featureFlagsPackage.fileEntries;

    # Register module metadata.
    stackpanel.modules.${meta.id} = {
      enable = true;
      meta = {
        name = meta.name;
        description = meta.description;
        icon = meta.icon;
        category = meta.category;
        author = meta.author;
        version = meta.version;
      };
      source.type = "builtin";
      features = {
        files = true;
        scripts = false;
        healthchecks = true;
        packages = false;
        services = false;
        secrets = false;
      };
      tags = meta.tags;
      priority = meta.priority;
      healthcheckModule = meta.id;
    };

    # Basic presence checks so the module is discoverable in dashboards.
    stackpanel.healthchecks.modules.${meta.id} = {
      enable = true;
      displayName = meta.name;
      checks = {
        generated-package = {
          name = "Feature flags package generated";
          description = "Check if ${featureFlagsOutputDir}/package.json exists";
          type = "script";
          script = ''
            [ -f "${featureFlagsOutputDir}/package.json" ]
          '';
          severity = "warning";
          timeout = 5;
          tags = [
            "codegen"
            "feature-flags"
          ];
        };

        generated-provider = {
          name = "Feature flags provider generated";
          description = "Check if ${featureFlagsOutputDir}/src/feature-flags.tsx exists";
          type = "script";
          script = ''
            [ -f "${featureFlagsOutputDir}/src/feature-flags.tsx" ]
          '';
          severity = "warning";
          timeout = 5;
          tags = [
            "codegen"
            "typescript"
          ];
        };
      };
    };
  };
}
