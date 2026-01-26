# ==============================================================================
# module.nix - Fly.io Deployment Module Implementation
#
# Provides Fly.io deployment support for stackpanel apps.
#
# This module:
#   1. Adds deployment.* options to each app via appModules
#   2. Generates fly.toml and deploy scripts into packages/infra/fly/
#   3. Generates packages/infra/package.json for turbo integration
#   4. Creates turbo tasks for the deploy pipeline
#   5. Builds nix2container images (available via flake outputs)
#
# Generated layout:
#   packages/infra/
#   ├── package.json           # Workspace package with deploy scripts
#   ├── turbo.json             # Per-package turbo config
#   └── fly/
#       ├── lib/
#       │   └── deploy.sh      # Shared deploy functions
#       └── <appName>/
#           ├── fly.toml        # Fly.io configuration
#           └── deploy.sh       # Full deploy pipeline script
#
# Usage:
#   stackpanel.apps.web = {
#     path = "apps/web";
#     deployment = {
#       enable = true;
#       provider = "fly";
#       fly = {
#         appName = "my-app";
#         region = "iad";
#       };
#       container = {
#         type = "bun";
#         port = 3000;
#       };
#     };
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs,
  inputs ? { },
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  deployCfg = cfg.deployment;

  # ---------------------------------------------------------------------------
  # Per-app deployment options module (added via appModules)
  # ---------------------------------------------------------------------------
  deploymentAppModule =
    { lib, name, ... }:
    {
      options.deployment = {
        enable = lib.mkEnableOption "deployment for this app";

        provider = lib.mkOption {
          type = lib.types.enum [ "fly" ];
          default = deployCfg.defaultProvider or "fly";
          description = "Deployment provider to use.";
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
            example = {
              NODE_ENV = "production";
              LOG_LEVEL = "info";
            };
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
            description = "App type determines build strategy and base image.";
          };

          port = lib.mkOption {
            type = lib.types.int;
            default = 3000;
            description = "Internal port the app listens on.";
          };

          buildCommand = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Custom build command (for type=custom or override).";
          };

          entrypoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Container entrypoint override.";
          };

          aws = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable AWS credentials via Fly OIDC.";
            };

            chamberService = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Chamber service for secrets (e.g., myapp/prod).";
              example = "myapp/prod";
            };
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
  # ---------------------------------------------------------------------------
  mkFlyToml =
    appName: appCfg:
    let
      d = appCfg.deployment;
      f = d.fly;
      c = d.container;

      # Base environment variables
      baseEnv = {
        PORT = toString c.port;
      };

      # AWS environment if enabled
      awsEnv = lib.optionalAttrs (c.aws.enable && cfg.sst.enable or false) {
        AWS_ROLE_ARN = cfg.sst.iam.role-arn or ""; # Will be filled by SST
      };

      # Merge all env vars
      allEnv = baseEnv // awsEnv // f.env;

      # Format env vars for TOML
      envSection = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} = '${v}'") allEnv);
    in
    ''
      # Generated by stackpanel - do not edit manually
      # Regenerate by entering the devshell: nix develop --impure

      app = "${f.appName}"

      [build]
      image = "registry.fly.io/${f.appName}:latest"

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
  # Generate build command based on app type
  # ---------------------------------------------------------------------------
  mkBuildCommand =
    appCfg:
    let
      c = appCfg.deployment.container;
    in
    if c.buildCommand != null then
      c.buildCommand
    else if c.type == "bun" then
      "bun run build"
    else if c.type == "node" then
      "npm run build"
    else if c.type == "go" then
      "go build -o ./server ."
    else if c.type == "static" then
      "echo 'Static site - no build needed'"
    else
      "echo 'Custom type - please specify buildCommand'";

  # ---------------------------------------------------------------------------
  # Generate deploy scripts
  # ---------------------------------------------------------------------------
  # ---------------------------------------------------------------------------
  # Infra package path constant
  # ---------------------------------------------------------------------------
  infraPath = "packages/infra";

  mkDeployLibSh = ''
    #!/usr/bin/env bash
    # ==============================================================================
    # deploy.sh - Shared functions for stackpanel Fly.io deployment
    # Generated by stackpanel - do not edit manually
    # ==============================================================================

    # Source common library (from packages/scripts if available)
    DEPLOY_SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"
    DEPLOY_LIB_DIR="$DEPLOY_SCRIPT_DIR"

    _SCRIPTS_COMMON="$(cd "$DEPLOY_SCRIPT_DIR/../../scripts/lib" 2>/dev/null && pwd)/common.sh"
    if [[ -f "$_SCRIPTS_COMMON" ]]; then
      source "$_SCRIPTS_COMMON"
    else
      # Minimal fallback logging if common.sh is not available
      log_info()  { echo "[INFO]  $*" >&2; }
      log_error() { echo "[ERROR] $*" >&2; }
      log_warn()  { echo "[WARN]  $*" >&2; }
      log_debug() { [[ "''${DEBUG:-}" == "1" ]] && echo "[DEBUG] $*" >&2; }
    fi
    unset _SCRIPTS_COMMON

    # Find project root
    find_deploy_root() {
      local dir="''${1:-$(pwd)}"
      if [[ -n "''${STACKPANEL_ROOT:-}" ]] && [[ -d "$STACKPANEL_ROOT" ]]; then
        echo "$STACKPANEL_ROOT"; return 0
      fi
      while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/flake.nix" ]]; then echo "$dir"; return 0; fi
        dir=$(dirname "$dir")
      done
      return 1
    }

    # Clean build artifacts for an app
    clean_build_artifacts() {
      local app_name="$1"
      local project_root
      project_root=$(find_deploy_root) || { log_error "Could not find project root"; return 1; }

      log_info "Cleaning build artifacts for $app_name..."
      rm -rf "$project_root/apps/$app_name/.output"
      rm -rf "$project_root/apps/$app_name/dist"
      log_info "Clean complete"
    }

    # Build app for deployment
    build_app() {
      local app_name="$1"
      local environment="''${2:-prod}"
      local project_root
      project_root=$(find_deploy_root) || { log_error "Could not find project root"; return 1; }

      log_info "Building $app_name for $environment..."

      # Source entrypoint for environment
      local entrypoint="$project_root/packages/scripts/entrypoints/$app_name.sh"
      if [[ -f "$entrypoint" ]]; then
        source "$entrypoint" --env "$environment"
      fi

      cd "$project_root/apps/$app_name"

      if [[ -f "package.json" ]]; then
        if command -v bun &>/dev/null; then bun run build; else npm run build; fi
      elif [[ -f "go.mod" ]]; then
        go build -o ./server .
      else
        log_warn "Unknown build type for $app_name"
      fi

      log_info "Build complete"
    }

    # Push container to Fly.io registry
    push_container() {
      local app_name="$1"
      local fly_app_name="''${2:-$app_name}"
      local project_root
      project_root=$(find_deploy_root) || { log_error "Could not find project root"; return 1; }

      log_info "Building and pushing container for $app_name..."

      local image_path
      image_path=$(nix build --impure --no-link --print-out-paths \
        "$project_root#containers.$app_name" 2>/dev/null) || {
        log_error "Failed to build container. Make sure nix2container is configured."
        return 1
      }

      local fly_token
      fly_token=$(flyctl auth token 2>/dev/null) || {
        log_error "Not logged in to Fly.io. Run 'flyctl auth login' first."
        return 1
      }

      log_info "Pushing to registry.fly.io/$fly_app_name:latest..."
      skopeo copy \
        --insecure-policy \
        --dest-creds="x:$fly_token" \
        "nix:$image_path" \
        "docker://registry.fly.io/$fly_app_name:latest"

      log_info "Push complete"
    }

    # Deploy to Fly.io
    deploy_to_fly() {
      local app_name="$1"
      local fly_app_name="''${2:-$app_name}"
      local project_root
      project_root=$(find_deploy_root) || { log_error "Could not find project root"; return 1; }

      local fly_toml="$project_root/${infraPath}/fly/$app_name/fly.toml"

      if [[ ! -f "$fly_toml" ]]; then
        log_error "fly.toml not found at $fly_toml"
        return 1
      fi

      log_info "Deploying $fly_app_name to Fly.io..."
      flyctl deploy --app "$fly_app_name" --config "$fly_toml"

      log_info "Deploy complete! App available at https://$fly_app_name.fly.dev/"
    }
  '';

  mkDeployScript = appName: appCfg: ''
    #!/usr/bin/env bash
    # ==============================================================================
    # Deploy script for ${appName}
    # Generated by stackpanel - do not edit manually
    # ==============================================================================
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../lib/deploy.sh"

    APP_NAME="${appName}"
    FLY_APP_NAME="${appCfg.deployment.fly.appName}"
    STAGE="''${1:-prod}"

    echo ""
    echo "=================================================="
    echo "  Deploying $APP_NAME to Fly.io ($STAGE)"
    echo "=================================================="
    echo ""

    clean_build_artifacts "$APP_NAME"
    build_app "$APP_NAME" "$STAGE"
    push_container "$APP_NAME" "$FLY_APP_NAME"
    deploy_to_fly "$APP_NAME" "$FLY_APP_NAME"

    echo ""
    echo "=================================================="
    echo "  Deploy complete!"
    echo "  https://$FLY_APP_NAME.fly.dev/"
    echo "=================================================="
  '';

  # ---------------------------------------------------------------------------
  # Deploy script entries for packages/infra/package.json
  # Merged into the SST-generated package.json via stackpanel.sst.package.scripts
  # ---------------------------------------------------------------------------
  mkDeployPackageScripts =
    deployableApps:
    let
      # Full pipeline: "deploy:<app>" -> "./fly/<app>/deploy.sh"
      pipelineScripts = lib.listToAttrs (
        lib.mapAttrsToList (appName: _: {
          name = "deploy:${appName}";
          value = "./fly/${appName}/deploy.sh";
        }) deployableApps
      );

      # Individual step scripts via turbo task symlinks
      stepScripts = lib.foldlAttrs (
        acc: appName: _:
        acc
        // {
          "deploy:${appName}:clean" = "./.tasks/bin/deploy:${appName}:clean";
          "deploy:${appName}:build" = "./.tasks/bin/deploy:${appName}:build";
          "deploy:${appName}:push" = "./.tasks/bin/deploy:${appName}:push";
        }
      ) { } deployableApps;
    in
    pipelineScripts // stepScripts;

  # ---------------------------------------------------------------------------
  # Generate packages/infra/turbo.json
  # ---------------------------------------------------------------------------
  mkInfraTurboJson =
    deployableApps:
    let
      deployTasks = lib.foldlAttrs (
        acc: appName: _:
        acc
        // {
          "deploy:${appName}" = {
            dependsOn = [ "deploy:${appName}:push" ];
            cache = false;
          };
          "deploy:${appName}:clean" = {
            cache = false;
          };
          "deploy:${appName}:build" = {
            dependsOn = [ "deploy:${appName}:clean" ];
            outputs = [ "../../apps/${appName}/.output/**" ];
          };
          "deploy:${appName}:push" = {
            dependsOn = [ "deploy:${appName}:build" ];
            cache = false;
          };
        }
      ) { } deployableApps;
    in
    builtins.toJSON {
      extends = [ "//" ];
      tasks = deployTasks;
    };

  # ---------------------------------------------------------------------------
  # Generate turbo tasks for deployment
  # ---------------------------------------------------------------------------
  mkDeployTasks =
    appName: appCfg:
    let
      appPath = appCfg.path or "apps/${appName}";
      buildCmd = mkBuildCommand appCfg;
      flyAppName = appCfg.deployment.fly.appName;
      flyTomlPath = "${infraPath}/fly/${appName}/fly.toml";
    in
    {
      "deploy:${appName}:clean" = {
        exec = ''
          rm -rf "$STACKPANEL_ROOT/${appPath}/.output"
          rm -rf "$STACKPANEL_ROOT/${appPath}/dist"
          echo "Cleaned ${appName} build artifacts"
        '';
        description = "Clean ${appName} build output";
        runtimeInputs = [ pkgs.coreutils ];
      };

      "deploy:${appName}:build" = {
        exec = ''
          cd "$STACKPANEL_ROOT/${appPath}"
          ${buildCmd}
        '';
        description = "Build ${appName} for deployment";
        dependsOn = [ "deploy:${appName}:clean" ];
        runtimeInputs = [
          pkgs.bun
          pkgs.nodejs
        ];
      };

      "deploy:${appName}:push" = {
        exec = ''
          cd "$STACKPANEL_ROOT"

          # Build container
          echo "Building container for ${appName}..."
          IMAGE_PATH=$(nix build --impure --no-link --print-out-paths \
            ".#containers.${appName}")

          # Get Fly auth token
          FLY_TOKEN=$(${lib.getExe pkgs.flyctl} auth token)

          # Push via skopeo
          echo "Pushing to registry.fly.io/${flyAppName}:latest..."
          ${pkgs.skopeo}/bin/skopeo copy \
            --insecure-policy \
            --dest-creds="x:$FLY_TOKEN" \
            "nix:$IMAGE_PATH" \
            "docker://registry.fly.io/${flyAppName}:latest"
        '';
        description = "Push ${appName} container to Fly.io registry";
        dependsOn = [ "deploy:${appName}:build" ];
        runtimeInputs = [
          pkgs.flyctl
          pkgs.skopeo
        ];
      };

      "deploy:${appName}" = {
        exec = ''
          echo "Deploying ${flyAppName} to Fly.io..."
          ${lib.getExe pkgs.flyctl} deploy \
            --app ${flyAppName} \
            --config "$STACKPANEL_ROOT/${flyTomlPath}"
          echo "Deploy complete! https://${flyAppName}.fly.dev/"
        '';
        description = "Deploy ${appName} to Fly.io";
        dependsOn = [ "deploy:${appName}:push" ];
        runtimeInputs = [ pkgs.flyctl ];
      };
    };

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

    container = {
      registry = lib.mkOption {
        type = lib.types.str;
        default = "registry.fly.io";
        description = "Container registry URL.";
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
      # Merge deploy scripts into SST's packages/infra/package.json
      # -------------------------------------------------------------------------
      stackpanel.sst.package.scripts = mkDeployPackageScripts deployableApps;

      # -------------------------------------------------------------------------
      # Generated Files (all under packages/infra/fly/)
      # -------------------------------------------------------------------------
      stackpanel.files.entries = lib.mkMerge [
        # packages/infra/turbo.json (per-package turbo config for deploy tasks)
        {
          "${infraPath}/turbo.json" = {
            type = "text";
            text = mkInfraTurboJson deployableApps;
            source = meta.id;
            description = "Per-package turbo config for deploy tasks";
          };
        }

        # packages/infra/fly/lib/deploy.sh
        {
          "${infraPath}/fly/lib/deploy.sh" = {
            type = "text";
            mode = "0755";
            text = mkDeployLibSh;
            source = meta.id;
            description = "Shared Fly.io deployment functions";
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

        # packages/infra/fly/<appName>/deploy.sh
        (lib.mapAttrs' (appName: appCfg: {
          name = "${infraPath}/fly/${appName}/deploy.sh";
          value = {
            type = "text";
            mode = "0755";
            text = mkDeployScript appName appCfg;
            source = meta.id;
            description = "Deploy script for ${appName}";
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
        pkgs.skopeo
      ];

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

          skopeo-installed = {
            description = "Skopeo is installed for container pushing";
            script = ''
              command -v skopeo >/dev/null 2>&1 && skopeo --version
            '';
            severity = "critical";
            timeout = 5;
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
