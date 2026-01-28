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

    # ---------------------------------------------------------------------------
    # Fly.io global settings
    # ---------------------------------------------------------------------------
    fly = {
      organization = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Fly.io organization for all apps.";
        example = "my-org";
      };

      defaultRegion = lib.mkOption {
        type = lib.types.str;
        default = "iad";
        description = "Default Fly.io region for new apps.";
      };
    };

    # ---------------------------------------------------------------------------
    # Cloudflare global settings
    # ---------------------------------------------------------------------------
    cloudflare = {
      accountId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Cloudflare account ID.";
      };

      compatibilityDate = lib.mkOption {
        type = lib.types.str;
        default = "2024-01-01";
        description = "Workers compatibility date.";
      };

      defaultRoute = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Default custom domain route pattern.";
        example = "*.example.com/*";
      };
    };
  };
}
