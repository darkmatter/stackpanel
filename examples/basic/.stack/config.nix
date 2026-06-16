# ==============================================================================
# .stack/config.nix
#
# Stackpanel configuration for the basic single-app example.
# See the full options reference in the main stackpanel repo:
#   nix/stackpanel/core/options/
# ==============================================================================
{
  enable = true;
  name = "example-basic";
  github = "acme/example-basic";

  cli.enable = true;
  theme.enable = true;
  ide.enable = true;
  ide.vscode.enable = true;

  apps = {
    web = {
      name = "Web";
      description = "Frontend app";
      path = "apps/web";
      domain = "web";
    };
  };
}
