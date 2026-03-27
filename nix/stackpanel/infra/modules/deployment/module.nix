# ==============================================================================
# infra/modules/deployment/module.nix
#
# Deployment infra module — provisions app hosting via Alchemy.
#
# Reads `framework` × `deployment.host` from each app's config and registers
# a single infra module that creates the appropriate alchemy resources.
#
# The actual TypeScript lives in index.ts (static) and receives pure-data
# inputs via the standard infra inputs JSON — no inlined TS in Nix.
#
# Supported matrix (framework × host → alchemy resource):
#   tanstack-start × cloudflare → TanStackStart
#   nextjs         × cloudflare → Nextjs
#   vite           × cloudflare → cloudflare.Vite
#   hono           × cloudflare → cloudflare.Worker
#   astro          × cloudflare → Astro
#   remix          × cloudflare → Remix (Worker-based)
#   *              × fly        → Fly container (handled separately)
#
# Usage:
#   stackpanel.apps.web = {
#     framework = "tanstack-start";
#     deployment = {
#       enable = true;
#       host = "cloudflare";
#       bindings = [ "DATABASE_URL" "CORS_ORIGIN" "BETTER_AUTH_SECRET" ];
#       secrets = [ "DATABASE_URL" "BETTER_AUTH_SECRET" ];
#     };
#   };
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;

  # ---------------------------------------------------------------------------
  # Derive the active framework name from framework.<name>.enable flags
  # Returns null if none enabled.
  # ---------------------------------------------------------------------------
  frameworkNames = [
    "tanstack-start"
    "nextjs"
    "vite"
    "hono"
    "astro"
    "remix"
    "nuxt"
  ];

  getFramework =
    appCfg:
    let
      enabled = lib.filter (name: appCfg.framework.${name}.enable or false) frameworkNames;
    in
    if enabled == [ ] then null else lib.head enabled;

  # ---------------------------------------------------------------------------
  # Resolve host for an app (per-app host overrides global defaultHost)
  # ---------------------------------------------------------------------------
  getHost = appCfg: appCfg.deployment.host or cfg.deployment.defaultHost;

  # ---------------------------------------------------------------------------
  # Collect deployable apps for infra module.
  #
  # IMPORTANT: Fly deploys are handled by the Fly deployment module
  # (flyctl + fly.toml). This infra module currently provisions Cloudflare and
  # AWS EC2 deployments.
  # ---------------------------------------------------------------------------
  supportedHosts = [
    "cloudflare"
    "aws"
  ];

  deployableApps = lib.filterAttrs (
    _: appCfg:
    (appCfg.deployment.enable or false)
    && (getFramework appCfg) != null
    && lib.elem (getHost appCfg) supportedHosts
  ) (cfg.apps or { });

  hasDeployableApps = deployableApps != { };

  # ---------------------------------------------------------------------------
  # Determine which hosts are in use (for npm dependencies)
  # ---------------------------------------------------------------------------
  hosts = lib.unique (lib.mapAttrsToList (_: appCfg: getHost appCfg) deployableApps);

  hasCloudflare = lib.elem "cloudflare" hosts;
  hasAws = lib.elem "aws" hosts;
  # ---------------------------------------------------------------------------
  # Build pure-data inputs for the TS module
  # ---------------------------------------------------------------------------
  appInputs = lib.mapAttrs (
    appName: appCfg:
    let
      fw = getFramework appCfg;
      fwCfg = appCfg.framework.${fw};
      cfCfg = appCfg.deployment.cloudflare or { };
      awsCfg = appCfg.deployment.aws or { };
      globalAwsCfg = cfg.deployment.aws or { };
    in
    {
      framework = fw;
      host = getHost appCfg;
      path = appCfg.path or "apps/${appName}";
      bindings = appCfg.deployment.bindings;
      secrets = appCfg.deployment.secrets;
    }
    // lib.optionalAttrs ((getHost appCfg) == "cloudflare") {
      cloudflare = {
        workerName = cfCfg.workerName or appName;
        route = cfCfg.route or null;
        compatibility = cfCfg.compatibility or "node";
      };
    }
    // lib.optionalAttrs ((getHost appCfg) == "aws") {
      aws = {
        region = awsCfg.region or globalAwsCfg.region;
        availabilityZone = awsCfg."availability-zone" or null;
        imageId = awsCfg."image-id" or null;
        instanceType = awsCfg."instance-type" or globalAwsCfg."instance-type";
        keyName = awsCfg."key-name" or null;
        port = awsCfg.port or globalAwsCfg.port;
        parameterPath = awsCfg."parameter-path" or null;
        httpCidrBlocks = awsCfg."http-cidr-blocks" or [ ];
        sshCidrBlocks = awsCfg."ssh-cidr-blocks" or [ ];
        rootVolumeSize = awsCfg."root-volume-size" or null;
        vpcCidrBlock = awsCfg."vpc-cidr-block" or null;
        subnetCidrBlock = awsCfg."subnet-cidr-block" or null;
        tags = awsCfg.tags or { };
        osType = awsCfg."os-type" or "amazon-linux";
      };
    }
    # Include framework-specific options as extra keys
    // lib.optionalAttrs (fw == "vite") {
      ssr = fwCfg.ssr or false;
      assetsDir = fwCfg."assets-dir" or "dist";
    }
    // lib.optionalAttrs (fw == "hono") {
      entrypoint = fwCfg.entrypoint or "src/index.ts";
    }
    // lib.optionalAttrs (fw == "nextjs") {
      output = fwCfg.output or "standalone";
    }
  ) deployableApps;

  # ---------------------------------------------------------------------------
  # Aggregate npm dependencies based on hosts in use
  # ---------------------------------------------------------------------------
  baseDeps = {
    # alchemy is always needed
  };

  cloudflareDeps = lib.optionalAttrs hasCloudflare {
    # alchemy/cloudflare is part of the alchemy package
  };

  awsDeps = lib.optionalAttrs hasAws {
    "@aws-sdk/client-ssm" = "^3.953.0";
  };

  # Future: flyDeps, vercelDeps
  allDeps = baseDeps // cloudflareDeps // awsDeps;

  # ---------------------------------------------------------------------------
  # Declare outputs (one URL per deployed app)
  # ---------------------------------------------------------------------------
  appOutputs = lib.mapAttrs' (
    appName: _:
    lib.nameValuePair "${appName}Url" {
      description = "Deployed URL for ${appName}";
      sensitive = false;
      sync = true;
    }
  ) deployableApps;

in
{
  config = lib.mkIf hasDeployableApps {
    # Auto-enable the infra system
    stackpanel.infra.enable = lib.mkDefault true;

    # Register as an infra module
    stackpanel.infra.modules.deployment = {
      name = "App Deployment";
      description = "Deploys apps to their configured hosts (${lib.concatStringsSep ", " hosts})";
      path = ./module;
      inputs = {
        apps = appInputs;
        cloudflare = {
          compatibilityDate = cfg.deployment.cloudflare.compatibilityDate or null;
          defaultRoute = cfg.deployment.cloudflare.defaultRoute or null;
        };
        aws = {
          region = cfg.deployment.aws.region or null;
          instanceType = cfg.deployment.aws."instance-type" or null;
          port = cfg.deployment.aws.port or null;
          artifact = {
            bucket = cfg.deployment.aws.artifact.bucket or null;
            keyPrefix = cfg.deployment.aws.artifact."key-prefix" or null;
          };
        };
      };
      dependencies = allDeps;
      outputs = appOutputs;
    };
  };
}
