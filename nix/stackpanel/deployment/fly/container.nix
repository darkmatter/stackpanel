# ==============================================================================
# container.nix - nix2container Image Building for Fly.io
#
# Creates container images using nix2container for deployment to Fly.io.
# Supports multiple app types: bun, node, go, static, custom.
#
# Build strategy:
# - Apps are built impure on the host (using local bun/node/go)
# - The build output is then copied into a linux container
# - This avoids cross-compilation issues with native modules
#
# For pure builds, you'd need a Linux builder (remote or VM).
# ==============================================================================
{
  lib,
  pkgs,
  inputs,
}:
let
  # Import nixpkgs for x86_64-linux to build amd64 container images
  pkgsLinux = import inputs.nixpkgs {
    system = "x86_64-linux";
  };

  # Get linux nix2container packages for building amd64 images
  nix2containerPkgs = inputs.nix2container.packages.x86_64-linux;

  # Import fly-oidc library
  flyOidc = import ./lib/fly-oidc.nix { pkgs = pkgsLinux; };

  # ---------------------------------------------------------------------------
  # Base Images
  # ---------------------------------------------------------------------------
  baseImages = {
    bun = nix2containerPkgs.nix2container.pullImage {
      imageName = "oven/bun";
      imageDigest = "sha256:6111acec4c5a703f2069d6e681967c047920ff2883e7e5a5e64f4ac95ddeb27f";
      arch = "amd64";
      sha256 = "sha256-1WxmFkFx9Pf5qcWOWzFy4/yAwekKL4u06fiAqT05Tyo=";
    };

    node = nix2containerPkgs.nix2container.pullImage {
      imageName = "node";
      imageDigest = "sha256:alpine-latest"; # TODO: Pin to specific digest
      arch = "amd64";
      sha256 = lib.fakeSha256; # Will need to be updated with real hash
    };

    alpine = nix2containerPkgs.nix2container.pullImage {
      imageName = "alpine";
      imageDigest = "sha256:latest"; # TODO: Pin to specific digest
      arch = "amd64";
      sha256 = lib.fakeSha256; # Will need to be updated with real hash
    };

    # Distroless for Go apps
    distroless = nix2containerPkgs.nix2container.pullImage {
      imageName = "gcr.io/distroless/static-debian12";
      imageDigest = "sha256:latest"; # TODO: Pin to specific digest
      arch = "amd64";
      sha256 = lib.fakeSha256; # Will need to be updated with real hash
    };

    # Nginx for static sites
    nginx = nix2containerPkgs.nix2container.pullImage {
      imageName = "nginx";
      imageDigest = "sha256:alpine-latest"; # TODO: Pin to specific digest
      arch = "amd64";
      sha256 = lib.fakeSha256; # Will need to be updated with real hash
    };
  };

  # ---------------------------------------------------------------------------
  # Select base image based on app type
  # ---------------------------------------------------------------------------
  selectBaseImage =
    type:
    if type == "bun" then
      baseImages.bun
    else if type == "node" then
      baseImages.node
    else if type == "go" then
      baseImages.distroless
    else if type == "static" then
      baseImages.nginx
    else
      baseImages.alpine;

  # ---------------------------------------------------------------------------
  # Build runtime command based on app type
  # ---------------------------------------------------------------------------
  mkRuntimeCmd =
    {
      type,
      port,
      customCmd ? null,
    }:
    if customCmd != null then
      [ customCmd ]
    else if type == "bun" then
      [
        "/usr/local/bin/bun"
        "/app/.output/server/index.mjs"
      ]
    else if type == "node" then
      [
        "node"
        "/app/dist/index.js"
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
      [
        "/bin/sh"
        "-c"
        "echo 'No runtime command configured'"
      ];

  # ---------------------------------------------------------------------------
  # Create container environment variables
  # ---------------------------------------------------------------------------
  mkContainerEnv =
    {
      appCfg,
      port,
      awsConfig ? null,
    }:
    let
      baseEnv = [
        "NODE_ENV=production"
        "PORT=${toString port}"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      ];

      flyEnv = lib.optionals (appCfg.deployment.fly.env or { } != { }) (
        lib.mapAttrsToList (k: v: "${k}=${v}") appCfg.deployment.fly.env
      );

      awsEnv = lib.optionals (awsConfig != null) [
        "AWS_REGION=${awsConfig.region or "us-west-2"}"
        "AWS_WEB_IDENTITY_TOKEN_FILE=/tmp/fly-oidc-token"
        "AWS_ROLE_ARN=${awsConfig.roleArn or ""}"
      ];
    in
    baseEnv ++ flyEnv ++ awsEnv;

in
rec {
  inherit
    baseImages
    selectBaseImage
    mkRuntimeCmd
    mkContainerEnv
    flyOidc
    ;

  # ===========================================================================
  # mkDeployContainer - Build a container image for an app
  # ===========================================================================
  mkDeployContainer =
    {
      appName,
      appCfg,
      projectRoot,
      awsConfig ? null,
    }:
    let
      deployCfg = appCfg.deployment or { };
      containerCfg = deployCfg.container or { };
      flyCfg = deployCfg.fly or { };

      appPath = appCfg.path or "apps/${appName}";
      appType = containerCfg.type or "bun";
      port = containerCfg.port or 3000;
      flyAppName = flyCfg.appName or appName;

      # Whether to use AWS OIDC authentication
      useAwsOidc = (containerCfg.aws.enable or false) && awsConfig != null;

      # Build the app output bundle (impure - uses local build)
      # The user must run the build task first
      appOutputDir = projectRoot + "/${appPath}/.output";
      appBundle = pkgsLinux.runCommand "${appName}-bundle" { } ''
        mkdir -p $out
        if [ -d "${builtins.filterSource (path: type: true) appOutputDir}" ]; then
          cp -R ${builtins.filterSource (path: type: true) appOutputDir}/* $out/
        else
          echo "Warning: No .output directory found at ${appOutputDir}" >&2
          mkdir -p $out/server $out/public
        fi
      '';

      # Create entrypoint
      entrypoint =
        if useAwsOidc then
          flyOidc.mkEntrypoint {
            sessionPrefix = appName;
            chamberService = containerCfg.aws.chamberService or "${appName}/prod";
            skipChamber = containerCfg.aws.chamberService or null == null;
            extraRuntimeInputs = lib.optionals (containerCfg.aws.chamberService or null != null) [
              pkgsLinux.sops
            ];
          }
        else
          flyOidc.mkSimpleEntrypoint { };

      # Container configuration
      containerConfig = {
        entrypoint = [
          "${entrypoint}/bin/${if useAwsOidc then "fly-oidc-entrypoint" else "fly-entrypoint"}"
        ];
        WorkingDir = "/app";
        Env = mkContainerEnv { inherit appCfg port awsConfig; };
        ExposedPorts = {
          "${toString port}/tcp" = { };
        };
        User = "65534:65534"; # nobody user for security
        Cmd = mkRuntimeCmd {
          type = appType;
          inherit port;
          customCmd = containerCfg.entrypoint or null;
        };
      };

      # Base packages to include
      basePackages = [
        pkgsLinux.cacert
        pkgsLinux.bashInteractive
        entrypoint
      ];

      # AWS-related packages
      awsPackages = lib.optionals useAwsOidc [
        pkgsLinux.chamber
      ];

      # App bundle layer
      appLayer = pkgsLinux.runCommand "${appName}-app-layer" { } ''
        mkdir -p $out/app/.output
        cp -r ${appBundle}/* $out/app/.output/
      '';

    in
    nix2containerPkgs.nix2container.buildImage {
      name = flyAppName;
      tag = "latest";
      fromImage = selectBaseImage appType;

      layers = [
        (nix2containerPkgs.nix2container.buildLayer {
          reproducible = false;
          copyToRoot = basePackages ++ awsPackages ++ [ appLayer ];
        })
      ];

      config = containerConfig;
    };

  # ===========================================================================
  # mkContainerDerivations - Build containers for all deployable apps
  # ===========================================================================
  mkContainerDerivations =
    {
      apps,
      projectRoot,
      sstConfig ? null,
    }:
    let
      deployableApps = lib.filterAttrs (_: appCfg: (appCfg.deployment.enable or false)) apps;

      # Get AWS config from SST if available
      awsConfig =
        if sstConfig != null && (sstConfig.enable or false) then
          {
            region = sstConfig.region or "us-west-2";
            roleArn = sstConfig.iam.role-name or null;
          }
        else
          null;
    in
    lib.mapAttrs (
      appName: appCfg:
      mkDeployContainer {
        inherit
          appName
          appCfg
          projectRoot
          awsConfig
          ;
      }
    ) deployableApps;
}
