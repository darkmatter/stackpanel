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
#       embedded-data.ts                 — runtime metadata manifest
#       entrypoints/<app>.ts, entrypoints/index.ts
#       loader.ts, docker-entrypoint.ts
#     data/
#       <env>/<app>.sops.json            — encrypted runtime payloads (built by `stackpanel codegen build`)
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
  envPackage = import ../../lib/codegen/env-package.nix { inherit lib config pkgs; };

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

    references = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.attrsOf lib.types.str));
      default = { };
      description = ''
        Explicit variable reference metadata for generated env payloads.

        Structure: env.references.<app>.<environment>.<ENV_KEY> = "/group/variable-id";

        Use this when an environment variable aliases a grouped variable through
        an expression such as `config.variables."/secret/foo".value` and the
        generated manifest should preserve the original variable reference.
      '';
      example = {
        docs.dev.HELLO = "/secret/cool-secre";
      };
    };
  };

  # ===========================================================================
  # Config
  # ===========================================================================
  config = lib.mkIf hasAppsWithEnvs {
    # Register generated files
    stackpanel.files.entries = envPackage.fileEntries;

    # Auto-populate `stackpanel.envs.<env>.<KEY>` from `apps.<app>.env`,
    # OR-merging across all apps that target the same environment. Other
    # modules can layer on top by writing `stackpanel.envs.<env>.<KEY> = …`
    # — those declarations merge with these via the option's submodule
    # semantics (later definitions take precedence per attribute).
    stackpanel.envs = envPackage.mergedAppEnvs;

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
        runtime-manifest-exists = {
          name = "Env Runtime Manifest Generated";
          description = "Check if the generated env runtime manifests exist";
          type = "script";
          script = ''
            [ -f "${envOutputDir}/src/embedded-data.ts" ] && [ -f ".stack/gen/codegen/env-manifest.json" ]
          '';
          severity = "warning";
          timeout = 5;
          tags = [
            "codegen"
            "env"
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
