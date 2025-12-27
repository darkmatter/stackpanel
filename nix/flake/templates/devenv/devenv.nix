# ==============================================================================
# devenv.nix (Template)
#
# Example devenv.nix configuration demonstrating stackpanel integration.
# This template shows how to configure a development environment with
# stackpanel features like AWS Roles Anywhere, Step CA, and secrets.
#
# Copy this file to your project and customize the stackpanel options.
#
# Available stackpanel features:
#   - stackpanel.aws.certAuth: AWS Roles Anywhere certificate authentication
#   - stackpanel.network.step: Step CA certificate management
#   - stackpanel.secrets: Encrypted secrets management with age
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}: {
  # Basic packages
  packages = [pkgs.git];

  # Enable stackpanel features
  stackpanel = {
    # AWS Roles Anywhere (uncomment to enable)
    # aws.certAuth = {
    #   enable = true;
    #   accountId = "123456789012";
    #   roleName = "my-dev-role";
    #   trustAnchorArn = "arn:aws:rolesanywhere:...";
    #   profileArn = "arn:aws:rolesanywhere:...";
    # };

    # Step CA certificates (uncomment to enable)
    # network.step = {
    #   enable = true;
    #   caUrl = "https://ca.internal:443";
    #   caFingerprint = "your-fingerprint-here";
    # };

    # Secrets (uncomment to enable)
    # secrets = {
    #   enable = true;
    #   envFile = ./.env.local;
    # };
  };

  # Languages
  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_20;
  };

  # Processes (optional)
  # processes.dev.exec = "npm run dev";

  enterShell = ''
    echo "Welcome to your stackpanel environment!"
  '';
}
