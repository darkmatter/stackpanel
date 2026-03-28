# ==============================================================================
# Deployment Module
#
# Aggregates all deployment provider modules.
#
# Includes:
#   - alchemy: shared Alchemy SDK/codegen/runtime for hosted deploy backends
#   - cloudflare: Cloudflare Workers (edge, serverless)
#   - fly: Fly.io (containers, VMs)
#   - aws: AWS EC2 deployments
#
# Each deployment submodule defines its own options and wiring:
#   - deployment/alchemy: shared Alchemy runtime and generated helpers
#   - deployment/cloudflare: Cloudflare-specific deployment options
#   - deployment/aws: AWS-specific deployment options
#   - deployment/fly: Fly-specific deployment options
#
# The actual deployment is handled by the deployment infra module at
# infra/modules/deployment/, which reads each app's `framework` × `host`
# config and creates the appropriate alchemy resources.
#
# Usage:
#   stackpanel.deployment.defaultHost = "cloudflare";
#
#   stackpanel.apps.web = {
#     framework = "tanstack-start";
#     deployment = {
#       enable = true;
#       host = "cloudflare";
#       bindings = [ "DATABASE_URL" "CORS_ORIGIN" ];
#       secrets = [ "DATABASE_URL" ];
#     };
#   };
# ==============================================================================
{
  imports = [
    ./alchemy # Shared hosted-deploy Alchemy plumbing
    ./fly # Fly.io (container-based)
    ./cloudflare # Cloudflare Workers (edge)
    ./aws # AWS EC2 deployments
  ];
}
