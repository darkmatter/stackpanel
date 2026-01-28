# apps.nix - Application configuration
# type: sp-app
# See: https://stackpanel.dev/docs/apps
#
# Commands (dev, build, test, lint, format) are automatically provided
# based on app type (bun, go, etc.) via Nix-native flake outputs:
#   nix build .#<app>       - Build for production
#   nix run .#<app>-dev     - Run dev server
#   nix flake check         - Run all tests and lints
{
  # Example bun app:
  # web = {
  #   name = "Web App";
  #   description = "Frontend web application";
  #   path = "apps/web";
  #   type = "bun";
  #   port = 3000;
  #   domain = "web.local";
  #   environments.dev = {
  #     DATABASE_URL = "ref+sops://.stackpanel/secrets/dev.yaml#/DATABASE_URL";
  #     PORT = "3000";
  #   };
  # };
}
