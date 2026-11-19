# ==============================================================================
# Deployment Module
#
# Aggregates the bundled providers. External modules register additional hosts and backends.
#
# Includes:
#   - alchemy: shared Alchemy SDK/codegen/runtime for hosted deploy backends
#   - cloudflare: Cloudflare Workers (edge, serverless)
#   - aws: AWS EC2 deployments
#
# Each deployment submodule defines its own options and wiring:
#   - deployment/alchemy: shared Alchemy runtime and generated helpers
#   - deployment/cloudflare: Cloudflare-specific deployment options
#   - deployment/aws: AWS-specific deployment options
#
# The actual deployment is handled by the deployment infra module at
# infra/modules/deployment/, which reads each app's `framework` × `host`
# config and creates the appropriate alchemy resources.
#
# Usage:
#   stackpanel.deployment.defaultHost = "cloudflare";
#
#   stackpanel.apps.web = {
#     framework.tanstack-start.enable = true;
#     deployment = {
#       enable = true;
#       backend = "alchemy";
#       host = "cloudflare";
#       bindings = [ "DATABASE_URL" "CORS_ORIGIN" ];
#       secrets = [ "DATABASE_URL" ];
#     };
#   };
# ==============================================================================
{ lib, config, ... }:
{
  imports = [
    ./alchemy # Shared hosted-deploy Alchemy plumbing
    ./cloudflare # Cloudflare Workers (edge)
    ./aws # AWS EC2 deployments
  ];

  options.stackpanel.deployment = {
    enable = lib.mkEnableOption "deployment module" // {
      default = true;
    };
    defaultHost = lib.mkOption {
      type = lib.types.enum (builtins.attrNames config.stackpanel.deploymentHosts);
      default = "cloudflare";
      description = "Registered deployment host to use when an app does not specify a host.";
      example = "aws";
    };
  };

  # Preserve the bundled host choices, including Vercel as a configuration
  # target. Cloudflare and external providers (e.g. Fly) register themselves.
  config.stackpanel.deploymentHosts = {
    aws = {
      label = "AWS";
      module = "infra";
    };
    vercel = {
      label = "Vercel";
      module = "deploy";
    };
  };
  config.stackpanel.deployBackends.alchemy.label = "Alchemy";
}
