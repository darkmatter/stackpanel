# ==============================================================================
# module.nix - Fly.io Deployment Module Implementation
#
# Provides Fly.io deployment support using nix2container (default) or dockerTools.
#
# This module:
#   1. Adds deployment.* options to each app via appModules
#   2. Auto-contributes to stackpanel.containers.images for deployable apps
#   3. Generates fly.toml into packages/infra/fly/
#   4. Adds deploy scripts to packages/infra/package.json
#   5. Registers turbo tasks for build + deploy workflow
#   6. Creates wrapped fly-<app> commands for each deployable app
#
# Container workflow:
#   bun run build                          # Build app (in app directory)
#   container-build web                    # Build container image
#   container-copy web docker://...        # Push to registry
#   fly-web deploy --image registry.fly.io/my-app:latest
#
# Generated layout:
#   packages/infra/
#   ├── package.json           # "deploy:web" script (merged via SST)
#   ├── turbo.json             # Per-package turbo config (extends root)
#   └── fly/
#       └── <appName>/
#           └── fly.toml       # Fly.io app configuration
#
# Usage:
#   stackpanel.apps.web = {
#     path = "apps/web";
#     deployment = {
#       enable = true;
#       provider = "fly";
#       fly.appName = "my-app";
#       container = { type = "bun"; port = 3000; };
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

  # Import schema for SpField definitions
  flySchema = import ./schema.nix { inherit lib; };
  sp = import ../../db/lib/field.nix { inherit lib; };

  # ---------------------------------------------------------------------------
  # Per-app deployment options module (added via appModules)
  # Uses SpField schema for simple fields, manual definitions for complex types
  # ---------------------------------------------------------------------------
  deploymentAppModule =
    { lib, name, ... }:
    {
      options.deployment = {
        fly = {
          # Simple fields from schema (auto-converted via sp.asOption)
          memory = sp.asOption flySchema.fields.memory;
          cpus = sp.asOption flySchema.fields.cpus;
          autoStart = sp.asOption flySchema.fields.autoStart;
          minMachines = sp.asOption flySchema.fields.minMachines;
          forceHttps = sp.asOption flySchema.fields.forceHttps;
          env = sp.asOption flySchema.fields.env;

          # App name defaults to stackpanel app name - needs special handling
          appName = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = flySchema.fields.appName.description;
            example = flySchema.fields.appName.example or null;
          };

          # Region defaults to global setting - needs special handling
          region = lib.mkOption {
            type = lib.types.str;
            default = deployCfg.fly.defaultRegion or flySchema.fields.region.default or "iad";
            description = flySchema.fields.region.description;
          };

          # Override cpuKind to use enum for strict validation in Nix
          cpuKind = lib.mkOption {
            type = lib.types.enum [
              "shared"
              "performance"
            ];
            default = flySchema.fields.cpuKind.default or "shared";
            description = flySchema.fields.cpuKind.description;
          };

          # Override autoStop to use enum for strict validation
          autoStop = lib.mkOption {
            type = lib.types.enum [
              "off"
              "stop"
              "suspend"
            ];
            default = flySchema.fields.autoStop.default or "suspend";
            description = flySchema.fields.autoStop.description;
          };
        };

        container = {
          type = lib.mkOption {
            type = lib.types.enum [
              "bun"
              "node"
              "go"
              "static"
              "custom"
            ];
            default = "bun";
            description = "App type determines base image and startup command.";
          };

          port = lib.mkOption {
            type = lib.types.int;
            default = 3000;
            description = "Internal port the app listens on.";
          };

          entrypoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Container startup command override.";
          };
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Filter deployable apps
  # ---------------------------------------------------------------------------
  getDeployableApps =
    apps:
    lib.filterAttrs (
      _: appCfg:
      (appCfg.deployment.enable or false)
      && (appCfg.deployment.host or deployCfg.defaultHost or "fly") == "fly"
    ) apps;

  # ---------------------------------------------------------------------------
  # Generate fly.toml content
  # Uses pre-built container images pushed via nix2container/dockerTools
  # ---------------------------------------------------------------------------
  mkFlyToml =
    appName: appCfg:
    let
      d = appCfg.deployment;
      f = d.fly;
      c = d.container;
      org = deployCfg.fly.organization or null;
      flyAppName = f.appName or appName;

      allEnv = {
        PORT = toString c.port;
      }
      // f.env;
      envSection = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} = '${v}'") allEnv);

      # Organization line (optional)
      orgLine = lib.optionalString (org != null) ''
        org = "${org}"
      '';
    in
    ''
      # Generated by stackpanel - do not edit manually
      # Regenerate by entering the devshell: nix develop --impure
      #
      # Deploy workflow (uses nix2container/dockerTools):
      #   1. Build app:        bun run build (in app directory)
      #   2. Build container:  container-build ${appName}
      #   3. Push container:   container-copy ${appName} docker://registry.fly.io/
      #   4. Deploy:           flyctl deploy --config ${infraPath}/fly/${appName}/fly.toml --image registry.fly.io/${flyAppName}:latest
      #
      # Or use turbo workflow:
      #   turbo run ship:${appName}

      app = "${flyAppName}"
      ${orgLine}
      # Build section removed - we use pre-built container images
      # Container is built with nix2container/dockerTools and pushed via skopeo

      [env]
      ${envSection}

      [http_service]
      internal_port = ${toString c.port}
      force_https = ${lib.boolToString f.forceHttps}
      auto_stop_machines = "${f.autoStop}"
      auto_start_machines = ${lib.boolToString f.autoStart}
      min_machines_running = ${toString f.minMachines}
      processes = ["app"]

      [[vm]]
      memory = "${f.memory}"
      cpu_kind = "${f.cpuKind}"
      cpus = ${toString f.cpus}
    '';

  # ---------------------------------------------------------------------------
  # Package.json scripts for packages/infra
  # ---------------------------------------------------------------------------
  # Organization for Fly.io (if configured)
  flyOrg = deployCfg.fly.organization or null;
  orgFlag = if flyOrg != null then "--org ${flyOrg}" else "";

  mkDeployPackageScripts =
    deployableApps:
    lib.foldlAttrs (
      acc: appName: appCfg:
      let
        flyAppName = appCfg.deployment.fly.appName or appName;
      in
      acc
      // {
        # Build container (nix2container)
        "container:build:${appName}" =
          "cd ../.. && nix build --impure .#packages.x86_64-linux.container-${appName}";
        # Push container to Fly.io registry (dockerTools + skopeo)
        "container:push:${appName}" =
          "cd ../.. && nix run --impure .#copy-container-${appName} -- docker://registry.fly.io/ --dest-creds x:$(flyctl auth token)";
        # Deploy to Fly.io (creates app if needed, uses pre-pushed image)
        "deploy:${appName}" =
          "cd ../.. && (flyctl status -a ${flyAppName} > /dev/null 2>&1 || flyctl apps create ${flyAppName} ${orgFlag}) && flyctl deploy --config ${infraPath}/fly/${appName}/fly.toml --image registry.fly.io/${flyAppName}:latest";
        # Full workflow
        "ship:${appName}" = "turbo run deploy:${appName}";
      }
    ) { } deployableApps;

  # ---------------------------------------------------------------------------
  # Turbo tasks - Global task definitions with transit dependencies
  #
  # Workflow: build -> container:build -> container:push -> deploy
  #
  # Each app with deployment.enable has scripts generated at:
  #   apps/<app>/.tasks/bin/{container-build,container-push,deploy}
  #
  # Apps add short wrappers in package.json that call these scripts.
  # Turbo runs tasks across all packages that have them.
  # ---------------------------------------------------------------------------

  # Global turbo task definitions (apply to any package with the script)
  globalDeployTasks = {
    # build:container is a separate build script that apps can customize
    # For Fly.io apps: runs Node/Nitro build (no ALCHEMY)
    # For Cloudflare apps: this task won't exist, so turbo skips it
    "build:container" = {
      description = "Build app for container deployment";
      # No cache - we want fresh builds for containers
      cache = false;
    };
    # Container build depends on the app's container build script
    "container:build" = {
      description = "Build container image";
      cache = false;
      dependsOn = [ "build:container" ];
    };
    # Container push depends on container build
    "container:push" = {
      description = "Push container to registry";
      cache = false;
      dependsOn = [ "container:build" ];
    };
    # Deploy depends on container push
    "deploy" = {
      description = "Deploy to production";
      cache = false;
      dependsOn = [ "container:push" ];
    };
  };

  # ---------------------------------------------------------------------------
  # Per-app deploy scripts (generated at apps/<app>/.tasks/bin/)
  # ---------------------------------------------------------------------------
  mkAppDeployScriptDerivations =
    appName: appCfg:
    let
      flyAppName = appCfg.deployment.fly.appName or appName;
      flyConfigPath = "${infraPath}/fly/${appName}/fly.toml";
      appPath = appCfg.path or "apps/${appName}";
    in
    {
      # Build container via nix
      "container-build" = pkgs.writeShellScriptBin "container-build" ''
        set -euo pipefail
        # Find repo root (use STACKPANEL_ROOT or git root)
        ROOT="''${STACKPANEL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
        cd "$ROOT"
        echo "📦 Building container for ${appName}..."
        nix build --impure ".#packages.x86_64-linux.container-${appName}"
        echo "✅ Container built: ./result"
      '';

      # Push to Fly registry
      "container-push" = pkgs.writeShellScriptBin "container-push" ''
        set -euo pipefail
        # Find repo root
        ROOT="''${STACKPANEL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
        cd "$ROOT"
        echo "📤 Pushing container for ${appName} to Fly.io..."
        nix run --impure ".#copy-container-${appName}"
        echo "✅ Container pushed to registry.fly.io/${flyAppName}:latest"
      '';

      # Deploy to Fly
      "deploy" = pkgs.writeShellScriptBin "deploy" ''
        set -euo pipefail
        # Find repo root
        ROOT="''${STACKPANEL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
        cd "$ROOT"

        # Ensure app exists (create if not)
        if ! flyctl status -a ${flyAppName} > /dev/null 2>&1; then
          echo "📱 Creating Fly.io app: ${flyAppName}..."
          flyctl apps create ${flyAppName} ${orgFlag}
        fi

        echo "🚀 Deploying ${appName} to Fly.io..."
        flyctl deploy --config ${flyConfigPath} --image "registry.fly.io/${flyAppName}:latest"
        echo "✅ Deployed to https://${flyAppName}.fly.dev/"
      '';
    };

  # Generate file entries for app deploy scripts
  mkAppDeployFileEntries =
    appName: appCfg:
    let
      scripts = mkAppDeployScriptDerivations appName appCfg;
      appPath = appCfg.path or "apps/${appName}";
    in
    lib.mapAttrs' (scriptName: scriptDrv: {
      name = "${appPath}/.tasks/bin/${scriptName}";
      value = {
        type = "symlink";
        target = "${scriptDrv}/bin/${scriptName}";
        source = meta.id;
        description = "Deploy script: ${scriptName} for ${appName}";
      };
    }) scripts;

  # Per-package turbo.json
  infraTurboJson = builtins.toJSON { extends = [ "//" ]; };

  # ---------------------------------------------------------------------------
  # Generate container configs for deployable apps
  # These are contributed to stackpanel.containers for nix2container builds
  # ---------------------------------------------------------------------------
  mkContainerConfigs =
    deployableApps:
    lib.mapAttrs (
      appName: appCfg:
      let
        d = appCfg.deployment;
        c = d.container;
        f = d.fly;
        flyAppName = f.appName or appName;
        appPath = appCfg.path or "apps/${appName}";
      in
      {
        name = flyAppName;
        version = "latest";
        type = c.type;
        port = c.port;
        registry = "docker://registry.fly.io/";
        workingDir = "/app";
        # Build output path for impure builds (app built on macOS, copied to container)
        buildOutputPath = "${appPath}/.output";
        # Fly.io auth via flyctl
        defaultCopyArgs = [
          "--dest-creds"
          "x:$(flyctl auth token)"
        ];
        # Container environment
        env = {
          PORT = toString c.port;
        }
        // f.env;
      }
    ) deployableApps;

  # Check if we have any deployable apps
  hasDeployableApps = deployableApps != { };
  deployableApps = getDeployableApps cfg.apps;

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.deployment = {
    enable = lib.mkEnableOption "deployment module" // {
      default = true;
    };

    defaultHost = lib.mkOption {
      type = lib.types.enum [
        "cloudflare"
        "fly"
        "vercel"
        "aws"
      ];
      default = "cloudflare";
      description = ''
        Default deployment host for apps that don't specify one.
        - cloudflare: Cloudflare Workers (edge, serverless)
        - fly: Fly.io (containers, VMs)
        - vercel: Vercel (Next.js, etc.)
        - aws: AWS (Lambda, ECS, etc.)
      '';
    };

    fly = {
      organization = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Fly.io organization slug.";
      };

      defaultRegion = lib.mkOption {
        type = lib.types.str;
        default = "iad";
        description = "Default Fly.io region for deployments.";
      };
    };
  };

  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # Always add appModules (unconditionally)
    {
      stackpanel.appModules = [ deploymentAppModule ];
    }

    # Apply config when stackpanel is enabled and has deployable apps
    (lib.mkIf (cfg.enable && deployCfg.enable && hasDeployableApps) {
      # NOTE: Container configs are NOT contributed here.
      # The containers module reads deployment.fly.* settings and applies them.
      # This avoids conflicts when both container.enable and deployment.enable are true.

      # Enable docker tooling for skopeo
      stackpanel.docker.enable = true;

      # -------------------------------------------------------------------------
      # Merge deploy scripts into SST's packages/infra/package.json
      # -------------------------------------------------------------------------
      stackpanel.sst.package.scripts = mkDeployPackageScripts deployableApps;

      # -------------------------------------------------------------------------
      # Generated Files (fly.toml + per-app deploy scripts)
      # -------------------------------------------------------------------------
      stackpanel.files.entries = lib.mkMerge [
        # packages/infra/turbo.json
        {
          "${infraPath}/turbo.json" = {
            type = "text";
            text = infraTurboJson;
            source = meta.id;
            description = "Per-package turbo config for deploy tasks";
          };
        }

        # packages/infra/fly/<appName>/fly.toml
        (lib.mapAttrs' (appName: appCfg: {
          name = "${infraPath}/fly/${appName}/fly.toml";
          value = {
            type = "text";
            text = mkFlyToml appName appCfg;
            source = meta.id;
            description = "Fly.io configuration for ${appName}";
          };
        }) deployableApps)

        # Per-app deploy scripts at apps/<app>/.tasks/bin/
        (lib.mkMerge (lib.mapAttrsToList mkAppDeployFileEntries deployableApps))
      ];

      # -------------------------------------------------------------------------
      # Turbo Tasks (global definitions)
      # -------------------------------------------------------------------------
      stackpanel.tasks = globalDeployTasks;

      # -------------------------------------------------------------------------
      # Per-app package.json scripts (injected into apps via appModules)
      # -------------------------------------------------------------------------
      # This is handled by the deploymentAppModule which adds scripts to each app

      # -------------------------------------------------------------------------
      # Devshell Packages
      # -------------------------------------------------------------------------
      stackpanel.devshell.packages = [
        pkgs.flyctl
      ];

      # -------------------------------------------------------------------------
      # Wrapped fly commands per app (bakes in -c and -a flags)
      # Usage: fly-web status, fly-web logs, fly-web ssh console, etc.
      # -------------------------------------------------------------------------
      stackpanel.scripts = lib.mapAttrs' (
        appName: appCfg:
        let
          flyAppName = appCfg.deployment.fly.appName or appName;
          configPath = "${infraPath}/fly/${appName}/fly.toml";
        in
        {
          name = "fly-${appName}";
          value = {
            description = "Fly.io CLI for ${appName} (pre-configured)";
            args = [
              {
                name = "command";
                description = "Flyctl command (status, logs, deploy, etc.)";
                required = true;
              }
              {
                name = "...";
                description = "Additional flyctl arguments";
              }
            ];
            exec = ''
              # Wrapped flyctl with pre-configured app and config
              # Usage: fly-${appName} <command> [args...]
              #
              # Examples:
              #   fly-${appName} status
              #   fly-${appName} logs
              #   fly-${appName} ssh console
              #   fly-${appName} secrets list
              #   fly-${appName} scale count 2

              if [ $# -eq 0 ]; then
                echo "fly-${appName}: Wrapped flyctl for ${appName}"
                echo ""
                echo "Pre-configured with:"
                echo "  --app ${flyAppName}"
                echo "  --config ${configPath}"
                echo ""
                echo "Usage: fly-${appName} <command> [args...]"
                echo ""
                echo "Common commands:"
                echo "  status     - Show app status"
                echo "  logs       - Stream logs"
                echo "  ssh console - SSH into a machine"
                echo "  secrets    - Manage secrets"
                echo "  scale      - Scale machines"
                echo "  deploy     - Deploy the app"
                echo ""
                flyctl --help
                exit 0
              fi

              exec flyctl --app "${flyAppName}" --config "${configPath}" "$@"
            '';
          };
        }
      ) deployableApps;

      # -------------------------------------------------------------------------
      # Health Checks
      # -------------------------------------------------------------------------
      stackpanel.healthchecks.modules.${meta.id} = {
        enable = true;
        displayName = meta.name;
        checks = {
          flyctl-installed = {
            description = "Fly.io CLI is installed and accessible";
            script = ''
              command -v flyctl >/dev/null 2>&1 && flyctl version
            '';
            severity = "critical";
            timeout = 5;
          };

          flyctl-auth = {
            description = "Logged in to Fly.io";
            script = ''
              flyctl auth whoami 2>/dev/null
            '';
            severity = "warning";
            timeout = 10;
          };
        };
      };

      # -------------------------------------------------------------------------
      # Module Registration
      # -------------------------------------------------------------------------
      stackpanel.modules.${meta.id} = {
        enable = true;
        meta = {
          name = meta.name;
          description = meta.description;
          icon = meta.icon;
          category = meta.category;
          author = meta.author;
          version = meta.version;
          homepage = meta.homepage;
        };
        source.type = "builtin";
        features = meta.features;
        tags = meta.tags;
        priority = meta.priority;
      };
    })
  ];
}
