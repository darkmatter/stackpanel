# ==============================================================================
# options.nix - Unified Deployment Options
#
# Shared deployment configuration options for all providers.
# Provider-specific options are defined in their respective modules.
#
# Usage:
#   stackpanel.deployment = {
#     defaultProvider = "cloudflare";  # or "fly"
#   };
#
#   stackpanel.apps.web = {
#     deployment = {
#       enable = true;
#       provider = "cloudflare";  # inherits from defaultProvider if not set
#     };
#   };
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.deployment = {
    defaultProvider = lib.mkOption {
      type = lib.types.enum [
        "fly"
        "cloudflare"
      ];
      default = "cloudflare";
      description = ''
        Default deployment provider for apps.

        - cloudflare: Cloudflare Workers (edge, serverless)
        - fly: Fly.io (containers, VMs)
      '';
    };
  };
}
