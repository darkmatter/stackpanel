# ==============================================================================
# module.nix - Containers Module
#
# Builds Linux containers using either:
#   1. dockerTools.buildImage (DEFAULT) - reliable cross-platform builds
#   2. nix2container.buildImage - more efficient layers, but has issues
#
# Build strategy:
# - Build the web app on macOS (impure, using local bun/turbo)
# - The dist directory is then copied into a linux container
# - Uses the Linux remote builder on macOS
#
# Usage:
#   stackpanel.containers.web = {
#     name = "my-web-app";
#     startupCommand = "bun run dist/server/index.js";
#     registry = "docker://registry.fly.io/";
#   };
#
# Build and push (from devshell):
#   container-build web           # Build container image
#   container-copy web            # Build + push to registry
#   container-run web             # Build + run in Docker
#
# ==============================================================================
# KNOWN ISSUES WITH NIX2CONTAINER:
# ==============================================================================
# 1. skopeo-nix2container build fails on Linux builders:
#    Error: "cd: vendor/go.podman.io/image/v5: No such file or directory"
#    The upstream nix2container flake has a broken skopeo derivation.
#    See: https://github.com/nlewo/nix2container/issues/XXX
#
# 2. Cross-platform script execution:
#    Scripts built with pkgsLinux.writeShellScript fail on macOS with
#    "Exec format error" because they're ELF binaries, not shell scripts.
#    Fix: Use pkgs.writeShellScript (host system) for scripts that run locally.
#
# 3. Workaround: Use dockerTools.buildImage + host skopeo
#    This avoids skopeo-nix2container entirely. The container is built as
#    docker-archive format, then copied with the host's native skopeo.
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

  # ---------------------------------------------------------------------------
  # Get Linux pkgs for container building (containers are always Linux)
  # ---------------------------------------------------------------------------
  pkgsLinux =
    if inputs != null && inputs ? nixpkgs then
      import inputs.nixpkgs { system = "x86_64-linux"; }
    else
      null;

  # ---------------------------------------------------------------------------
  # Get nix2container for Linux (x86_64-linux)
  # ---------------------------------------------------------------------------
  hasNix2container = inputs != null && inputs ? nix2container;
  nix2containerPkgs =
    if hasNix2container then inputs.nix2container.packages.x86_64-linux else null;
  nix2container = if nix2containerPkgs != null then nix2containerPkgs.nix2container else null;

  # ---------------------------------------------------------------------------
  # Base images for different app types
  # Get hash with: nix-shell -p nix-prefetch-docker --run \
  #   "nix-prefetch-docker --image-name oven/bun --image-tag slim --arch amd64"
  # ---------------------------------------------------------------------------
  defaultBaseImages = {
    bun = {
      imageName = "oven/bun";
      imageDigest = "sha256:6111acec4c5a703f2069d6e681967c047920ff2883e7e5a5e64f4ac95ddeb27f";
      arch = "amd64";
      sha256 = "1WxmFkFx9Pf5qcWOWzFy4/yAwekKL4u06fiAqT05Tyo=";
    };
    node = {
      imageName = "node";
      imageDigest = "sha256:a1f1e237b8f228f9c25f3d30b3c890e96ca8a5d8f8d9c5f1f8f9e8d7c6b5a4f3";
      arch = "amd64";
      sha256 = ""; # Users must provide
    };
  };

  # ---------------------------------------------------------------------------
  # Per-app container options (added via appModules)
  # ---------------------------------------------------------------------------
  containerAppModule =
    { lib, name, ... }:
    {
      options.container = {
        enable = lib.mkEnableOption "container building for this app";

        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Container image name. Defaults to the app name.";
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
          description = "App type determines the base image and startup command.";
        };

        port = lib.mkOption {
          type = lib.types.int;
          default = 3000;
          description = "Port the app listens on inside the container.";
        };

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

        registry = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Container registry to push to (e.g., docker://registry.fly.io/).";
        };

        workingDir = lib.mkOption {
          type = lib.types.str;
          default = "/app";
          description = "Working directory inside the container.";
        };

        # Base image configuration
        baseImage = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                imageName = lib.mkOption {
                  type = lib.types.str;
                  description = "Docker image name.";
                };
                imageDigest = lib.mkOption {
                  type = lib.types.str;
                  description = "Image digest (sha256:...).";
                };
                arch = lib.mkOption {
                  type = lib.types.str;
                  default = "amd64";
                  description = "Image architecture.";
                };
                sha256 = lib.mkOption {
                  type = lib.types.str;
                  description = "Nix hash of the image.";
                };
              };
            }
          );
          default = null;
          description = ''
            Base image to use. When null, uses default for the app type.
            Get hash with: nix-shell -p nix-prefetch-docker --run "nix-prefetch-docker --image-name oven/bun --image-tag slim --arch amd64"
          '';
        };

        # Build output path (for impure builds)
        buildOutputPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Path to pre-built output directory (e.g., apps/web/.output).
            Used for impure builds where the app is built on macOS first.
          '';
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

        defaultCopyArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Default arguments to pass to skopeo copy.";
        };

        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Environment variables for the container.";
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Generate startup command based on app type
  # NOTE: In Nix-built containers, binaries are in /bin/ (symlinked from /nix/store)
  # NOT /usr/local/bin/ like in traditional Docker images
  # ---------------------------------------------------------------------------
  mkStartupCommand =
    containerCfg:
    let
      startupCommand = containerCfg.startupCommand or null;
      appType = containerCfg.type or "bun";
    in
    if startupCommand != null then
      if builtins.isList startupCommand then startupCommand else [ "/bin/sh" "-c" startupCommand ]
    else if appType == "bun" then
      # Bun is at /bin/bun in Nix containers (via buildEnv pathsToLink)
      # Nitro outputs to .output/server/index.mjs
      [ "/bin/bun" "/app/.output/server/index.mjs" ]
    else if appType == "node" then
      [ "/bin/node" "/app/.output/server/index.mjs" ]
    else if appType == "go" then
      [ "/app/server" ]
    else if appType == "static" then
      [ "nginx" "-g" "daemon off;" ]
    else
      [ "/bin/sh" ];

  # ---------------------------------------------------------------------------
  # Filter apps with container.enable = true
  # ---------------------------------------------------------------------------
  appsWithContainers = lib.filterAttrs (
    _name: appCfg: (appCfg.container.enable or false)
  ) (cfg.apps or { });

  # ---------------------------------------------------------------------------
  # Build container image using dockerTools.buildImage
  # This works reliably for cross-platform builds (macOS -> Linux containers)
  # ---------------------------------------------------------------------------
  mkContainerDerivation =
    name: containerCfg:
    if pkgsLinux == null then
      null
    else
      let
        # Build output handling (for impure builds)
        projectRoot = cfg.root or (builtins.getEnv "PWD");
        buildOutputPath = containerCfg.buildOutputPath or null;
        hasBuildOutput = buildOutputPath != null;
        fullBuildPath = "${projectRoot}/${buildOutputPath}";
        buildOutputExists = builtins.pathExists fullBuildPath;

        # Create the output bundle from local build
        webOutput =
          if hasBuildOutput && buildOutputExists then
            builtins.path {
              path = /. + fullBuildPath;
              name = "web-output";
            }
          else
            null;

        # Environment variables
        containerEnv =
          [
            "NODE_ENV=production"
            "PORT=${toString (containerCfg.port or 3000)}"
            "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          ]
          ++ lib.mapAttrsToList (k: v: "${k}=${v}") (containerCfg.env or { });

        # App type determines what runtime to include
        appType = containerCfg.type or "bun";
        runtimePkg =
          if appType == "bun" then
            pkgsLinux.bun
          else if appType == "node" then
            pkgsLinux.nodejs
          else
            null;

        # Build the app directory with output
        appDir =
          if webOutput != null then
            pkgsLinux.runCommand "web-app" { } ''
              mkdir -p $out/app/.output
              cp -r ${webOutput}/server $out/app/.output/ || true
              cp -r ${webOutput}/public $out/app/.output/ || true
            ''
          else
            pkgsLinux.runCommand "web-app-placeholder" { } ''
              mkdir -p $out/app
              echo "Build output not found. Run: bun run build:fly" > $out/app/README.txt
            '';

        # Startup command
        startupCmd = mkStartupCommand containerCfg;
      in
      pkgsLinux.dockerTools.buildImage {
        name = containerCfg.name;
        tag = containerCfg.version or "latest";

        copyToRoot = pkgsLinux.buildEnv {
          name = "image-root";
          paths =
            [
              pkgsLinux.bashInteractive
              pkgsLinux.coreutils
              pkgsLinux.cacert
              appDir
            ]
            ++ lib.optional (runtimePkg != null) runtimePkg
            ++ (
              if containerCfg.copyToRoot != null then
                if builtins.isList containerCfg.copyToRoot then
                  containerCfg.copyToRoot
                else
                  [ containerCfg.copyToRoot ]
              else
                [ ]
            );
          pathsToLink = [
            "/bin"
            "/etc"
            "/app"
          ];
        };

        config = {
          WorkingDir = containerCfg.workingDir or "/app";
          Env = containerEnv;
          ExposedPorts = {
            "${toString (containerCfg.port or 3000)}/tcp" = { };
          };
          User = "65534:65534";
          Cmd = startupCmd;
        };
      };

  # ---------------------------------------------------------------------------
  # Build container image using nix2container.buildImage (EXPERIMENTAL)
  #
  # KNOWN ISSUES - This approach currently does NOT work due to upstream bugs:
  # 1. skopeo-nix2container fails to build on Linux with:
  #    "cd: vendor/go.podman.io/image/v5: No such file or directory"
  # 2. The nix2container flake's skopeo derivation is broken
  #
  # Benefits if/when fixed:
  # - More efficient layer caching (individual Nix store paths as layers)
  # - Faster incremental pushes
  # - Better integration with nix2container tooling
  #
  # To use once upstream is fixed, change mkContainerDerivation calls to
  # mkNix2ContainerDerivation and mkCopyScript to mkNix2ContainerCopyScript
  # ---------------------------------------------------------------------------
  mkNix2ContainerDerivation =
    name: containerCfg:
    if nix2container == null || pkgsLinux == null then
      null
    else
      let
        # Build output handling (for impure builds)
        projectRoot = cfg.root or (builtins.getEnv "PWD");
        buildOutputPath = containerCfg.buildOutputPath or null;
        hasBuildOutput = buildOutputPath != null;
        fullBuildPath = "${projectRoot}/${buildOutputPath}";
        buildOutputExists = builtins.pathExists fullBuildPath;

        # Create the output bundle from local build
        webOutput =
          if hasBuildOutput && buildOutputExists then
            builtins.path {
              path = /. + fullBuildPath;
              name = "web-output";
            }
          else
            null;

        # Environment variables
        containerEnv =
          [
            { name = "NODE_ENV"; value = "production"; }
            { name = "PORT"; value = toString (containerCfg.port or 3000); }
            { name = "SSL_CERT_FILE"; value = "/etc/ssl/certs/ca-bundle.crt"; }
          ]
          ++ lib.mapAttrsToList (k: v: { name = k; value = v; }) (containerCfg.env or { });

        # App type determines what runtime to include
        appType = containerCfg.type or "bun";
        runtimePkg =
          if appType == "bun" then
            pkgsLinux.bun
          else if appType == "node" then
            pkgsLinux.nodejs
          else
            null;

        # Build the app directory with output
        appDir =
          if webOutput != null then
            pkgsLinux.runCommand "web-app" { } ''
              mkdir -p $out/app/.output
              cp -r ${webOutput}/server $out/app/.output/ || true
              cp -r ${webOutput}/public $out/app/.output/ || true
            ''
          else
            pkgsLinux.runCommand "web-app-placeholder" { } ''
              mkdir -p $out/app
              echo "Build output not found. Run: bun run build:fly" > $out/app/README.txt
            '';

        # Startup command
        startupCmd = mkStartupCommand containerCfg;
      in
      nix2container.buildImage {
        name = containerCfg.name;
        tag = containerCfg.version or "latest";

        copyToRoot = [
          pkgsLinux.bashInteractive
          pkgsLinux.coreutils
          pkgsLinux.cacert
          appDir
        ]
        ++ lib.optional (runtimePkg != null) runtimePkg
        ++ (
          if containerCfg.copyToRoot != null then
            if builtins.isList containerCfg.copyToRoot then
              containerCfg.copyToRoot
            else
              [ containerCfg.copyToRoot ]
          else
            [ ]
        );

        config = {
          WorkingDir = containerCfg.workingDir or "/app";
          Env = containerEnv;
          ExposedPorts = {
            "${toString (containerCfg.port or 3000)}/tcp" = { };
          };
          User = "65534:65534";
          Cmd = startupCmd;
        };

        # nix2container specific options
        maxLayers = containerCfg.maxLayers or 100;
      };

  # ---------------------------------------------------------------------------
  # Create copy script for nix2container (EXPERIMENTAL - BROKEN)
  #
  # KNOWN ISSUE: This uses skopeo-nix2container which fails to build.
  # Error: "cd: vendor/go.podman.io/image/v5: No such file or directory"
  # ---------------------------------------------------------------------------
  mkNix2ContainerCopyScript =
    name: containerCfg:
    if nix2containerPkgs == null || pkgsLinux == null then
      null
    else
      let
        container = mkNix2ContainerDerivation name containerCfg;
        imageName = containerCfg.name;
        imageTag = containerCfg.version or "latest";
        registry = containerCfg.registry or "docker://registry.fly.io/";
        defaultCopyArgs = containerCfg.defaultCopyArgs or [ ];
        # NOTE: This is the broken package - skopeo-nix2container fails to build
        skopeo-nix2container = nix2containerPkgs.skopeo-nix2container;
      in
      if container == null then
        null
      else
        # NOTE: Using pkgsLinux here means this script can only run on Linux
        # or via a Linux remote builder. This is intentional for nix2container.
        pkgsLinux.writeShellScript "copy-container-nix2container-${name}" ''
          set -e -o pipefail

          IMAGE_NAME="${imageName}"
          IMAGE_TAG="${imageTag}"

          if [[ -z "$1" ]] || [[ "$1" == "--"* ]]; then
            DEST="${registry}''${IMAGE_NAME}:''${IMAGE_TAG}"
          elif [[ "$1" == "docker-daemon:" ]]; then
            DEST="docker-daemon:''${IMAGE_NAME}:''${IMAGE_TAG}"
            shift || true
          else
            DEST="$1''${IMAGE_NAME}:''${IMAGE_TAG}"
            shift
          fi

          echo
          echo "📦 Copying container image (nix2container)..."
          echo "   Destination: $DEST"
          echo

          # Use skopeo-nix2container to copy (BROKEN - see module header)
          ${skopeo-nix2container}/bin/skopeo copy \
            --insecure-policy \
            "nix:${container}" \
            "$DEST" \
            ${lib.concatStringsSep " " defaultCopyArgs} "$@"

          echo
          echo "✅ Successfully copied to $DEST"
        '';

  # ---------------------------------------------------------------------------
  # Create copy script (push to registry)
  # Uses skopeo to copy the docker-archive to a registry
  # Built for current system (macOS) but references Linux container image
  # ---------------------------------------------------------------------------
  mkCopyScript =
    name: containerCfg:
    if pkgs == null || pkgsLinux == null then
      null
    else
      let
        container = mkContainerDerivation name containerCfg;
        imageName = containerCfg.name;
        imageTag = containerCfg.version or "latest";
        registry = containerCfg.registry or "docker://registry.fly.io/";
        defaultCopyArgs = containerCfg.defaultCopyArgs or [ ];
      in
      if container == null then
        null
      else
        # Use pkgs (current system) for the script so it runs on macOS
        # The container is still Linux but the script itself runs natively
        pkgs.writeShellScript "copy-container-${name}" ''
          set -e -o pipefail

          IMAGE_NAME="${imageName}"
          IMAGE_TAG="${imageTag}"
          IMAGE_ARCHIVE="${container}"

          # Allow overriding destination via first argument
          if [[ -z "$1" ]] || [[ "$1" == "--"* ]]; then
            DEST="${registry}''${IMAGE_NAME}:''${IMAGE_TAG}"
          elif [[ "$1" == "docker-daemon:" ]]; then
            DEST="docker-daemon:''${IMAGE_NAME}:''${IMAGE_TAG}"
            shift || true
          else
            DEST="$1''${IMAGE_NAME}:''${IMAGE_TAG}"
            shift
          fi

          echo
          echo "📦 Copying container image..."
          echo "   Source: $IMAGE_ARCHIVE"
          echo "   Destination: $DEST"
          echo

          # Use skopeo (from current system) to copy from docker-archive to destination
          ${pkgs.skopeo}/bin/skopeo copy \
            --insecure-policy \
            "docker-archive:$IMAGE_ARCHIVE" \
            "$DEST" \
            ${lib.concatStringsSep " " defaultCopyArgs} "$@"

          echo
          echo "✅ Successfully copied to $DEST"
        '';

  # ---------------------------------------------------------------------------
  # Generate container config from app config
  # ---------------------------------------------------------------------------
  mkContainerFromApp =
    appName: appCfg:
    let
      container = appCfg.container;
      appPath = appCfg.path or "apps/${appName}";
    in
    {
      name = if container.name != null then container.name else appName;
      version = container.version;
      type = container.type;
      port = container.port;
      startupCommand = container.startupCommand;
      registry = container.registry;
      workingDir = container.workingDir;
      baseImage = container.baseImage;
      # Default buildOutputPath to app's .output directory
      buildOutputPath =
        if container.buildOutputPath != null then
          container.buildOutputPath
        else
          "${appPath}/.output";
      copyToRoot = container.copyToRoot;
      defaultCopyArgs = container.defaultCopyArgs;
      env = container.env;
    };

  # ---------------------------------------------------------------------------
  # Layer submodule type
  # ---------------------------------------------------------------------------
  layerModule = lib.types.submodule {
    options = {
      deps = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Store paths to include in the layer.";
      };

      copyToRoot = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Derivations copied to the image root directory.";
      };

      reproducible = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the layer should be reproducible.";
      };
    };
  };

  # Build all outputs
  containerDerivations = lib.mapAttrs mkContainerDerivation containersCfg;
  copyScripts = lib.mapAttrs mkCopyScript containersCfg;

  # Filter out nulls
  validDerivations = lib.filterAttrs (_: v: v != null) containerDerivations;
  validCopyScripts = lib.filterAttrs (_: v: v != null) copyScripts;

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.containers = lib.mkOption {
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

            baseImage = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    imageName = lib.mkOption {
                      type = lib.types.str;
                      description = "Docker image name.";
                    };
                    imageDigest = lib.mkOption {
                      type = lib.types.str;
                      description = "Image digest (sha256:...).";
                    };
                    arch = lib.mkOption {
                      type = lib.types.str;
                      default = "amd64";
                      description = "Image architecture.";
                    };
                    sha256 = lib.mkOption {
                      type = lib.types.str;
                      description = "Nix hash of the image.";
                    };
                  };
                }
              );
              default = null;
              description = "Base image configuration.";
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
              default = "docker-daemon:";
              description = ''
                Registry to push to. Examples:
                - "docker-daemon:" (local Docker)
                - "docker://registry.fly.io/"
                - "docker://ghcr.io/org/"
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

            layers = lib.mkOption {
              type = lib.types.listOf layerModule;
              default = [ ];
              description = "Additional container layers.";
            };
          };
        }
      )
    );
    default = { };
    description = ''
      Container definitions built with dockerTools.

      Build and push:
        container-build <name>   # Build container image
        container-copy <name>    # Build + push to registry
        container-run <name>     # Build + run in Docker
    '';
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
        stackpanel.containers = lib.mapAttrs mkContainerFromApp appsWithContainers;
      })

      # When dockerTools is available (pkgsLinux) and we have containers
      (lib.mkIf (containersCfg != { } && pkgsLinux != null && pkgs != null) {
        # Computed outputs for flake exposure
        stackpanel.containersComputed = {
          images = validDerivations;
          copyScripts = validCopyScripts;
        };

        # Add container helper scripts
        # Note: --impure is required because we read local build output from filesystem
        stackpanel.scripts = {
          container-build = {
            description = "Build a container image (uses Linux builder)";
            exec = ''
              if [ $# -eq 0 ]; then
                echo "Usage: container-build <container-name>"
                echo "Available containers: ${lib.concatStringsSep ", " (lib.attrNames containersCfg)}"
                echo ""
                echo "Make sure to build your app first: bun run build"
                exit 1
              fi
              echo "📦 Building Linux container..."
              echo "   (Uses remote Linux builder on macOS)"
              nix build --impure ".#packages.x86_64-linux.container-$1" "''${@:2}"
              echo "✅ Container built: ./result"
            '';
          };

          container-copy = {
            description = "Build and push a container to registry";
            exec = ''
              if [ $# -eq 0 ]; then
                echo "Usage: container-copy <container-name> [registry]"
                echo "Available containers: ${lib.concatStringsSep ", " (lib.attrNames containersCfg)}"
                echo ""
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
            description = "Run container locally (uses Apple container on macOS, Docker elsewhere)";
            exec = ''
              if [ $# -eq 0 ]; then
                echo "Usage: container-run <container-name> [args...]"
                echo "Available containers: ${lib.concatStringsSep ", " (lib.attrNames containersCfg)}"
                echo ""
                echo "Make sure to build your app first: bun run build"
                exit 1
              fi
              NAME="$1"
              shift

              # Check for Apple's container tool (macOS native, optimized for Apple Silicon)
              if command -v container &> /dev/null && [[ "$(uname)" == "Darwin" ]]; then
                echo "🍎 Using Apple container (native macOS)"
                echo "📦 Pulling/running container..."
                container run -it "$NAME:latest" "$@"
              elif command -v docker &> /dev/null; then
                echo "🐳 Using Docker"
                echo "📦 Building and loading container..."
                nix run --impure ".#copy-container-$NAME" -- docker-daemon: || {
                  echo "⚠️  Container copy failed, trying Dockerfile build..."
                  docker build -t "$NAME:latest" -f "packages/infra/docker/$NAME/Dockerfile" .
                }
                echo "🚀 Running container..."
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
                  echo "  - Apple container (recommended for macOS):"
                  echo "      Run: container-install"
                  echo "      Or:  brew install --cask container"
                fi
                echo "  - Docker Desktop: https://www.docker.com/products/docker-desktop"
                exit 1
              fi
            '';
          };

          # Install Apple's container tool via Homebrew
          container-install = {
            description = "Install Apple's container tool (macOS only, requires Homebrew)";
            exec = ''
              if [[ "$(uname)" != "Darwin" ]]; then
                echo "❌ Apple container is only available on macOS"
                exit 1
              fi

              if command -v container &> /dev/null; then
                echo "✅ Apple container is already installed"
                container --version
                exit 0
              fi

              if ! command -v brew &> /dev/null; then
                echo "❌ Homebrew is required to install Apple container"
                echo ""
                echo "Install Homebrew first:"
                echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
                echo ""
                echo "Or install manually from: https://github.com/apple/container/releases"
                exit 1
              fi

              echo "🍎 Installing Apple container via Homebrew..."
              echo ""
              brew install --cask container

              echo ""
              echo "✅ Apple container installed!"
              echo ""
              echo "Starting container system..."
              container system start

              echo ""
              echo "You can now use:"
              echo "  container-run <name>     - Run a container"
              echo "  container-apple <cmd>    - Direct container CLI access"
            '';
          };

          # Apple's container tool - native macOS container runtime
          # https://github.com/apple/container
          container-apple = {
            description = "Run container with Apple's native container tool (macOS only)";
            exec = ''
              if ! command -v container &> /dev/null; then
                echo "❌ Apple container not installed"
                echo ""
                if command -v brew &> /dev/null; then
                  echo "Install with: container-install"
                  echo "         or:  brew install --cask container"
                else
                  echo "Install from: https://github.com/apple/container/releases"
                fi
                echo "Then run: container system start"
                exit 1
              fi

              if [ $# -eq 0 ]; then
                echo "Usage: container-apple <command> [args...]"
                echo ""
                echo "Commands:"
                echo "  run <image>     Run a container"
                echo "  build           Build an image from Dockerfile"
                echo "  push            Push image to registry"
                echo "  images          List images"
                echo "  ps              List running containers"
                echo ""
                echo "Available containers: ${lib.concatStringsSep ", " (lib.attrNames containersCfg)}"
                exit 0
              fi

              container "$@"
            '';
          };

          # Build with Apple container (uses Dockerfile)
          container-apple-build = {
            description = "Build container image with Apple container (macOS native)";
            exec = ''
              if ! command -v container &> /dev/null; then
                echo "❌ Apple container not installed"
                echo ""
                if command -v brew &> /dev/null; then
                  echo "Install with: container-install"
                else
                  echo "Install from: https://github.com/apple/container/releases"
                fi
                exit 1
              fi

              if [ $# -eq 0 ]; then
                echo "Usage: container-apple-build <container-name>"
                echo "Available: ${lib.concatStringsSep ", " (lib.attrNames containersCfg)}"
                exit 1
              fi

              NAME="$1"
              DOCKERFILE="packages/infra/docker/$NAME/Dockerfile"

              if [ ! -f "$DOCKERFILE" ]; then
                echo "❌ Dockerfile not found: $DOCKERFILE"
                exit 1
              fi

              echo "🍎 Building with Apple container..."
              container build -t "$NAME:latest" -f "$DOCKERFILE" .
              echo "✅ Built: $NAME:latest"
            '';
          };
        };
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
