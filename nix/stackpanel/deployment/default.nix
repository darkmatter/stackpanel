# ==============================================================================
# Deployment Module
#
# Aggregates all deployment provider modules.
#
# Supported providers:
#   - cloudflare: Cloudflare Workers (edge, serverless)
#   - fly: Fly.io (containers, VMs)
#
# Each provider module defines its own global options and adds per-app options via appModules.
# See fly/module.nix and cloudflare/module.nix for provider-specific options.
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
