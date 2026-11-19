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
#       <env>/<app>.sops.json            — encrypted runtime payloads (built by `stack codegen build`)
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
  envOutputDir = config.stackpanel.env.output-dir;

  # Import the codegen library
  envPackage = import ../../lib/codegen/env-package.nix { inherit lib config pkgs; };

  # Check if we should generate files
  hasAppsWithEnvs = envPackage.enabled;
  enabled = hasAppsWithEnvs && config.stackpanel.modules.${meta.id}.enable;

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

        Stackpanel owns files under this directory. Do not edit generated
        TypeScript modules manually; edit app env declarations or variable schemas.

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

        Apps import this package for type-safe env access, for example
        `import "@gen/env/web"`.
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
  config = {
    # Register generated files
    stackpanel.files.entries = lib.mkIf enabled (
      lib.mapAttrs (_: entry: entry // { module = meta.id; }) envPackage.fileEntries
    );

    # Auto-populate `stackpanel.envs."<app-path>/<env>".<KEY>` from
    # `apps.<app>.env` so app-specific values never collide at the root env
    # registry. Other modules can still layer on top by writing their own
    # `stackpanel.envs.<scope>.<KEY> = …` entries.
    stackpanel.envs = lib.mkIf enabled envPackage.mergedAppEnvs;

    # Register module
    stackpanel.modules.${meta.id} = {
      enable = lib.mkDefault hasAppsWithEnvs;
      configPath = "env";
      meta = {
        inherit (meta) name;
        inherit (meta) description;
        icon = "FileCode";
        inherit (meta) category;
        inherit (meta) version;
      };
      source.type = "builtin";
      healthcheckModule = meta.id;
      features = {
        files = true;
        healthchecks = true;
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
    stackpanel.doctor.${meta.id} = lib.mkIf enabled {
      enable = true;
      displayName = meta.name;
      runtime-manifest-exists = {
        module = meta.id;
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
        module = meta.id;
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
}
