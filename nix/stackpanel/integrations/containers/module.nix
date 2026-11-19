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
}@args:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  containersCfg = cfg.containers;
  settingsCfg = containersCfg.settings;
  enabled = cfg.enable && cfg.modules.${meta.id}.enable;

  # Import container library with inputs for nix2container access
  containerLib = import ../../lib/containers.nix {
    inherit lib pkgs inputs;
  };

  # Import schema for SpField definitions
  containerSchema = import ./schema.nix { inherit lib; };
  sp = lib.stackpanel.spField;
  builderTypeOption = (sp.asOption containerSchema.fields.type) // {
    apply =
      id:
      if cfg.containerBuilders ? ${id} then
        id
      else
        throw "stackpanel.containers: unknown container builder '${id}'. Registered builders: ${lib.concatStringsSep ", " (builtins.attrNames cfg.containerBuilders)}";
  };

  # ---------------------------------------------------------------------------
  # Per-app container options (added via appModules)
  # Uses SpField schema for simple fields, manual definitions for complex types
  # ---------------------------------------------------------------------------
  containerAppModule =
    { lib, ... }:
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

        type = builderTypeOption;

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
          example = [
            "bun"
            "run"
            "start"
          ];
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
          example = lib.literalExpression "[ ./public ]";
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
  # ---------------------------------------------------------------------------
  mkContainerFromApp =
    appName: appCfg:
    let
      inherit (appCfg) container;
      appPath = appCfg.path or "apps/${appName}";
    in
    {
      name = if container.name != null then container.name else appName;
      inherit (container)
        version
        type
        port
        startupCommand
        registry
        workingDir
        copyToRoot
        defaultCopyArgs
        env
        maxLayers
        ;
      buildOutputPath =
        if container.buildOutputPath != null then container.buildOutputPath else "${appPath}/.output";
    };

  # ---------------------------------------------------------------------------
  # Build container using selected backend
  # ---------------------------------------------------------------------------
  mkContainerDerivation =
    appName: containerCfg:
    let
      projectRoot =
        if cfg.root != null then
          cfg.root
        else
          throw ''
            stackpanel.containers: cfg.root is not set. Cannot build containers without a project root.

            Normally `stackpanel.root` is set automatically to the flake source
            (`toString self`) by the stackpanel flake module. If you're calling
            `lib.evalModules` directly, set it explicitly:

              stackpanel.root = toString self;
          '';
    in
    containerLib.mkContainer (
      containerCfg
      // {
        inherit appName projectRoot;
        inherit (settingsCfg) backend;
        app = appsWithContainers.${appName} or null;
        builders = cfg.containerBuilders;
        registry =
          if containerCfg.registry == null then settingsCfg.defaultRegistry else containerCfg.registry;
        buildOutputPath =
          if containerCfg.buildOutputPath == null then
            "apps/${appName}/.output"
          else
            containerCfg.buildOutputPath;
      }
    );

  # ---------------------------------------------------------------------------
  # Per-app .tasks/bin/ scripts for container-build and container-push
  # These are generated for ALL apps with containers enabled, regardless of
  # deployment host (the Fly module only generates deploy scripts).
  # ---------------------------------------------------------------------------
  mkContainerScriptDerivations = appName: _appCfg: {
    # `STACKPANEL_ROOT_ABSOLUTE` is read by `lib/containers.nix:mkAppDir` so
    # the build can pull `apps/<app>/.output` straight from the working tree
    # — `.output` is gitignored, so it isn't in the flake's store copy.
    "container-build" = pkgs.writeShellScriptBin "container-build" ''
      set -euo pipefail
      ROOT="''${STACKPANEL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
      cd "$ROOT"
      export STACKPANEL_ROOT_ABSOLUTE="''${STACKPANEL_ROOT_ABSOLUTE:-$ROOT}"
      echo "📦 Building container for ${appName}..."
      nix build --impure ".#packages.x86_64-linux.container-${appName}"
      echo "✅ Container built: ./result"
    '';

    "container-push" = pkgs.writeShellScriptBin "container-push" ''
      set -euo pipefail
      ROOT="''${STACKPANEL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
      cd "$ROOT"
      export STACKPANEL_ROOT_ABSOLUTE="''${STACKPANEL_ROOT_ABSOLUTE:-$ROOT}"
      echo "📤 Pushing container for ${appName}..."
      nix run --impure ".#copy-container-${appName}"
      echo "✅ Container pushed"
    '';
  };

  mkContainerFileEntries =
    appName: appCfg:
    let
      scripts = mkContainerScriptDerivations appName appCfg;
      appPath = appCfg.path or "apps/${appName}";
    in
    lib.mapAttrs' (scriptName: scriptDrv: {
      name = "${appPath}/.tasks/bin/${scriptName}";
      value = {
        format = "symlink";
        target = "${scriptDrv}/bin/${scriptName}";
        source = meta.id;
        module = meta.id;
        description = "Container script: ${scriptName} for ${appName}";
      };
    }) scripts;

  # Build all outputs
  containerResults = lib.mapAttrs mkContainerDerivation containersCfg.images;

  # Extract derivations and scripts
  containerDerivations = lib.mapAttrs (_: r: r.container) containerResults;
  copyScripts = lib.mapAttrs (_: r: r.copyScript) containerResults;

  # Only the copy script is optional (e.g. a build-only custom provider).
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
        example = "nix2container";
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
        example = "docker://ghcr.io/darkmatter/";
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
                example = "stackpanel-web";
              };

              version = lib.mkOption {
                type = lib.types.str;
                default = "latest";
                description = "Container image tag/version.";
                example = "2026-06-18";
              };

              type = builderTypeOption;

              port = lib.mkOption {
                type = lib.types.int;
                default = 3000;
                description = "Port the app listens on.";
                example = 3000;
              };

              buildOutputPath = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Path to pre-built output (relative to project root).";
                example = "apps/web/.output";
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
                example = lib.literalExpression "[ ./public ]";
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
                example = [
                  "bun"
                  "run"
                  "start"
                ];
              };

              workingDir = lib.mkOption {
                type = lib.types.str;
                default = "/app";
                description = "Working directory inside the container.";
                example = "/app";
              };

              registry = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  Registry to push to. When null, uses settings.defaultRegistry.
                '';
                example = "docker://registry.fly.io/";
              };

              defaultCopyArgs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Default arguments to pass to skopeo copy.";
                example = [
                  "--dest-cert-dir"
                  "/etc/containers/certs.d/registry"
                ];
              };

              env = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "Environment variables for the container.";
                example = {
                  NODE_ENV = "production";
                };
              };

              maxLayers = lib.mkOption {
                type = lib.types.int;
                default = 100;
                description = "Maximum layers for nix2container (ignored for dockerTools).";
                example = 100;
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
      example = {
        web = {
          name = "stackpanel-web";
          type = "bun";
          port = 3000;
          registry = "docker://ghcr.io/darkmatter/";
        };
      };
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
  config = lib.mkMerge [
    # Keep schemas and built-in provider IDs discoverable without building images.
    {
      stackpanel.appModules = [ containerAppModule ];
      stackpanel.containerBuilders = containerLib.builtinBuilders;
      stackpanel.lazyNamespaces = [ "containersComputed" ];
    }

    # Generate containers from apps with container.enable = true
    (lib.mkIf enabled {
      stackpanel.containers.images = lib.mapAttrs mkContainerFromApp appsWithContainers;
    })

    # When we have containers and the required inputs
    (lib.mkIf (enabled && !(args.isGlobalEval or false) && pkgs != null && containersCfg.images != { })
      {
        # Computed outputs for flake exposure
        stackpanel.containersComputed = {
          images = containerDerivations;
          copyScripts = validCopyScripts;
          inherit (settingsCfg) backend;
        };

        # Add container helper scripts
        # Note: --impure is required because we read local build output from filesystem
        stackpanel.scripts = {
          container-build = {
            module = meta.id;
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
                echo "Prepare any app output required by the selected image builder first."
                exit 1
              fi
              echo "📦 Building Linux container (${settingsCfg.backend})..."
              nix build --impure ".#packages.x86_64-linux.container-$1" "''${@:2}"
              echo "✅ Container built: ./result"
            '';
          };

          container-copy = {
            module = meta.id;
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
                echo "Prepare any app output required by the selected image builder first."
                exit 1
              fi
              NAME="$1"
              shift
              echo "📦 Building and pushing Linux container..."
              nix run --impure ".#copy-container-$NAME" -- "$@"
            '';
          };

          container-run = {
            module = meta.id;
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
                echo "Prepare any app output required by the selected image builder first."
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
            module = meta.id;
            description = "Show container configuration info";
            exec = ''
              echo "Container Configuration"
              echo "======================="
              echo ""
              echo "Backend: ${settingsCfg.backend}"
              echo "Default Registry: ${settingsCfg.defaultRegistry}"
              echo ${lib.escapeShellArg "Registered builders: ${lib.concatStringsSep ", " (builtins.attrNames cfg.containerBuilders)}"}
              echo ""
              echo "Available Containers:"
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  name: img:
                  "echo ${lib.escapeShellArg "  - ${name} (type: ${img.type}, port: ${toString img.port})"}"
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

        # Generate .tasks/bin/ scripts for each app with containers
        stackpanel.files.entries = lib.mkMerge (
          lib.mapAttrsToList mkContainerFileEntries appsWithContainers
        );

        # Add skopeo to devshell
        stackpanel.modulePackages.${meta.id} = [ pkgs.skopeo ];
      }
    )

    # Module registration
    {
      stackpanel.modules.${meta.id} = {
        enable = lib.mkDefault true;
        meta = {
          inherit (meta) name;
          inherit (meta) description;
          inherit (meta) icon;
          inherit (meta) category;
          inherit (meta) author;
          inherit (meta) version;
          inherit (meta) homepage;
        };
        source.type = "builtin";
        inherit (meta) features;
        inherit (meta) tags;
        inherit (meta) priority;
      };
    }
  ];
}
