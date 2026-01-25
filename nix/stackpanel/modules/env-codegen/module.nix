# ==============================================================================
# env-codegen/module.nix
#
# Generates the packages/env structure from stackpanel.apps configuration.
#
# This module integrates env-package.nix codegen into the files system,
# ensuring all generated files are created on devshell entry.
#
# Generated files:
#   packages/env/data/.sops.yaml         - SOPS creation rules
#   packages/env/data/shared/vars.yaml   - Shared plaintext config
#   packages/env/data/<app>/<env>.yaml   - Per-app secrets (boilerplate)
#   packages/env/src/generated/          - TypeScript znv modules
#   packages/env/src/entrypoints/        - App entrypoint loaders
#
# Usage:
#   # The module is automatically enabled when apps have environments
#   stackpanel.apps.web.environments.dev.env = {
#     DATABASE_URL = "ref+sops://...";
#   };
# ==============================================================================
{ lib, config, pkgs, ... }:
let
  cfg = config.stackpanel;
  
  # Import the codegen library
  envPackage = import ../../lib/codegen/env-package.nix { inherit lib config; };
  
  # Check if we should generate files
  hasAppsWithEnvs = envPackage.enabled;

  # Module metadata
  meta = {
    id = "env-codegen";
    name = "Environment Codegen";
    description = "Generates packages/env structure from app configurations";
    category = "codegen";
    version = "1.0.0";
  };

in
{
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
        category = "development";  # "codegen" not in allowed values
        version = meta.version;
      };
      source.type = "builtin";
      features = {
        files = true;
        secrets = true;
      };
      tags = [ "codegen" "secrets" "env" ];
      priority = 50; # Run after app definitions are processed
    };

    # Add healthcheck for generated files
    stackpanel.healthchecks.modules.${meta.id} = {
      enable = true;
      displayName = meta.name;
      checks = {
        sops-yaml-exists = {
          name = "SOPS Config Generated";
          description = "Check if packages/env/data/.sops.yaml exists";
          type = "script";
          script = ''
            [ -f "packages/env/data/.sops.yaml" ]
          '';
          severity = "warning";
          timeout = 5;
          tags = [ "codegen" "sops" ];
        };
        generated-ts-exists = {
          name = "TypeScript Modules Generated";
          description = "Check if generated TypeScript modules exist";
          type = "script";
          script = ''
            [ -d "packages/env/src/generated" ] && [ -f "packages/env/src/generated/index.ts" ]
          '';
          severity = "warning";
          timeout = 5;
          tags = [ "codegen" "typescript" ];
        };
      };
    };
  };
}
