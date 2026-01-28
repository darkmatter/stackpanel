# ==============================================================================
# module.nix - Cloudflare Workers Deployment Module
#
# Provides Cloudflare Workers deployment support for stackpanel apps using
# Alchemy for infrastructure-as-code.
#
# This module:
#   1. Adds deployment.cloudflare.* options to each app via appModules
#   2. Generates Alchemy resource definitions
#   3. Adds deploy scripts to packages/infra/package.json
#   4. Registers turbo tasks for build + deploy workflow
#
# Deployment workflow:
#   bun run build                    # Build for Workers (ALCHEMY=1)
#   turbo alchemy:deploy             # Deploy via Alchemy
#
# Usage:
#   stackpanel.apps.web = {
#     path = "apps/web";
#     deployment = {
#       enable = true;
#       provider = "cloudflare";
#       cloudflare = {
#         workerName = "my-web-app";
#         type = "vite";  # or "worker"
#       };
#     };
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  deployCfg = cfg.deployment;
  infraPath = "packages/infra";

  # ---------------------------------------------------------------------------
  # Per-app Cloudflare deployment options (added via appModules)
  # ---------------------------------------------------------------------------
  cloudflareAppModule =
    { lib, name, ... }:
    {
      options.deployment.cloudflare = {
        workerName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Cloudflare Worker name.";
        };

        type = lib.mkOption {
          type = lib.types.enum [
            "vite"
            "worker"
            "pages"
          ];
          default = "vite";
          description = ''
            Cloudflare deployment type:
            - vite: TanStack Start / Vite-based app (uses cloudflare.Vite)
            - worker: Plain Worker (uses cloudflare.Worker)
            - pages: Cloudflare Pages (static + functions)
          '';
        };

        route = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Custom domain route pattern (e.g., 'app.example.com/*').";
        };

        compatibility = lib.mkOption {
          type = lib.types.enum [
            "node"
            "browser"
          ];
          default = "node";
          description = "Worker compatibility mode.";
        };

        bindings = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Environment variable bindings for the Worker.";
        };

        secrets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Secret names to inject (resolved at deploy time).";
          example = [
            "DATABASE_URL"
            "API_KEY"
          ];
        };

        kvNamespaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "KV namespace bindings.";
        };

        d1Databases = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "D1 database bindings.";
        };

        r2Buckets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "R2 bucket bindings.";
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Filter apps with cloudflare deployment enabled
  # ---------------------------------------------------------------------------
  cloudflareApps = lib.filterAttrs (
    _name: appCfg:
    (appCfg.deployment.enable or false) && (appCfg.deployment.provider or deployCfg.defaultProvider) == "cloudflare"
  ) (cfg.apps or { });

  hasCloudflareApps = cloudflareApps != { };

  # ---------------------------------------------------------------------------
  # Generate Alchemy resource TypeScript for an app
  # ---------------------------------------------------------------------------
  mkAlchemyResource =
    appName: appCfg:
    let
      cf = appCfg.deployment.cloudflare;
      appPath = appCfg.path or "apps/${appName}";
    in
    if cf.type == "vite" then
      ''
        export const ${appName} = await cloudflare.Vite("${appName}", {
          cwd: "${appPath}",
          assets: "dist",
          bindings: {
            ${lib.concatStringsSep ",\n    " (lib.mapAttrsToList (k: v: "${k}: ${v}") cf.bindings)}
          },
          dev: {
            command: "bun run dev",
          },
        });
      ''
    else if cf.type == "worker" then
      ''
        export const ${appName} = await cloudflare.Worker("${appName}", {
          cwd: "${appPath}",
          entrypoint: "src/index.ts",
          compatibility: "${cf.compatibility}",
          bindings: {
            ${lib.concatStringsSep ",\n    " (lib.mapAttrsToList (k: v: "${k}: ${v}") cf.bindings)}
          },
        });
      ''
    else
      ''
        // Pages deployment for ${appName}
        export const ${appName} = await cloudflare.Pages("${appName}", {
          cwd: "${appPath}",
          buildCommand: "bun run build",
          outputDirectory: "dist",
        });
      '';

  # ---------------------------------------------------------------------------
  # Generate turbo tasks for Cloudflare deployment
  # ---------------------------------------------------------------------------
  mkDeployTasks = lib.optionalAttrs hasCloudflareApps {
    # Alchemy deploy task already exists, but we can add per-app tasks
    "deploy:cloudflare" = {
      dependsOn = [ "build" ];
      cache = false;
      description = "Deploy all Cloudflare apps via Alchemy";
    };
  };

  # ---------------------------------------------------------------------------
  # Generate package.json scripts
  # ---------------------------------------------------------------------------
  mkDeployScripts = lib.optionalAttrs hasCloudflareApps {
    "deploy:cloudflare" = "alchemy deploy";
    "deploy:cloudflare:dev" = "alchemy dev";
    "deploy:cloudflare:destroy" = "alchemy destroy";
  };

in
{
  # ===========================================================================
  # Config
  # ===========================================================================
  config = lib.mkMerge [
    # Always register the appModule
    {
      stackpanel.appModules = [ cloudflareAppModule ];
    }

    # When Cloudflare apps exist, add tasks and scripts
    (lib.mkIf hasCloudflareApps {
      # Add Cloudflare deploy tasks
      stackpanel.tasks = mkDeployTasks;

      # Add helper scripts
      stackpanel.scripts = {
        deploy-cloudflare = {
          description = "Deploy all Cloudflare Workers via Alchemy";
          exec = ''
            echo "☁️  Deploying to Cloudflare Workers..."
            cd ${infraPath}
            alchemy deploy
          '';
        };

        deploy-cloudflare-dev = {
          description = "Start Cloudflare development mode";
          exec = ''
            echo "☁️  Starting Cloudflare dev mode..."
            cd ${infraPath}
            alchemy dev
          '';
        };
      };

      # Add MOTD entries
      stackpanel.motd.commands = [
        {
          name = "deploy-cloudflare";
          description = "Deploy to Cloudflare Workers";
        }
        {
          name = "turbo alchemy:deploy";
          description = "Deploy via Turborepo";
        }
      ];

      stackpanel.motd.features = [
        "Cloudflare Workers (${toString (lib.length (lib.attrNames cloudflareApps))} apps)"
      ];
    })
  ];
}
