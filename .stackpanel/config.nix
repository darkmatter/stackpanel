# ==============================================================================
# stackpanel.nix
#
# Stackpanel-specific options for the stackpanel repository itself.
# This file contains only stackpanel.* options (without the prefix, since
# it's imported directly into the stackpanel namespace).
#
# Configures:
#   - Theme and IDE integrations (VSCode)
#   - AWS Roles Anywhere authentication
#   - Step CA for internal certificate management
#   - MOTD (Message of the Day) with helpful commands and hints
#
# Imported by devshell.nix into the `stackpanel = { ... }` block.
# ==============================================================================
{
  # Enable core stackpanel features
  enable = true;
  debug = true;
  theme.enable = true;
  ide.enable = true;
  ide.vscode.enable = true;
  cli.enable = false;

  # AWS Roles Anywhere via stackpanel's AWS module
  aws.roles-anywhere = {
    enable = true;
    region = "us-west-2";
    account-id = "950224716579";
    role-name = "darkmatter-dev";
    trust-anchor-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:trust-anchor/c99a9383-6be1-48ba-8e63-c3ab6b7069cb";
    profile-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:profile/4e72b392-9074-4e53-8cd0-1ba50856d1ca";
  };

  # Step CA
  step-ca = {
    enable = true;
    ca-url = "https://ca.internal:443";
    ca-fingerprint = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
    provisioner = "Authentik";
    prompt-on-shell = true;
    cert-name = "device";
  };



  # MOTD content
  motd.enable = true;
  motd.commands = [
    {
      name = "aws-creds-env";
      description = "Export AWS credentials to environment";
    }
  ];
}
