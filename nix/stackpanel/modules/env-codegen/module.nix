# ==============================================================================
# env-codegen/module.nix
#
# Generates the packages/gen/env structure from stackpanel.apps configuration.
#
# This module integrates env-package.nix codegen into the files system,
# ensuring all generated files are created on devshell entry.
#
# Generated files:
#   packages/gen/env/                    — generated package shell
#     package.json, tsconfig.json, README.md
#     src/                               — 100% generated (do not edit)
#       <app>/<env>.ts, <app>/index.ts, index.ts
#       <app>.ts                         — app-level env export (@gen/env/web)
#       embedded-data.ts                 — embedded plaintext + encrypted payloads
#       entrypoints/<app>.ts, entrypoints/index.ts
#       loader.ts, docker-entrypoint.ts
#
# Usage:
#   # The module is automatically enabled when apps have environments
#   stackpanel.apps.web.environments.dev.env = {
#     DATABASE_URL = "ref+sops://...";
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;
  envOutputDir = config.stackpanel.env.output-dir;

  # Import the codegen library
  envPackage = import ../../lib/codegen/env-package.nix { inherit lib config; };

  # Check if we should generate files
  hasAppsWithEnvs = envPackage.enabled;

  # Module metadata
  meta = {
    id = "env-codegen";
    name = "Environment Codegen";
    description = "Generates packages/gen/env structure from app configurations";
    category = "codegen";
    version = "1.0.0";
  };

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.env = {
    output-dir = lib.mkOption {
      type = lib.types.str;
      default = "packages/gen/env";
      description = ''
        Output directory for the generated env package (relative to project root).

        Examples:
          "packages/gen/env"       — monorepo with @gen/env workspace package
          "packages/env"           — traditional packages/env location
          "apps/my-app/gen/env"    — co-located with a specific app
      '';
      example = "packages/env";
    };

    package-name = lib.mkOption {
      type = lib.types.str;
      default = "@${config.stackpanel.project.owner}/env";
      description = ''
        NPM package name for the generated env package.
        Defaults to @{project.owner}/env (e.g., @darkmatter/env).
      '';
      example = "@gen/env";
    };
  };

  # ===========================================================================
  # Config
  # ===========================================================================
  config = lib.mkIf hasAppsWithEnvs {
    # Register generated files
    stackpanel.files.entries = envPackage.fileEntries;

    # Register module
    stackpanel.modules.${meta.id} = {
      enable = true;
      meta = {
        name = meta.name;
        description = meta.description;
        icon = "FileCode";
        category = "development"; # "codegen" not in allowed values
        version = meta.version;
      };
      source.type = "builtin";
      features = {
        files = true;
        secrets = true;
      };
      flakeInputs = meta.flakeInputs or [ ];
      tags = [
        "codegen"
        "secrets"
        "env"
      ];
      priority = 50; # Run after app definitions are processed
    };

    # Add healthcheck for generated files
    stackpanel.healthchecks.modules.${meta.id} = {
      enable = true;
      displayName = meta.name;
      checks = {
        sops-yaml-exists = {
          name = "Embedded Secrets Generated";
          description = "Check if ${envOutputDir}/src/embedded-data.ts exists";
          type = "script";
          script = ''
            [ -f "${envOutputDir}/src/embedded-data.ts" ]
          '';
          severity = "warning";
          timeout = 5;
          tags = [
            "codegen"
            "sops"
          ];
        };
        generated-ts-exists = {
          name = "TypeScript Modules Generated";
          description = "Check if generated TypeScript modules exist";
          type = "script";
          script = ''
            [ -d "${envOutputDir}/src" ] && [ -f "${envOutputDir}/src/index.ts" ]
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
