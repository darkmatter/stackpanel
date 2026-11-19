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

  # Patched skopeo with nix: transport support — includes the custom nix:
  # transport that can read nix2container image JSON files from the nix store.
  # Uses host system (e.g. aarch64-darwin) since the copy script runs locally
  # and Linux store paths are present locally after remote builds.
  skopeoNix2container =
    if hasNix2container && pkgs != null then
      inputs.nix2container.packages.${pkgs.stdenv.hostPlatform.system}.skopeo-nix2container
    else
      null;

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
        spec = defaultBaseImageSpecs.${type};
        # Refuse to build from an unpinned base image: the unpinned specs carry
        # lib.fakeSha256, which would otherwise fail later as a cryptic hash
        # mismatch. Pin with `nix-prefetch-docker` (set imageDigest + sha256).
        isPinned = (spec.sha256 or lib.fakeSha256) != lib.fakeSha256;
      in
      assert lib.assertMsg isPinned
        "stackpanel: base image '${spec.imageName}' is not pinned (still lib.fakeSha256); pin it with nix-prefetch-docker before building a container from it.";
      nix2containerLib.pullImage spec;

  # Runtime-specific defaults belong to providers, not to either OCI backend.
  jsProfile = executable: package: {
    baseImage = pullBaseImage executable;
    runtimePackage = if pkgsLinux == null then null else pkgsLinux.${package};
    defaultCommand = backend: [
      "${if backend == "nix2container" then "/usr/local/bin" else "/bin"}/${executable}"
      "/app/.output/server/index.mjs"
    ];
  };
  alpineProfile = command: {
    baseImage = pullBaseImage "alpine";
    defaultCommand = _: command;
  };
  builtinProfiles = {
    bun = jsProfile "bun" "bun";
    node = jsProfile "node" "nodejs";
    go = alpineProfile [ "/app/server" ];
    static = alpineProfile [
      "nginx"
      "-g"
      "daemon off;"
    ];
    custom = alpineProfile [ "/bin/sh" ];
  };

  builtinBuilders = lib.mapAttrs (
    _: profile:
    { image, containerLib, ... }:
    containerLib.buildImage (
      image
      // {
        inherit (profile) baseImage;
        runtimePackage = profile.runtimePackage or null;
        defaultCommand = profile.defaultCommand image.backend;
      }
    )
  ) builtinProfiles;

  resolveCommand =
    defaultCommand: startupCommand:
    if startupCommand == null then
      defaultCommand
    else if builtins.isList startupCommand then
      startupCommand
    else
      [
        "/bin/sh"
        "-c"
        startupCommand
      ];

  # ---------------------------------------------------------------------------
  # Build environment variables list
  # OCI image spec defines Env as []string in "KEY=value" format
  # Both nix2container and dockerTools expect this same format
  # ---------------------------------------------------------------------------
  mkContainerEnv =
    {
      port ? 3000,
      env ? { }, # Kept for API compatibility, not used
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
        # The flake's store copy lives at `projectRoot`. It excludes git-
        # ignored directories like `.output` (produced by `bun build`,
        # `vite build`, OpenNext). So `${projectRoot}/apps/<app>/.output`
        # typically doesn't exist in the store even when the build has
        # just run on the host filesystem.
        #
        # Fall back to an absolute path injected via STACKPANEL_ROOT_ABSOLUTE
        # (set by the deploy workflow to ${GITHUB_WORKSPACE}) so the nix
        # build can import freshly-built output without requiring it to be
        # committed to git. Requires `--impure` which we already use.
        fullBuildPath = "${projectRoot}/${buildOutputPath}";
        absoluteRoot = builtins.getEnv "STACKPANEL_ROOT_ABSOLUTE";
        absolutePath = if absoluteRoot != "" then "${absoluteRoot}/${buildOutputPath}" else null;
        chosenPath =
          if absolutePath != null && builtins.pathExists absolutePath then
            absolutePath
          else if builtins.pathExists fullBuildPath then
            fullBuildPath
          else
            null;
        buildOutputExists = chosenPath != null;

        webOutput =
          if buildOutputExists then
            builtins.path {
              path = /. + chosenPath;
              name = "${name}-output";
            }
          else
            null;
      in
      if webOutput != null then
        pkgsLinux.runCommand "${name}-app"
          {
            preferLocalBuild = true;
            allowSubstitutes = false;
          }
          ''
            mkdir -p $out/app/.output
            cp -r ${webOutput}/server $out/app/.output/ || true
            cp -r ${webOutput}/public $out/app/.output/ || true
          ''
      else
        pkgsLinux.runCommand "${name}-app-placeholder"
          {
            preferLocalBuild = true;
            allowSubstitutes = false;
          }
          ''
            mkdir -p $out/app
            echo "Build output not found at ${buildOutputPath}. Run your build command first." > $out/app/README.txt
          '';

  # ---------------------------------------------------------------------------
  # Build container with nix2container
  # ---------------------------------------------------------------------------
  buildNix2Container =
    {
      name,
      version,
      appDir,
      baseImage,
      extraPaths,
      config,
      maxLayers,
    }:
    if nix2containerLib == null then
      throw "stackpanel.containers: image '${name}' selects the nix2container backend but inputs.nix2container is unavailable"
    else if pkgsLinux == null then
      throw "stackpanel.containers: image '${name}' requires inputs.nixpkgs for Linux packages"
    else
      let
        # Base packages layer
        basePackages = [
          pkgsLinux.bashInteractive
          pkgsLinux.coreutils
          pkgsLinux.cacert
        ];

        # App layer
        appLayer =
          pkgsLinux.runCommand "${name}-layer"
            {
              preferLocalBuild = true;
              allowSubstitutes = false;
            }
            ''
              mkdir -p $out
              cp -r ${appDir}/* $out/
            '';
      in
      nix2containerLib.buildImage (
        {
          inherit name;
          tag = version;
          inherit config maxLayers;

          layers = [
            (nix2containerLib.buildLayer {
              reproducible = false;
              copyToRoot = basePackages ++ extraPaths ++ [ appLayer ];
            })
          ];

        }
        // lib.optionalAttrs (baseImage != null) { fromImage = baseImage; }
      );

  # ---------------------------------------------------------------------------
  # Build container with dockerTools.buildImage
  # ---------------------------------------------------------------------------
  buildDockerToolsContainer =
    {
      name,
      version,
      appDir,
      runtimePackage,
      extraPaths,
      config,
    }:
    if pkgsLinux == null then
      throw "stackpanel.containers: image '${name}' requires inputs.nixpkgs for dockerTools"
    else
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
          ++ lib.optional (runtimePackage != null) runtimePackage
          ++ extraPaths;
          pathsToLink = [
            "/bin"
            "/etc"
            "/app"
          ];
        };

        inherit config;
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
      registry ? "docker-daemon:",
      defaultCopyArgs ? [ ],
      backend ? "nix2container",
    }:
    let
      # Ensure registry is never null (fall back to default if null)
      effectiveRegistry = if registry != null then registry else "docker-daemon:";
    in
    if pkgs == null || container == null then
      null
    else
      let
        sourceArg =
          if backend == "nix2container" then "nix:${container}" else "docker-archive:${container}";
        # Always use host pkgs for the copy script — it runs locally on the host.
        # The patched skopeo-nix2container supports macOS natively and reads
        # Linux store paths from the local store (copied back from remote builder).
        writePkgs = pkgs;
      in
      writePkgs.writeShellScript "copy-container-${name}" ''
        set -e -o pipefail

        IMAGE_NAME=${lib.escapeShellArg name}
        IMAGE_TAG=${lib.escapeShellArg version}

        # Allow overriding destination via first argument
        if [[ -z "$1" ]] || [[ "$1" == "--"* ]]; then
          DEST=${lib.escapeShellArg effectiveRegistry}"''${IMAGE_NAME}:''${IMAGE_TAG}"
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

        ${
          if backend == "nix2container" && skopeoNix2container != null then
            skopeoNix2container
          else
            pkgs.skopeo
        }/bin/skopeo copy \
          --insecure-policy \
          "${sourceArg}" \
          "$DEST" \
          ${lib.escapeShellArgs defaultCopyArgs} "$@"

        echo
        echo "✅ Successfully copied to $DEST"
      '';

  # Provider helper. A provider may supply its own Linux appDir (a tree rooted
  # at /), default argv, pulled base image, and/or dockerTools runtime package.
  # Both backends use the same resolved OCI config and host-side copy settings.
  buildImage =
    {
      name,
      version,
      backend,
      projectRoot,
      buildOutputPath,
      workingDir,
      port,
      env,
      startupCommand,
      copyToRoot,
      registry,
      defaultCopyArgs,
      maxLayers,
      appDir ? mkAppDir { inherit name projectRoot buildOutputPath; },
      baseImage ? null,
      runtimePackage ? null,
      defaultCommand ? [ "/bin/sh" ],
      ...
    }:
    let
      common = {
        inherit name version appDir;
        extraPaths = if copyToRoot == null then [ ] else lib.toList copyToRoot;
        config = {
          WorkingDir = workingDir;
          Env = mkContainerEnv { inherit port env; };
          ExposedPorts."${toString port}/tcp" = { };
          User = "65534:65534";
          Cmd = resolveCommand defaultCommand startupCommand;
        };
      };
      container =
        if backend == "nix2container" then
          buildNix2Container (common // { inherit baseImage maxLayers; })
        else if backend == "dockerTools" then
          buildDockerToolsContainer (common // { inherit runtimePackage; })
        else
          throw "stackpanel.containers: unknown backend '${backend}' for image '${name}'";
    in
    {
      inherit container;
      copyScript = mkCopyScript {
        inherit
          name
          version
          container
          registry
          defaultCopyArgs
          backend
          ;
      };
    };

in
rec {
  # Expose individual components for flexibility
  inherit
    pkgsLinux
    nix2containerLib
    nix2containerPkgs
    defaultBaseImageSpecs
    pullBaseImage
    buildImage
    builtinBuilders
    mkContainerEnv
    mkAppDir
    mkCopyScript
    ;

  # The backend-specific entry points select a backend, not an image provider.
  mkNix2Container = args: (mkContainer (args // { backend = "nix2container"; })).container;
  mkDockerToolsContainer = args: (mkContainer (args // { backend = "dockerTools"; })).container;

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
      registry ? "docker-daemon:",
      defaultCopyArgs ? [ ],
      builders ? builtinBuilders,
      appName ? name,
      app ? null,
    }:
    let
      image = {
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
          backend
          maxLayers
          registry
          defaultCopyArgs
          ;
      };

      builder =
        builders.${type} or (throw ''
          stackpanel.containers: no container builder '${type}' for '${appName}'.
          Register stackpanel.containerBuilders.${type} or choose one of: ${lib.concatStringsSep ", " (builtins.attrNames builders)}.
        '');
      result = builder {
        inherit
          appName
          app
          image
          lib
          pkgs
          inputs
          ;
        containerLib = {
          inherit
            buildImage
            pkgsLinux
            nix2containerLib
            mkCopyScript
            ;
        };
      };
    in
    assert lib.assertMsg (builtins.isAttrs result && result ? container && result ? copyScript)
      "stackpanel.containerBuilders.${type}: builder for '${appName}' must return { container, copyScript }";
    assert lib.assertMsg (lib.isDerivation result.container)
      "stackpanel.containerBuilders.${type}: builder for '${appName}' did not return an image derivation";
    result
    // {
      inherit backend;
      image = result.container;
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
