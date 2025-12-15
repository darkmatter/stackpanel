# Example devenv.nix using stackpanel
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
