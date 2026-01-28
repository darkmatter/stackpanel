# ==============================================================================
# module.nix - Fly.io Deployment Module Implementation
#
# Provides Fly.io deployment support for stackpanel apps using dockerTools.
#
# This module:
#   1. Adds deployment.* options to each app via appModules
#   2. Auto-enables stackpanel.containers for deployable apps
#   3. Generates fly.toml into packages/infra/fly/
#   4. Adds deploy scripts to packages/infra/package.json
#   5. Registers turbo tasks for build + deploy workflow
#   6. Creates wrapped fly-<app> commands for each deployable app
#
# Container workflow:
#   container-build web                    # Build container image
#   container-copy web docker://...        # Push to registry
#   fly-web deploy --image registry.fly.io/stackpanel-web:latest
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

  # ---------------------------------------------------------------------------
  # Per-app deployment options module (added via appModules)
  # ---------------------------------------------------------------------------
  deploymentAppModule =
    { lib, name, ... }:
    {
      options.deployment = {
        enable = lib.mkEnableOption "deployment for this app";

        provider = lib.mkOption {
          type = lib.types.enum [
            "fly"
            "cloudflare"
          ];
          default = deployCfg.defaultProvider or "cloudflare";
          description = ''
            Deployment provider to use.
            
            - fly: Fly.io (containers, VMs) - requires nix2container/dockerTools
            - cloudflare: Cloudflare Workers (edge, serverless) - requires Alchemy
          '';
        };

        fly = {
          appName = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Fly.io app name.";
          };

          region = lib.mkOption {
            type = lib.types.str;
            default = deployCfg.fly.defaultRegion or "iad";
            description = "Fly.io region for deployment.";
          };

          memory = lib.mkOption {
            type = lib.types.str;
            default = "512mb";
            description = "Memory allocation for the VM.";
          };

          cpuKind = lib.mkOption {
            type = lib.types.enum [
              "shared"
              "performance"
            ];
            default = "shared";
            description = "CPU type for the VM.";
          };

          cpus = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Number of CPUs for the VM.";
          };

          autoStop = lib.mkOption {
            type = lib.types.enum [
              "off"
              "stop"
              "suspend"
            ];
            default = "suspend";
            description = "Auto-stop behavior for machines.";
          };

          autoStart = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Auto-start machines on request.";
          };

          minMachines = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Minimum number of machines to keep running.";
          };

          forceHttps = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Force HTTPS for all requests.";
          };

          env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Environment variables for fly.toml.";
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
            description = "App type determines the generated Dockerfile.";
          };

          port = lib.mkOption {
            type = lib.types.int;
            default = 3000;
            description = "Internal port the app listens on.";
          };

          entrypoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Container CMD override.";
          };

          dockerfile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Custom Dockerfile content (overrides auto-generation).";
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
      _: appCfg: (appCfg.deployment.enable or false) && (appCfg.deployment.provider or "fly") == "fly"
    ) apps;

  # ---------------------------------------------------------------------------
  # Generate fly.toml content
  # Uses Dockerfile for building (flyctl handles the build)
  # ---------------------------------------------------------------------------
  mkFlyToml =
    appName: appCfg:
    let
      d = appCfg.deployment;
      f = d.fly;
      c = d.container;
      org = deployCfg.fly.organization or null;

      allEnv = {
        PORT = toString c.port;
      }
      // f.env;
      envSection = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} = '${v}'") allEnv);

      # Dockerfile path - relative from fly.toml location to docker directory
      # fly.toml is at packages/infra/fly/<app>/fly.toml
      # Dockerfile is at packages/infra/docker/<app>/Dockerfile
      # So relative path is ../../docker/<app>/Dockerfile
      dockerfilePath = "../../docker/${appName}/Dockerfile";

      # Organization line (optional)
      orgLine = lib.optionalString (org != null) ''
        org = "${org}"
      '';
    in
    ''
      # Generated by stackpanel - do not edit manually
      # Regenerate by entering the devshell: nix develop --impure
      #
      # Deploy workflow:
      #   flyctl deploy --config ${infraPath}/fly/${appName}/fly.toml
      #
      # Or use npm scripts:
      #   bun run deploy:${appName}

      app = "${f.appName}"
      ${orgLine}
      [build]
      dockerfile = "${dockerfilePath}"

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
        "container:build:${appName}" = "cd ../.. && nix build --impure .#packages.x86_64-linux.container-${appName}";
        # Push container to Fly.io registry (dockerTools + skopeo)
        "container:push:${appName}" = "cd ../.. && nix run --impure .#copy-container-${appName} -- docker://registry.fly.io/ --dest-creds x:$(flyctl auth token)";
        # Deploy to Fly.io (creates app if needed, uses pre-pushed image)
        "deploy:${appName}" = ''cd ../.. && (flyctl status -a ${flyAppName} > /dev/null 2>&1 || flyctl apps create ${flyAppName} ${orgFlag}) && flyctl deploy --config ${infraPath}/fly/${appName}/fly.toml --image registry.fly.io/${flyAppName}:latest'';
        # Full workflow
        "ship:${appName}" = "turbo run deploy:${appName}";
      }
    ) { } deployableApps;

  # ---------------------------------------------------------------------------
  # Turbo tasks per deployable app (with dependency chain)
  # Workflow: build -> container:build -> container:push -> deploy
  # Uses nix2container for building and pushing containers
  # ---------------------------------------------------------------------------
  mkDeployTasks =
    appName: appCfg:
    let
      # Package name from package.json (defaults to app name)
      pkgName =
        if appCfg.packageName or null != null then
          appCfg.packageName
        else
          appCfg.name or appName;
      flyAppName = appCfg.deployment.fly.appName or appName;
    in
    {
      # Build container image (nix2container, uses Linux builder on macOS)
      "container:build:${appName}" = {
        description = "Build ${appName} container (nix2container)";
        cache = false;
        dependsOn = [ "${pkgName}#build" ];
        exec = ''
          echo "📦 Building container image with nix2container..."
          nix build --impure ".#packages.x86_64-linux.container-${appName}"
          echo "✅ Container built: ./result"
        '';
      };
      # Push container to registry (uses dockerTools + skopeo)
      "container:push:${appName}" = {
        description = "Push ${appName} container to Fly.io registry";
        cache = false;
        dependsOn = [ "container:build:${appName}" ];
        exec = ''
          echo "📤 Pushing container to registry.fly.io..."
          nix run --impure ".#copy-container-${appName}" -- \
            "docker://registry.fly.io/" \
            --dest-creds "x:$(flyctl auth token)"
          echo "✅ Container pushed to registry.fly.io/${flyAppName}:latest"
        '';
      };
      # Deploy to Fly.io (uses pre-pushed image)
      "deploy:${appName}" = {
        description = "Deploy ${appName} to Fly.io";
        cache = false;
        dependsOn = [ "container:push:${appName}" ];
        exec = ''
          # Ensure app exists (create if not)
          if ! flyctl status -a ${flyAppName} > /dev/null 2>&1; then
            echo "📱 Creating Fly.io app: ${flyAppName}..."
            flyctl apps create ${flyAppName} ${orgFlag}
          fi

          echo "🚀 Deploying ${appName} to Fly.io..."
          flyctl deploy --config ${infraPath}/fly/${appName}/fly.toml \
            --image "registry.fly.io/${flyAppName}:latest"
          echo "✅ Deployed to Fly.io!"
        '';
      };
      # Ship is the full workflow
      "ship:${appName}" = {
        description = "Build, push, and deploy ${appName} to Fly.io";
        cache = false;
        dependsOn = [ "deploy:${appName}" ];
      };
    };

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
        } // f.env;
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

    defaultProvider = lib.mkOption {
      type = lib.types.enum [ "fly" ];
      default = "fly";
      description = "Default deployment provider.";
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
      # -------------------------------------------------------------------------
      # Contribute containers to stackpanel.containers
      # These are passed to devenv.containers for nix2container builds
      # -------------------------------------------------------------------------
      stackpanel.containers = mkContainerConfigs deployableApps;

      # -------------------------------------------------------------------------
      # Enable Dockerfile generation for Fly apps (docker build fallback)
      # -------------------------------------------------------------------------
      stackpanel.docker.enable = true;
      stackpanel.docker.images = lib.mapAttrs (
        appName: appCfg:
        let
          d = appCfg.deployment;
          c = d.container;
        in
        {
          registry = "registry.fly.io";
          name = d.fly.appName or appName;
          dockerfile = {
            enable = true;
            type = c.type;
            appPath = appCfg.path or "apps/${appName}";
            port = c.port;
            entrypoint = c.entrypoint;
            content = c.dockerfile;
          };
        }
      ) deployableApps;

      # -------------------------------------------------------------------------
      # Merge deploy scripts into SST's packages/infra/package.json
      # -------------------------------------------------------------------------
      stackpanel.sst.package.scripts = mkDeployPackageScripts deployableApps;

      # -------------------------------------------------------------------------
      # Generated Files (fly.toml)
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
      ];

      # -------------------------------------------------------------------------
      # Turbo Tasks
      # -------------------------------------------------------------------------
      stackpanel.tasks = lib.mkMerge (lib.mapAttrsToList mkDeployTasks deployableApps);

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
