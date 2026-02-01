# ==============================================================================
# containers.nix - Pure Library Functions for Container Building
#
# Provides backend-agnostic container building functions that work with either:
#   - nix2container (default) - Efficient layer caching, streaming pushes
#   - dockerTools - Reliable cross-platform builds, no external dependencies
#
# Usage:
#   containerLib = import ./containers.nix { inherit lib pkgs inputs; };
#   image = containerLib.mkContainer {
#     name = "my-app";
#     backend = "nix2container"; # or "dockerTools"
#     type = "bun";
#     port = 3000;
#     buildOutputPath = "apps/web/.output";
#   };
# ==============================================================================
{
  lib,
  pkgs ? null,
  inputs ? null,
}:
let
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
  nix2containerPkgs = if hasNix2container then inputs.nix2container.packages.x86_64-linux else null;
  nix2containerLib = if nix2containerPkgs != null then nix2containerPkgs.nix2container else null;

  # ---------------------------------------------------------------------------
  # Default base images for nix2container.pullImage
  # Get hash with: nix-shell -p nix-prefetch-docker --run \
  #   "nix-prefetch-docker --image-name oven/bun --image-tag slim --arch amd64"
  # ---------------------------------------------------------------------------
  defaultBaseImageSpecs = {
    bun = {
      imageName = "oven/bun";
      imageDigest = "sha256:6111acec4c5a703f2069d6e681967c047920ff2883e7e5a5e64f4ac95ddeb27f";
      arch = "amd64";
      sha256 = "1WxmFkFx9Pf5qcWOWzFy4/yAwekKL4u06fiAqT05Tyo=";
    };
    node = {
      imageName = "node";
      imageDigest = "sha256:22-alpine"; # TODO: Pin to specific digest
      arch = "amd64";
      sha256 = lib.fakeSha256;
    };
    alpine = {
      imageName = "alpine";
      imageDigest = "sha256:latest"; # TODO: Pin to specific digest
      arch = "amd64";
      sha256 = lib.fakeSha256;
    };
    distroless = {
      imageName = "gcr.io/distroless/static-debian12";
      imageDigest = "sha256:latest"; # TODO: Pin to specific digest
      arch = "amd64";
      sha256 = lib.fakeSha256;
    };
    nginx = {
      imageName = "nginx";
      imageDigest = "sha256:alpine-latest"; # TODO: Pin to specific digest
      arch = "amd64";
      sha256 = lib.fakeSha256;
    };
  };

  # ---------------------------------------------------------------------------
  # Pull base image for nix2container
  # ---------------------------------------------------------------------------
  pullBaseImage =
    type:
    if nix2containerLib == null then
      null
    else
      let
        spec = defaultBaseImageSpecs.${type} or defaultBaseImageSpecs.alpine;
      in
      nix2containerLib.pullImage spec;

  # ---------------------------------------------------------------------------
  # Get runtime package for dockerTools (included in copyToRoot)
  # ---------------------------------------------------------------------------
  getRuntimePackage =
    type:
    if pkgsLinux == null then
      null
    else if type == "bun" then
      pkgsLinux.bun
    else if type == "node" then
      pkgsLinux.nodejs
    else
      null;

  # ---------------------------------------------------------------------------
  # Generate startup command based on app type
  # NOTE: Paths differ between backends:
  #   - nix2container with base image: /usr/local/bin/bun
  #   - dockerTools buildImage: /bin/bun (via buildEnv pathsToLink)
  # ---------------------------------------------------------------------------
  mkStartupCommand =
    {
      type,
      startupCommand ? null,
      backend ? "nix2container",
    }:
    if startupCommand != null then
      if builtins.isList startupCommand then
        startupCommand
      else
        [
          "/bin/sh"
          "-c"
          startupCommand
        ]
    else if type == "bun" then
      if backend == "nix2container" then
        [
          "/usr/local/bin/bun"
          "/app/.output/server/index.mjs"
        ]
      else
        [
          "/bin/bun"
          "/app/.output/server/index.mjs"
        ]
    else if type == "node" then
      if backend == "nix2container" then
        [
          "/usr/local/bin/node"
          "/app/.output/server/index.mjs"
        ]
      else
        [
          "/bin/node"
          "/app/.output/server/index.mjs"
        ]
    else if type == "go" then
      [ "/app/server" ]
    else if type == "static" then
      [
        "nginx"
        "-g"
        "daemon off;"
      ]
    else
      [ "/bin/sh" ];

  # ---------------------------------------------------------------------------
  # Build environment variables list
  # OCI image spec defines Env as []string in "KEY=value" format
  # Both nix2container and dockerTools expect this same format
  # ---------------------------------------------------------------------------
  mkContainerEnv =
    {
      port ? 3000,
      env ? { },
      backend ? "nix2container", # Kept for API compatibility, not used
    }:
    let
      baseList = [
        "NODE_ENV=production"
        "PORT=${toString port}"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      ];

      customList = lib.mapAttrsToList (k: v: "${k}=${v}") env;
    in
    # Both backends use OCI-standard list of "KEY=value" strings
    baseList ++ customList;

  # ---------------------------------------------------------------------------
  # Build app directory from build output
  # ---------------------------------------------------------------------------
  mkAppDir =
    {
      name,
      projectRoot,
      buildOutputPath,
    }:
    if pkgsLinux == null then
      null
    else
      let
        fullBuildPath = "${projectRoot}/${buildOutputPath}";
        buildOutputExists = builtins.pathExists fullBuildPath;

        webOutput =
          if buildOutputExists then
            builtins.path {
              path = /. + fullBuildPath;
              name = "${name}-output";
            }
          else
            null;
      in
      if webOutput != null then
        pkgsLinux.runCommand "${name}-app" { } ''
          mkdir -p $out/app/.output
          cp -r ${webOutput}/server $out/app/.output/ || true
          cp -r ${webOutput}/public $out/app/.output/ || true
        ''
      else
        pkgsLinux.runCommand "${name}-app-placeholder" { } ''
          mkdir -p $out/app
          echo "Build output not found at ${buildOutputPath}. Run your build command first." > $out/app/README.txt
        '';

  # ---------------------------------------------------------------------------
  # Build container with nix2container
  # ---------------------------------------------------------------------------
  mkNix2Container =
    {
      name,
      version ? "latest",
      type ? "bun",
      port ? 3000,
      projectRoot,
      buildOutputPath,
      workingDir ? "/app",
      startupCommand ? null,
      copyToRoot ? null,
      env ? { },
      maxLayers ? 100,
    }:
    if nix2containerLib == null || pkgsLinux == null then
      null
    else
      let
        baseImage = pullBaseImage type;
        appDir = mkAppDir { inherit name projectRoot buildOutputPath; };

        # Base packages layer
        basePackages = [
          pkgsLinux.bashInteractive
          pkgsLinux.coreutils
          pkgsLinux.cacert
        ];

        # User-provided extra paths
        extraPaths =
          if copyToRoot != null then
            if builtins.isList copyToRoot then copyToRoot else [ copyToRoot ]
          else
            [ ];

        # App layer
        appLayer = pkgsLinux.runCommand "${name}-layer" { } ''
          mkdir -p $out
          cp -r ${appDir}/* $out/
        '';
      in
      nix2containerLib.buildImage {
        inherit name;
        tag = version;
        fromImage = baseImage;

        layers = [
          (nix2containerLib.buildLayer {
            reproducible = false;
            copyToRoot = basePackages ++ extraPaths ++ [ appLayer ];
          })
        ];

        config = {
          WorkingDir = workingDir;
          Env = mkContainerEnv {
            inherit port env;
            backend = "nix2container";
          };
          ExposedPorts = {
            "${toString port}/tcp" = { };
          };
          User = "65534:65534";
          Cmd = mkStartupCommand {
            inherit type startupCommand;
            backend = "nix2container";
          };
        };

        inherit maxLayers;
      };

  # ---------------------------------------------------------------------------
  # Build container with dockerTools.buildImage
  # ---------------------------------------------------------------------------
  mkDockerToolsContainer =
    {
      name,
      version ? "latest",
      type ? "bun",
      port ? 3000,
      projectRoot,
      buildOutputPath,
      workingDir ? "/app",
      startupCommand ? null,
      copyToRoot ? null,
      env ? { },
    }:
    if pkgsLinux == null then
      null
    else
      let
        appDir = mkAppDir { inherit name projectRoot buildOutputPath; };
        runtimePkg = getRuntimePackage type;

        # User-provided extra paths
        extraPaths =
          if copyToRoot != null then
            if builtins.isList copyToRoot then copyToRoot else [ copyToRoot ]
          else
            [ ];
      in
      pkgsLinux.dockerTools.buildImage {
        inherit name;
        tag = version;

        copyToRoot = pkgsLinux.buildEnv {
          name = "image-root";
          paths = [
            pkgsLinux.bashInteractive
            pkgsLinux.coreutils
            pkgsLinux.cacert
            appDir
          ]
          ++ lib.optional (runtimePkg != null) runtimePkg
          ++ extraPaths;
          pathsToLink = [
            "/bin"
            "/etc"
            "/app"
          ];
        };

        config = {
          WorkingDir = workingDir;
          Env = mkContainerEnv {
            inherit port env;
            backend = "dockerTools";
          };
          ExposedPorts = {
            "${toString port}/tcp" = { };
          };
          User = "65534:65534";
          Cmd = mkStartupCommand {
            inherit type startupCommand;
            backend = "dockerTools";
          };
        };
      };

  # ---------------------------------------------------------------------------
  # Create copy script for pushing to registry
  # Uses host system skopeo for cross-platform compatibility
  # ---------------------------------------------------------------------------
  mkCopyScript =
    {
      name,
      container,
      version ? "latest",
      registry ? "docker://registry.fly.io/",
      defaultCopyArgs ? [ ],
      backend ? "nix2container",
    }:
    if pkgs == null || container == null then
      null
    else
      let
        sourceArg =
          if backend == "nix2container" then
            "nix:${container}"
          else
            "docker-archive:${container}";
      in
      pkgs.writeShellScript "copy-container-${name}" ''
        set -e -o pipefail

        IMAGE_NAME="${name}"
        IMAGE_TAG="${version}"

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
        echo "   Source: ${sourceArg}"
        echo "   Destination: $DEST"
        echo

        ${pkgs.skopeo}/bin/skopeo copy \
          --insecure-policy \
          "${sourceArg}" \
          "$DEST" \
          ${lib.concatStringsSep " " defaultCopyArgs} "$@"

        echo
        echo "✅ Successfully copied to $DEST"
      '';

in
{
  # Expose individual components for flexibility
  inherit
    pkgsLinux
    nix2containerLib
    nix2containerPkgs
    defaultBaseImageSpecs
    pullBaseImage
    getRuntimePackage
    mkStartupCommand
    mkContainerEnv
    mkAppDir
    mkNix2Container
    mkDockerToolsContainer
    mkCopyScript
    ;

  # ===========================================================================
  # mkContainer - Unified container builder with backend selection
  # ===========================================================================
  mkContainer =
    {
      name,
      version ? "latest",
      type ? "bun",
      port ? 3000,
      projectRoot,
      buildOutputPath,
      workingDir ? "/app",
      startupCommand ? null,
      copyToRoot ? null,
      env ? { },
      backend ? "nix2container",
      maxLayers ? 100, # nix2container only
      registry ? "docker://registry.fly.io/",
      defaultCopyArgs ? [ ],
    }:
    let
      containerArgs = {
        inherit
          name
          version
          type
          port
          projectRoot
          buildOutputPath
          workingDir
          startupCommand
          copyToRoot
          env
          ;
      };

      container =
        if backend == "nix2container" then
          mkNix2Container (containerArgs // { inherit maxLayers; })
        else
          mkDockerToolsContainer containerArgs;

      copyScript = mkCopyScript {
        inherit
          name
          container
          version
          registry
          defaultCopyArgs
          backend
          ;
      };
    in
    {
      inherit container copyScript backend;
      image = container;
    };

  # ===========================================================================
  # Utility: Check if backends are available
  # ===========================================================================
  hasNix2container = nix2containerLib != null;
  hasDockerTools = pkgsLinux != null;
  availableBackends =
    lib.optional (nix2containerLib != null) "nix2container"
    ++ lib.optional (pkgsLinux != null) "dockerTools";
}
