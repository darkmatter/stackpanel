# ==============================================================================
# module.nix - Containers Module
#
# Builds Linux containers using either:
#   1. nix2container (DEFAULT) - efficient layer caching, streaming pushes
#   2. dockerTools.buildImage - reliable cross-platform builds
#
# Usage:
#   # Global backend selection (applies to all containers)
#   stackpanel.containers.settings.backend = "nix2container"; # or "dockerTools"
#
#   # Per-app container configuration
#   stackpanel.apps.web.container = {
#     enable = true;
#     type = "bun";
#     port = 3000;
#     registry = "docker://registry.fly.io/";
#   };
#
#   # Or direct container definition
#   stackpanel.containers.images.web = {
#     name = "my-web-app";
#     startupCommand = "bun run dist/server/index.js";
#     registry = "docker://registry.fly.io/";
#   };
#
# Build and push (from devshell):
#   container-build web           # Build container image
#   container-copy web            # Build + push to registry
#   container-run web             # Build + run locally
#
# ==============================================================================
{
  lib,
  config,
  pkgs ? null,
  inputs ? null,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  containersCfg = cfg.containers;
  settingsCfg = containersCfg.settings;

  # Import container library with inputs for nix2container access
  containerLib = import ../lib/containers.nix {
    inherit lib pkgs inputs;
  };

  # Import schema for SpField definitions
  containerSchema = import ./schema.nix { inherit lib; };
  sp = import ../db/lib/field.nix { inherit lib; };

  # ---------------------------------------------------------------------------
  # Per-app container options (added via appModules)
  # Uses SpField schema for simple fields, manual definitions for complex types
  # ---------------------------------------------------------------------------
  containerAppModule =
    { lib, name, ... }:
    {
      options.container = {
        # Simple fields from schema (auto-converted via sp.asOption)
        enable = sp.asOption containerSchema.fields.enable;
        name = sp.asOption containerSchema.fields.name;
        version = sp.asOption containerSchema.fields.version;
        port = sp.asOption containerSchema.fields.port;
        registry = sp.asOption containerSchema.fields.registry;
        workingDir = sp.asOption containerSchema.fields.workingDir;
        buildOutputPath = sp.asOption containerSchema.fields.buildOutputPath;
        maxLayers = sp.asOption containerSchema.fields.maxLayers;
        defaultCopyArgs = sp.asOption containerSchema.fields.defaultCopyArgs;
        env = sp.asOption containerSchema.fields.env;

        # Override type to use enum for strict validation in Nix
        # (SpField generates string type, but we want enum validation)
        type = lib.mkOption {
          type = lib.types.enum [
            "bun"
            "node"
            "go"
            "static"
            "custom"
          ];
          default = "bun";
          description = "App type determines the base image and startup command.";
        };

        # Complex types that SpField doesn't support - manual definitions
        startupCommand = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.oneOf [
              lib.types.str
              (lib.types.listOf lib.types.str)
            ]
          );
          default = null;
          description = "Custom startup command. When null, auto-detected based on type.";
        };

        copyToRoot = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.oneOf [
              lib.types.path
              (lib.types.listOf lib.types.path)
            ]
          );
          default = null;
          description = "Additional paths to copy to the container root.";
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Filter apps with container.enable = true
  # ---------------------------------------------------------------------------
  appsWithContainers = lib.filterAttrs (_name: appCfg: (appCfg.container.enable or false)) (
    cfg.apps or { }
  );

  # ---------------------------------------------------------------------------
  # Generate container config from app config
  # Reads deployment.fly.* settings when deployment is enabled for Fly.io
  # ---------------------------------------------------------------------------
  mkContainerFromApp =
    appName: appCfg:
    let
      container = appCfg.container;
      appPath = appCfg.path or "apps/${appName}";

      # Check if Fly.io deployment is enabled for this app
      deployment = appCfg.deployment or { };
      isFlyDeployment = (deployment.enable or false) && (deployment.provider or "cloudflare") == "fly";
      flyConfig = deployment.fly or { };

      # Fly-specific overrides
      flyRegistry = "docker://registry.fly.io/";
      flyCopyArgs = [
        "--dest-creds"
        "x:$(flyctl auth token)"
      ];
      flyAppName = flyConfig.appName or appName;
      flyEnv = flyConfig.env or { };
    in
    {
      # Use fly appName if fly deployment is enabled, otherwise container.name or appName
      name =
        if isFlyDeployment then flyAppName
        else if container.name != null then container.name
        else appName;
      version = container.version;
      type = container.type;
      port = container.port;
      startupCommand = container.startupCommand;
      # Use fly registry if fly deployment is enabled
      registry = if isFlyDeployment then flyRegistry else container.registry;
      workingDir = container.workingDir;
      buildOutputPath =
        if container.buildOutputPath != null then container.buildOutputPath else "${appPath}/.output";
      copyToRoot = container.copyToRoot;
      # Use fly auth args if fly deployment is enabled
      defaultCopyArgs = if isFlyDeployment then flyCopyArgs else container.defaultCopyArgs;
      # Merge fly env with container env
      env = container.env // (if isFlyDeployment then flyEnv else { });
      maxLayers = container.maxLayers;
    };

  # ---------------------------------------------------------------------------
  # Build container using selected backend
  # ---------------------------------------------------------------------------
  mkContainerDerivation =
    appName: containerCfg:
    let
      projectRoot = cfg.root or (builtins.getEnv "PWD");
      backend = settingsCfg.backend;
      # Use containerCfg.name for the actual image name (e.g., stackpanel-web)
      # The appName (attrset key, e.g., web) is only used for fallback paths
      imageName = containerCfg.name or appName;

      result = containerLib.mkContainer {
        name = imageName;
        inherit
          backend
          projectRoot
          ;
        version = containerCfg.version or "latest";
        type = containerCfg.type or "bun";
        port = containerCfg.port or 3000;
        buildOutputPath = containerCfg.buildOutputPath or "apps/${appName}/.output";
        workingDir = containerCfg.workingDir or "/app";
        startupCommand = containerCfg.startupCommand or null;
        copyToRoot = containerCfg.copyToRoot or null;
        env = containerCfg.env or { };
        maxLayers = containerCfg.maxLayers or 100;
        registry = containerCfg.registry or settingsCfg.defaultRegistry;
        defaultCopyArgs = containerCfg.defaultCopyArgs or [ ];
      };
    in
    result;

  # Build all outputs
  containerResults = lib.mapAttrs mkContainerDerivation containersCfg.images;

  # Extract derivations and scripts
  containerDerivations = lib.mapAttrs (_: r: r.container) containerResults;
  copyScripts = lib.mapAttrs (_: r: r.copyScript) containerResults;

  # Filter out nulls
  validDerivations = lib.filterAttrs (_: v: v != null) containerDerivations;
  validCopyScripts = lib.filterAttrs (_: v: v != null) copyScripts;

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.containers = {
    # Global settings
    settings = {
      backend = lib.mkOption {
        type = lib.types.enum [
          "nix2container"
          "dockerTools"
        ];
        default = "nix2container";
        description = ''
          Container building backend to use:
          - nix2container (default): Efficient layer caching, streaming pushes
          - dockerTools: Reliable cross-platform builds, no external dependencies
        '';
      };

      defaultRegistry = lib.mkOption {
        type = lib.types.str;
        default = "docker-daemon:";
        description = ''
          Default registry for containers. Examples:
          - "docker-daemon:" (local Docker)
          - "docker://registry.fly.io/"
          - "docker://ghcr.io/org/"
        '';
      };
    };

    # Container image definitions
    images = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "Container image name.";
              };

              version = lib.mkOption {
                type = lib.types.str;
                default = "latest";
                description = "Container image tag/version.";
              };

              type = lib.mkOption {
                type = lib.types.enum [
                  "bun"
                  "node"
                  "go"
                  "static"
                  "custom"
                ];
                default = "bun";
                description = "App type for base image and startup command defaults.";
              };

              port = lib.mkOption {
                type = lib.types.int;
                default = 3000;
                description = "Port the app listens on.";
              };

              buildOutputPath = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Path to pre-built output (relative to project root).";
              };

              copyToRoot = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.oneOf [
                    lib.types.path
                    (lib.types.listOf lib.types.path)
                  ]
                );
                default = null;
                description = "Additional paths to copy to container root.";
              };

              startupCommand = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.oneOf [
                    lib.types.str
                    lib.types.package
                    (lib.types.listOf lib.types.str)
                  ]
                );
                default = null;
                description = "Command to run in the container.";
              };

              workingDir = lib.mkOption {
                type = lib.types.str;
                default = "/app";
                description = "Working directory inside the container.";
              };

              registry = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  Registry to push to. When null, uses settings.defaultRegistry.
                '';
              };

              defaultCopyArgs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Default arguments to pass to skopeo copy.
                  For Fly.io auth: [ "--dest-creds" "x:$(flyctl auth token)" ]
                '';
              };

              env = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "Environment variables for the container.";
              };

              maxLayers = lib.mkOption {
                type = lib.types.int;
                default = 100;
                description = "Maximum layers for nix2container (ignored for dockerTools).";
              };
            };
          }
        )
      );
      default = { };
      description = ''
        Container image definitions.

        Build and push:
          container-build <name>   # Build container image
          container-copy <name>    # Build + push to registry
          container-run <name>     # Build + run locally
      '';
    };
  };

  # Computed outputs
  options.stackpanel.containersComputed = {
    images = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      internal = true;
      description = "Built container images.";
    };

    copyScripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      internal = true;
      description = "Copy/push scripts for each container.";
    };

    backend = lib.mkOption {
      type = lib.types.str;
      default = "nix2container";
      internal = true;
      description = "Active container backend.";
    };
  };

  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Always register appModule
      {
        stackpanel.appModules = [ containerAppModule ];
      }

      # Generate containers from apps with container.enable = true
      (lib.mkIf (appsWithContainers != { }) {
        stackpanel.containers.images = lib.mapAttrs mkContainerFromApp appsWithContainers;
      })

      # When we have containers and the required inputs
      (lib.mkIf (containersCfg.images != { } && containerLib.hasDockerTools) {
        # Computed outputs for flake exposure
        stackpanel.containersComputed = {
          images = validDerivations;
          copyScripts = validCopyScripts;
          backend = settingsCfg.backend;
        };

        # Add container helper scripts
        # Note: --impure is required because we read local build output from filesystem
        stackpanel.scripts = {
          container-build = {
            description = "Build a container image (${settingsCfg.backend})";
            args = [
              {
                name = "container-name";
                description = "Name of the container to build";
                required = true;
              }
              {
                name = "...";
                description = "Additional nix build arguments";
              }
            ];
            exec = ''
              if [ $# -eq 0 ]; then
                echo "Usage: container-build <container-name>"
                echo "Available containers: ${lib.concatStringsSep ", " (lib.attrNames containersCfg.images)}"
                echo ""
                echo "Backend: ${settingsCfg.backend}"
                echo "Make sure to build your app first: bun run build"
                exit 1
              fi
              echo "📦 Building Linux container (${settingsCfg.backend})..."
              nix build --impure ".#packages.x86_64-linux.container-$1" "''${@:2}"
              echo "✅ Container built: ./result"
            '';
          };

          container-copy = {
            description = "Build and push a container to registry";
            args = [
              {
                name = "container-name";
                description = "Name of the container to copy";
                required = true;
              }
              {
                name = "registry";
                description = "Target registry (e.g., docker://registry.fly.io/)";
              }
            ];
            exec = ''
              if [ $# -eq 0 ]; then
                echo "Usage: container-copy <container-name> [registry]"
                echo "Available containers: ${lib.concatStringsSep ", " (lib.attrNames containersCfg.images)}"
                echo ""
                echo "Backend: ${settingsCfg.backend}"
                echo "Make sure to build your app first: bun run build"
                exit 1
              fi
              NAME="$1"
              shift
              echo "📦 Building and pushing Linux container..."
              nix run --impure ".#copy-container-$NAME" -- "$@"
            '';
          };

          container-run = {
            description = "Run container locally (Docker or Apple container)";
            args = [
              {
                name = "container-name";
                description = "Name of the container to run";
                required = true;
              }
              {
                name = "...";
                description = "Arguments passed to the container";
              }
            ];
            exec = ''
              if [ $# -eq 0 ]; then
                echo "Usage: container-run <container-name> [args...]"
                echo "Available containers: ${lib.concatStringsSep ", " (lib.attrNames containersCfg.images)}"
                echo ""
                echo "Backend: ${settingsCfg.backend}"
                echo "Make sure to build your app first: bun run build"
                exit 1
              fi
              NAME="$1"
              shift

              # Check for Apple's container tool (macOS native)
              if command -v container &> /dev/null && [[ "$(uname)" == "Darwin" ]]; then
                echo "🍎 Using Apple container (native macOS)"
                nix run --impure ".#copy-container-$NAME" -- docker-daemon:
                container run -it "$NAME:latest" "$@"
              elif command -v docker &> /dev/null; then
                echo "🐳 Using Docker"
                nix run --impure ".#copy-container-$NAME" -- docker-daemon:
                if [ -t 0 ]; then
                  docker run -it "$NAME:latest" "$@"
                else
                  docker run -i "$NAME:latest" "$@"
                fi
              else
                echo "❌ No container runtime found!"
                echo ""
                echo "Install one of:"
                if [[ "$(uname)" == "Darwin" ]]; then
                  echo "  - Apple container: brew install --cask container"
                fi
                echo "  - Docker Desktop: https://www.docker.com/products/docker-desktop"
                exit 1
              fi
            '';
          };

          container-info = {
            description = "Show container configuration info";
            exec = ''
              echo "Container Configuration"
              echo "======================="
              echo ""
              echo "Backend: ${settingsCfg.backend}"
              echo "Default Registry: ${settingsCfg.defaultRegistry}"
              echo ""
              echo "Available Containers:"
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  name: img: ''echo "  - ${name} (type: ${img.type}, port: ${toString img.port})"''
                ) containersCfg.images
              )}
              echo ""
              echo "Commands:"
              echo "  container-build <name>   Build a container"
              echo "  container-copy <name>    Build + push to registry"
              echo "  container-run <name>     Build + run locally"
            '';
          };
        };

        # Add skopeo to devshell
        stackpanel.devshell.packages = lib.optionals (pkgs != null) [
          pkgs.skopeo
        ];
      })

      # Module registration
      {
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
      }
    ]
  );
}
