# ==============================================================================
# module.nix - Cloudflare Workers Per-App Options
#
# Adds cloudflare-specific options to each app's deployment config via
# appModules. These are optional overrides — the actual deployment is
# handled by the deployment infra module at infra/modules/deployment/.
#
# The core deployment options (enable, host, bindings, secrets) live in
# core/options/apps.nix. This module only adds cloudflare-specific extras.
#
# Usage:
#   stackpanel.apps.web = {
#     framework = "tanstack-start";
#     deployment = {
#       enable = true;
#       host = "cloudflare";
#       bindings = [ "DATABASE_URL" "CORS_ORIGIN" ];
#       secrets = [ "DATABASE_URL" ];
#       # Cloudflare-specific overrides (optional):
#       cloudflare.workerName = "my-custom-name";
#       cloudflare.route = "app.example.com/*";
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

  # Import schema for SpField definitions
  cloudflareSchema = import ./schema.nix { inherit lib; };
  sp = import ../../db/lib/field.nix { inherit lib; };

  # ---------------------------------------------------------------------------
  # Per-app Cloudflare deployment options (added via appModules)
  # ---------------------------------------------------------------------------
  cloudflareAppModule =
    { lib, name, ... }:
    {
      options.deployment.cloudflare = {
        workerName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = cloudflareSchema.fields.workerName.description;
          example = cloudflareSchema.fields.workerName.example or null;
        };

        route = sp.asOption cloudflareSchema.fields.route;

        compatibility = lib.mkOption {
          type = lib.types.enum [
            "node"
            "browser"
          ];
          default = cloudflareSchema.fields.compatibility.default or "node";
          description = cloudflareSchema.fields.compatibility.description;
        };

        kvNamespaces = sp.asOption cloudflareSchema.fields.kvNamespaces;
        d1Databases = sp.asOption cloudflareSchema.fields.d1Databases;
        r2Buckets = sp.asOption cloudflareSchema.fields.r2Buckets;
      };
    };

in
{
  # ===========================================================================
  # Options - Global Cloudflare deployment settings
  # ===========================================================================
  options.stackpanel.deployment.cloudflare = {
    accountId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Cloudflare account ID. Can also be set via CLOUDFLARE_ACCOUNT_ID env var.
      '';
      example = "abc123def456...";
    };

    compatibilityDate = lib.mkOption {
      type = lib.types.str;
      default = "2024-01-01";
      description = ''
        Workers API compatibility date. Use a recent date for new projects.
      '';
      example = "2024-12-01";
    };

    defaultRoute = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Default custom domain route pattern for Workers.
        Individual apps can override this in their cloudflare.route option.
      '';
      example = "*.example.com/*";
    };
  };

  # ===========================================================================
  # Config - Register the appModule (always, so options are available)
  # ===========================================================================
  config = {
    stackpanel.appModules = [ cloudflareAppModule ];
  };
}
