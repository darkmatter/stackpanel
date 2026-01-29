# ==============================================================================
# deployment.nix
#
# Deployment configuration options for stackpanel apps.
#
# Configures global deployment settings and per-app deployment targets.
# Supports multiple providers: Cloudflare Workers (edge) and Fly.io (containers).
#
# Global options:
#   - defaultProvider: Default provider for all apps (cloudflare or fly)
#   - fly.*: Fly.io global settings (organization, region)
#   - cloudflare.*: Cloudflare global settings (accountId, compatibility)
#
# Per-app options are added via appModules in the provider modules:
#   - deployment.enable: Enable deployment for this app
#   - deployment.provider: Override the default provider
#   - deployment.fly.*: Fly.io specific options
#   - deployment.cloudflare.*: Cloudflare specific options
#
# Usage:
#   stackpanel.deployment = {
#     defaultProvider = "cloudflare";
#     fly.organization = "my-org";
#     cloudflare.accountId = "abc123";
#   };
#
#   stackpanel.apps.web.deployment = {
#     enable = true;
#     provider = "fly";  # Override for this app
#   };
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.deployment = {
    enable = lib.mkEnableOption "deployment module" // {
      default = true;
    };

    defaultProvider = lib.mkOption {
      type = lib.types.enum [
        "cloudflare"
        "fly"
      ];
      default = "cloudflare";
      description = ''
        Default deployment provider for apps.

        - cloudflare: Cloudflare Workers (edge, serverless, V8 isolates)
        - fly: Fly.io (containers, VMs, full Linux environment)

        Individual apps can override this with deployment.provider.
      '';
      example = "fly";
    };

    # -------------------------------------------------------------------------
    # Fly.io global settings
    # -------------------------------------------------------------------------
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
        example = "lax";
      };

      registryPrefix = lib.mkOption {
        type = lib.types.str;
        default = "registry.fly.io";
        description = "Container registry prefix for Fly.io.";
      };
    };

    # -------------------------------------------------------------------------
    # Cloudflare global settings
    # -------------------------------------------------------------------------
    cloudflare = {
      accountId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Cloudflare account ID (from dashboard).";
      };

      compatibilityDate = lib.mkOption {
        type = lib.types.str;
        default = "2024-01-01";
        description = "Workers compatibility date for API versioning.";
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
