# ==============================================================================
# .stackpanel/config.nix
#
# Stackpanel configuration for this project.
# All options here are under the `stackpanel.*` namespace.
#
# Documentation: https://stackpanel.dev/docs
# ==============================================================================
{
  enable = true;

  # ---------------------------------------------------------------------------
  # CLI - Stackpanel command-line tools
  # ---------------------------------------------------------------------------
  cli.enable = true;

  # ---------------------------------------------------------------------------
  # Theme - Starship prompt with stackpanel styling
  # ---------------------------------------------------------------------------
  theme.enable = true;

  # ---------------------------------------------------------------------------
  # IDE Integration - Auto-generate editor config files
  # ---------------------------------------------------------------------------
  ide.enable = true;
  ide.vscode.enable = true;

  # ---------------------------------------------------------------------------
  # MOTD - Message of the day shown on shell entry
  # ---------------------------------------------------------------------------
  motd.enable = true;
  motd.commands = [
    {
      name = "dev";
      description = "Start development server";
    }
    {
      name = "build";
      description = "Build the project";
    }
  ];

  # ---------------------------------------------------------------------------
  # AWS Certificate Auth - Passwordless AWS access via Roles Anywhere
  # ---------------------------------------------------------------------------
  # aws.roles-anywhere = {
  #   enable = true;
  #   region = "us-west-2";
  #   account-id = "123456789012";
  #   role-name = "dev-role";
  #   trust-anchor-arn = "arn:aws:rolesanywhere:us-west-2:123456789012:trust-anchor/...";
  #   profile-arn = "arn:aws:rolesanywhere:us-west-2:123456789012:profile/...";
  # };

  # ---------------------------------------------------------------------------
  # Step CA - Internal certificate management
  # ---------------------------------------------------------------------------
  # step-ca = {
  #   enable = true;
  #   ca-url = "https://ca.internal:443";
  #   ca-fingerprint = "your-fingerprint-here";
  # };

  # ---------------------------------------------------------------------------
  # Global Services - Shared development services
  # ---------------------------------------------------------------------------
  # globalServices = {
  #   enable = true;
  #   project-name = "myproject";
  #   postgres.enable = true;
  #   redis.enable = true;
  #   minio.enable = true;
  # };

  # ---------------------------------------------------------------------------
  # Caddy - Local HTTPS reverse proxy
  # ---------------------------------------------------------------------------
  # caddy = {
  #   enable = true;
  #   project-name = "myproject";
  # };
}
