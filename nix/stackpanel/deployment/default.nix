# ==============================================================================
# Deployment Module
#
# Aggregates all deployment provider modules.
# 
# Supported providers:
#   - cloudflare: Cloudflare Workers (edge, serverless)
#   - fly: Fly.io (containers, VMs)
#
# Usage:
#   stackpanel.deployment.defaultProvider = "cloudflare";  # or "fly"
#
#   stackpanel.apps.web.deployment = {
#     enable = true;
#     provider = "cloudflare";  # optional, uses defaultProvider
#   };
# ==============================================================================
{
  imports = [
    ./options.nix # Shared deployment options
    ./fly # Fly.io (container-based)
    ./cloudflare # Cloudflare Workers (edge)
  ];
}
