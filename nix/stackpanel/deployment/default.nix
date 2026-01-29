# ==============================================================================
# Deployment Module
#
# Aggregates all deployment provider modules.
#
# Supported providers:
#   - cloudflare: Cloudflare Workers (edge, serverless)
#   - fly: Fly.io (containers, VMs)
#
# Global options are defined in core/options/deployment.nix.
# Each provider module adds per-app options via appModules.
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
    ./fly # Fly.io (container-based)
    ./cloudflare # Cloudflare Workers (edge)
  ];
}
