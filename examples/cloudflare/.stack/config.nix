# ==============================================================================
# .stack/config.nix
#
# Stackpanel configuration for the Cloudflare edge deployment example.
# See the full options reference in the main stackpanel repo:
#   nix/stackpanel/core/options/
# ==============================================================================
{
  enable = true;
  name = "example-cloudflare";
  github = "acme/example-cloudflare";

  cli.enable = true;
  theme.enable = true;
  ide.enable = true;
  ide.vscode.enable = true;

  apps = {
    web = {
      name = "Web";
      path = "apps/web";
      domain = "web";

      framework.tanstack-start.enable = true;
      deployment = {
        enable = true;
        host = "cloudflare";
        bindings = [
          "API_BASE_URL"
          "BETTER_AUTH_SECRET"
        ];
        secrets = [
          "BETTER_AUTH_SECRET"
        ];
      };
    };

    api = {
      name = "API";
      path = "apps/api";
      domain = "api";

      framework.hono.enable = true;
      deployment = {
        enable = true;
        host = "cloudflare";
        bindings = [
          "DATABASE_URL"
          "JWT_SECRET"
        ];
        secrets = [
          "DATABASE_URL"
          "JWT_SECRET"
        ];
      };
    };
  };
}
